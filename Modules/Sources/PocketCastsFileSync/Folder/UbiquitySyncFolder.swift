import Foundation

/// A sync folder rooted at the app's iCloud Drive container's Documents
/// directory (user-visible in the Files app when the container is declared
/// public-scope in Info.plist).
///
/// Requires the iCloud Documents entitlement and an `NSUbiquitousContainers`
/// Info.plist entry — see docs/file-sync-format.md.
public actor UbiquitySyncFolder: SyncFolder {
    nonisolated public let kind: SyncFolderKind = .ubiquity

    private let containerIdentifier: String?
    private var resolvedRoot: URL?
    private var monitor: UbiquityChangeMonitor?

    /// - Parameter containerIdentifier: nil uses the app's first entitlement
    ///   container (`iCloud.<bundle id>`).
    public init(containerIdentifier: String? = nil) {
        self.containerIdentifier = containerIdentifier
    }

    /// True when an iCloud account with Documents enabled is signed in.
    public static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    public func rootURL() async throws -> URL {
        if let resolvedRoot { return resolvedRoot }
        // url(forUbiquityContainerIdentifier:) performs filesystem work and
        // must stay off the main thread.
        let identifier = containerIdentifier
        let container = await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: identifier)
        }.value
        guard let container else {
            throw SyncFolderError.ubiquityUnavailable
        }
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        resolvedRoot = documents
        return documents
    }

    public func list(_ relativeDir: String) async throws -> [FolderEntry] {
        let root = try await rootURL()
        return try await CoordinatedFileIO.list(root: root, relativeDir: relativeDir)
    }

    public func coordinatedRead<T: Sendable>(_ relativePath: String, _ body: @Sendable @escaping (URL) throws -> T) async throws -> T {
        let root = try await rootURL()
        let url = root.appendingPathComponent(relativePath)
        _ = try await materialize(url, relativePath: relativePath)
        return try await CoordinatedFileIO.read(url, body)
    }

    public func coordinatedWrite(_ relativePath: String, data: Data) async throws {
        let root = try await rootURL()
        try await CoordinatedFileIO.write(root.appendingPathComponent(relativePath), data: data)
    }

    public func createDirectory(_ relativePath: String) async throws {
        let root = try await rootURL()
        try await CoordinatedFileIO.createDirectory(root.appendingPathComponent(relativePath, isDirectory: true))
    }

    public func coordinatedCopy(from localURL: URL, to relativePath: String) async throws {
        let root = try await rootURL()
        try await CoordinatedFileIO.copy(from: localURL, to: root.appendingPathComponent(relativePath))
    }

    public func coordinatedDelete(_ relativePath: String) async throws {
        let root = try await rootURL()
        try await CoordinatedFileIO.delete(root.appendingPathComponent(relativePath))
    }

    public func ensureMaterialized(_ relativePath: String) async throws -> URL {
        let root = try await rootURL()
        let url = root.appendingPathComponent(relativePath)
        return try await materialize(url, relativePath: relativePath)
    }

    /// Triggers download of an evicted/placeholder item and polls its
    /// downloading status until current.
    private func materialize(_ url: URL, relativePath: String, timeout: TimeInterval = 300) async throws -> URL {
        let keys: Set<URLResourceKey> = [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey]

        func status() -> URLUbiquitousItemDownloadingStatus? {
            guard let values = try? url.resourceValues(forKeys: keys), values.isUbiquitousItem == true else {
                return nil
            }
            return values.ubiquitousItemDownloadingStatus
        }

        // Local (non-ubiquitous or already current) items need no work.
        guard let initial = status(), initial != .current else {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            // Not on disk under its real name: possibly a .icloud
            // placeholder that has never been requested.
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            return try await waitUntilCurrent(url, relativePath: relativePath, timeout: timeout, status: status)
        }

        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        return try await waitUntilCurrent(url, relativePath: relativePath, timeout: timeout, status: status)
    }

    private func waitUntilCurrent(
        _ url: URL, relativePath: String, timeout: TimeInterval,
        status: () -> URLUbiquitousItemDownloadingStatus?
    ) async throws -> URL {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if let current = status() {
                if current == .current { return url }
            } else if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw SyncFolderError.materializeTimeout(relativePath)
    }

    public func startChangeMonitoring(_ handler: @escaping @Sendable (FolderChangeHint) -> Void) async {
        guard monitor == nil else { return }
        let monitor = await UbiquityChangeMonitor(handler: handler)
        self.monitor = monitor
        await monitor.start()
    }

    public func stopChangeMonitoring() async {
        await monitor?.stop()
        monitor = nil
    }
}

/// NSMetadataQuery wrapper. Queries need a run loop, so this lives on the
/// main actor; results are forwarded as coalesced change hints.
@MainActor
final class UbiquityChangeMonitor {
    private let handler: @Sendable (FolderChangeHint) -> Void
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []

    init(handler: @escaping @Sendable (FolderChangeHint) -> Void) {
        self.handler = handler
    }

    func start() {
        guard query == nil else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        // Sync state churn is frequent during propagation; coalesce.
        query.notificationBatchingInterval = 2.0

        let center = NotificationCenter.default
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering,
                     NSNotification.Name.NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] notification in
                let paths = Self.paths(from: notification)
                MainActor.assumeIsolated {
                    self?.deliver(paths: paths)
                }
            })
        }
        self.query = query
        query.start()
    }

    nonisolated private static func paths(from notification: Notification) -> [String] {
        var paths: [String] = []
        let changedKeys = [NSMetadataQueryUpdateAddedItemsKey,
                           NSMetadataQueryUpdateChangedItemsKey,
                           NSMetadataQueryUpdateRemovedItemsKey]
        for key in changedKeys {
            guard let items = notification.userInfo?[key] as? [NSMetadataItem] else { continue }
            for item in items {
                if let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                    paths.append(path)
                }
            }
        }
        return paths
    }

    private func deliver(paths: [String]) {
        handler(FolderChangeHint(changedPaths: paths))
    }

    func stop() {
        query?.stop()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        query = nil
    }
}
