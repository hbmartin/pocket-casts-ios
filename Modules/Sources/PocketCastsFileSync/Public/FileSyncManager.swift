import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Facade for local-first file sync (mirrors RefreshManager's role for
/// server sync).
///
/// Owns the sync folder handle, this device's identity, the uploads
/// pipeline, and — as the engine grows — the flush/ingest cycle. The app
/// configures it at startup and pokes `syncNow()` from its cadence
/// triggers (pause/seek/queue-edit notifications, backgrounding, the 60s
/// playback heartbeat, and BGAppRefresh).
public actor FileSyncManager {
    public static let shared = FileSyncManager()

    // MARK: Configuration persistence

    private enum DefaultsKey {
        static let deviceID = "FileSync.deviceId"
        static let enabled = "FileSync.enabled"
        static let folderKind = "FileSync.folderKind"
        static let bookmarkData = "FileSync.rootBookmark"
    }

    private let dataManager: DataManager
    private let defaults: UserDefaults
    private var folder: (any SyncFolder)?
    private var uploadsScanner: UploadsScanner?
    private var isSupportedFile: @Sendable (String) -> Bool = { _ in false }

    private(set) var lastScanDate: Date?
    private(set) var lastError: String?

    public init(dataManager: DataManager = .sharedManager, defaults: UserDefaults = .standard) {
        self.dataManager = dataManager
        self.defaults = defaults
    }

    /// Stable identity of this install in the sync folder; created on first
    /// use.
    public var deviceID: String {
        if let existing = defaults.string(forKey: DefaultsKey.deviceID) {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: DefaultsKey.deviceID)
        return created
    }

    public var isEnabled: Bool {
        defaults.bool(forKey: DefaultsKey.enabled)
    }

    /// The app injects file-type support (FileTypeUtil) once at startup.
    public func configure(isSupportedFile: @escaping @Sendable (String) -> Bool) {
        self.isSupportedFile = isSupportedFile
    }

    // MARK: Enable / disable

    /// Silently enables iCloud-backed sync when available and nothing was
    /// configured yet (first-launch onboarding path). No-op otherwise.
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

    /// Enables sync against a user-picked folder (bookmark from the app's
    /// document picker flow).
    public func enable(pickedFolderBookmark: Data) async throws {
        try await enable(folder: BookmarkSyncFolder(bookmarkData: pickedFolderBookmark),
                         kind: .securityScopedBookmark)
        defaults.set(pickedFolderBookmark, forKey: DefaultsKey.bookmarkData)
    }

    private func enable(folder: any SyncFolder, kind: SyncFolderKind) async throws {
        try await SyncFolderBootstrapper.prepare(folder: folder, deviceID: deviceID)
        self.folder = folder
        self.uploadsScanner = UploadsScanner(
            folder: folder, dataManager: dataManager, isSupportedFile: isSupportedFile)
        defaults.set(true, forKey: DefaultsKey.enabled)
        defaults.set(kind.rawValue, forKey: DefaultsKey.folderKind)
        lastError = nil
        FileLog.shared.addMessage("FileSync: enabled (\(kind.rawValue)) as device \(deviceID)")
    }

    /// Reattaches the persisted folder on app launch.
    public func restoreIfEnabled() async {
        guard isEnabled, folder == nil else { return }
        do {
            if defaults.string(forKey: DefaultsKey.folderKind) == SyncFolderKind.securityScopedBookmark.rawValue,
               let bookmark = defaults.data(forKey: DefaultsKey.bookmarkData) {
                try await enable(folder: BookmarkSyncFolder(bookmarkData: bookmark),
                                 kind: .securityScopedBookmark)
            } else {
                try await enable(folder: UbiquitySyncFolder(), kind: .ubiquity)
            }
        } catch {
            lastError = "\(error)"
            FileLog.shared.addMessage("FileSync: restore failed: \(error)")
        }
    }

    /// Disabling keeps the folder contents (they belong to the user) but
    /// clears local cursors so a re-enable bootstraps cleanly.
    public func disable() {
        folder = nil
        uploadsScanner = nil
        defaults.set(false, forKey: DefaultsKey.enabled)
        defaults.removeObject(forKey: DefaultsKey.bookmarkData)
        dataManager.deleteAllFileSyncCursors()
    }

    // MARK: Sync cycle (Phase 1: uploads reconciliation + device presence)

    /// Runs one sync pass. Currently: refresh device presence and reconcile
    /// the uploads folder. The op flush/ingest cycle lands here as the
    /// engine integration grows.
    public func syncNow() async {
        guard isEnabled, let folder, let uploadsScanner else { return }
        do {
            try await SyncFolderBootstrapper.writeDeviceInfo(
                folder: folder,
                deviceID: deviceID,
                name: deviceDisplayName(),
                model: deviceModelIdentifier(),
                appVersion: appVersion(),
                headSeq: UInt64(max(0, dataManager.fileSyncCursor(peerDeviceId: deviceID)?.headSeq ?? 0)),
                nowMs: Int64(Date().timeIntervalSince1970 * 1000))
            try await uploadsScanner.scan(manifest: [])
            lastScanDate = Date()
            lastError = nil
        } catch {
            lastError = "\(error)"
            FileLog.shared.addMessage("FileSync: sync pass failed: \(error)")
        }
    }

    // MARK: Inspector

    public func status() async -> FileSyncStatus {
        var devices: [FileSyncStatus.Device] = []
        if let folder {
            let peerIDs = (try? await SyncFolderBootstrapper.peerDeviceIDs(
                folder: folder, ownDeviceID: deviceID)) ?? []
            for peerID in peerIDs + [deviceID] {
                let path = "\(FileSyncFormat.deviceDirectory(deviceID: peerID))/\(FileSyncFormat.deviceInfoFileName)"
                let info: Filesync_DeviceInfo? = try? await folder.coordinatedRead(path) { url in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? Filesync_DeviceInfo(serializedBytes: data)
                }
                devices.append(FileSyncStatus.Device(
                    deviceID: peerID,
                    name: info?.name ?? "Unknown device",
                    model: info?.model ?? "",
                    appVersion: info?.appVersion ?? "",
                    lastSeen: info.flatMap { $0.lastSeenMs > 0 ? Date(timeIntervalSince1970: Double($0.lastSeenMs) / 1000) : nil },
                    isThisDevice: peerID == deviceID))
            }
        }
        let kind = defaults.string(forKey: DefaultsKey.folderKind).flatMap(SyncFolderKind.init(rawValue:))
        return FileSyncStatus(
            isEnabled: isEnabled,
            folderKind: folder != nil ? kind : nil,
            pendingOpCount: dataManager.unflushedFileSyncCount(),
            lastScanDate: lastScanDate,
            lastError: lastError,
            devices: devices.sorted { ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast) })
    }

    // MARK: Device metadata

    private func deviceDisplayName() -> String {
        #if canImport(UIKit) && !os(watchOS)
        return ProcessInfo.processInfo.hostName
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }

    private func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}
