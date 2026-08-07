import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Facade for the uploads folder that backs the Files library.
///
/// Owns the folder handle and the uploads pipeline: audio files placed in
/// the folder's `Uploads/` directory appear as user episodes on every
/// device pointing at the same folder. The app configures it at startup
/// and pokes `syncNow()` from cadence triggers.
public actor FileSyncManager {
    public static let shared = FileSyncManager()

    // MARK: Configuration persistence

    private enum DefaultsKey {
        static let enabled = "FileSync.enabled"
        static let folderKind = "FileSync.folderKind"
        static let bookmarkData = "FileSync.rootBookmark"
    }

    private let dataManager: DataManager
    private let defaults: UserDefaults
    private var folder: (any SyncFolder)?
    private var uploadsScanner: UploadsScanner?
    private var materializer: UploadMaterializer?
    private var isSupportedFile: @Sendable (String) -> Bool = { _ in false }
    private var localPathResolver: @Sendable (UserEpisode) -> String = { _ in "" }
    private var onUploadsChanged: (@Sendable () -> Void)?

    private var syncPassRunning = false
    private var rescanRequested = false

    private(set) var lastScanDate: Date?
    private(set) var lastError: String?

    public init(dataManager: DataManager = .sharedManager, defaults: UserDefaults = .standard) {
        self.dataManager = dataManager
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        defaults.bool(forKey: DefaultsKey.enabled)
    }

    /// The app injects file-type support, local cache path resolution, and
    /// the upload-list reload bridge once at startup.
    public func configure(
        isSupportedFile: @escaping @Sendable (String) -> Bool,
        localPathResolver: @escaping @Sendable (UserEpisode) -> String,
        onUploadsChanged: (@Sendable () -> Void)? = nil
    ) {
        self.isSupportedFile = isSupportedFile
        self.localPathResolver = localPathResolver
        self.onUploadsChanged = onUploadsChanged
    }

    // MARK: Enable

    /// Silently enables the iCloud-backed folder when available and nothing
    /// was configured yet.
    public func enableICloudIfUnconfigured() async {
        guard defaults.object(forKey: DefaultsKey.enabled) == nil,
              UbiquitySyncFolder.isAvailable else { return }
        do {
            try await enable(folder: UbiquitySyncFolder(), kind: .ubiquity)
        } catch {
            lastError = "\(error)"
            FileLog.shared.addMessage("FileSync: silent iCloud enable failed: \(error)")
        }
    }

    public func enable(pickedFolderBookmark: Data) async throws {
        if defaults.data(forKey: DefaultsKey.bookmarkData) != pickedFolderBookmark {
            defaults.set(false, forKey: DefaultsKey.enabled)
        }
        try await enable(folder: BookmarkSyncFolder(bookmarkData: pickedFolderBookmark),
                         kind: .securityScopedBookmark)
        defaults.set(pickedFolderBookmark, forKey: DefaultsKey.bookmarkData)
    }

    private func enable(folder: any SyncFolder, kind: SyncFolderKind) async throws {
        await self.folder?.stopChangeMonitoring()
        try await folder.createDirectory(FileSyncFormat.uploadsDirectory)
        self.folder = folder
        self.uploadsScanner = UploadsScanner(
            folder: folder,
            dataManager: dataManager,
            isSupportedFile: isSupportedFile)
        self.materializer = UploadMaterializer(
            folder: folder,
            dataManager: dataManager,
            localPathResolver: localPathResolver)

        defaults.set(true, forKey: DefaultsKey.enabled)
        defaults.set(kind.rawValue, forKey: DefaultsKey.folderKind)
        lastError = nil
        FileLog.shared.addMessage("FileSync: uploads folder enabled (\(kind.rawValue))")

        await folder.startChangeMonitoring { [weak self] _ in
            Task { await self?.syncNow() }
        }
    }

    public func restoreIfEnabled() async {
        guard isEnabled, folder == nil else { return }
        do {
            if defaults.string(forKey: DefaultsKey.folderKind) == SyncFolderKind.securityScopedBookmark.rawValue,
               let bookmark = defaults.data(forKey: DefaultsKey.bookmarkData) {
                try await enable(folder: BookmarkSyncFolder(bookmarkData: bookmark),
                                 kind: .securityScopedBookmark)
            } else if defaults.string(forKey: DefaultsKey.folderKind) == SyncFolderKind.securityScopedBookmark.rawValue {
                throw SyncFolderError.fileNotFound("missing bookmark data for restore")
            } else {
                try await enable(folder: UbiquitySyncFolder(), kind: .ubiquity)
            }
        } catch {
            lastError = "\(error)"
            FileLog.shared.addMessage("FileSync: restore failed: \(error)")
        }
    }

    // MARK: Upload operations

    public func importUpload(from sourceURL: URL, group: String? = nil) async throws -> String {
        guard let materializer else { throw SyncFolderError.ubiquityUnavailable }
        let relative = try await materializer.importUpload(from: sourceURL, group: group)
        onUploadsChanged?()
        return relative
    }

    public func materializeUpload(episodeUuid: String) async throws {
        guard let materializer, let uploadsScanner else { throw SyncFolderError.ubiquityUnavailable }
        let (_, folderURL) = try await materializer.materialize(episodeUuid: episodeUuid)
        try await uploadsScanner.resolveIdentity(episodeUuid: episodeUuid, materializedURL: folderURL)
        onUploadsChanged?()
    }

    public func evictUpload(episodeUuid: String) async {
        await materializer?.evict(episodeUuid: episodeUuid)
        onUploadsChanged?()
    }

    public func deleteUpload(episodeUuid: String) async throws {
        guard let folder else { throw SyncFolderError.ubiquityUnavailable }
        guard let episode = dataManager.findUserEpisode(uuid: episodeUuid) else { return }
        let localPath = localPathResolver(episode)
        if !localPath.isEmpty {
            try? FileManager.default.removeItem(atPath: localPath)
        }
        dataManager.delete(userEpisodeUuid: episodeUuid)
        onUploadsChanged?()
        if let relativePath = episode.folderRelativePath {
            try await folder.coordinatedDelete("\(FileSyncFormat.uploadsDirectory)/\(relativePath)")
        }
    }

    // MARK: Scan cycle

    public func syncNow() async {
        guard isEnabled, let uploadsScanner else { return }
        guard !syncPassRunning else {
            rescanRequested = true
            return
        }
        syncPassRunning = true
        defer { syncPassRunning = false }

        repeat {
            rescanRequested = false
            do {
                let scanResult = try await uploadsScanner.scan()
                if scanResult.created + scanResult.moved + scanResult.reset + scanResult.removed > 0 {
                    onUploadsChanged?()
                }
                lastScanDate = Date()
                lastError = nil
            } catch {
                lastError = "\(error)"
                FileLog.shared.addMessage("FileSync: uploads scan failed: \(error)")
            }
        } while rescanRequested
    }

    // MARK: Inspector

    public func status() async -> FileSyncStatus {
        let kind = defaults.string(forKey: DefaultsKey.folderKind).flatMap(SyncFolderKind.init(rawValue:))
        return FileSyncStatus(
            isEnabled: isEnabled,
            folderKind: folder != nil ? kind : nil,
            lastScanDate: lastScanDate,
            lastError: lastError)
    }
}
