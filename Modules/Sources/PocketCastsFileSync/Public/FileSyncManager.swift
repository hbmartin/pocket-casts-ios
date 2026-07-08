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
    private var materializer: UploadMaterializer?
    private var isSupportedFile: @Sendable (String) -> Bool = { _ in false }
    private var deviceName: String?
    private var delegate: (any FileSyncDelegate)?
    private var localPathResolver: @Sendable (UserEpisode) -> String = { _ in "" }
    /// Invoked after any pass that may have changed upload episodes; the app
    /// bridges this to its NotificationCenter reload notifications.
    private var onUploadsChanged: (@Sendable () -> Void)?

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

    /// The app injects file-type support (FileTypeUtil), the local cache
    /// path resolver (DownloadManager), and the uploads-changed bridge once
    /// at startup.
    public func configure(
        isSupportedFile: @escaping @Sendable (String) -> Bool,
        localPathResolver: @escaping @Sendable (UserEpisode) -> String,
        onUploadsChanged: (@Sendable () -> Void)? = nil
    ) {
        self.isSupportedFile = isSupportedFile
        self.localPathResolver = localPathResolver
        self.onUploadsChanged = onUploadsChanged
    }

    /// The user-facing device name (UIDevice.current.name) must be read on
    /// the main actor; the app captures it during setup and hands it over.
    public func configureDeviceMetadata(name: String) {
        deviceName = name
    }

    /// App-side capabilities bridge (playback, backfill, settings, stats).
    public func configureDelegate(_ delegate: any FileSyncDelegate) {
        self.delegate = delegate
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
        // A different root folder invalidates all read cursors and needs a
        // fresh union-join seed.
        if defaults.data(forKey: DefaultsKey.bookmarkData) != pickedFolderBookmark {
            dataManager.deleteAllFileSyncCursors()
            defaults.set(false, forKey: DefaultsKey.enabled)
        }
        try await enable(folder: BookmarkSyncFolder(bookmarkData: pickedFolderBookmark),
                         kind: .securityScopedBookmark)
        defaults.set(pickedFolderBookmark, forKey: DefaultsKey.bookmarkData)
    }

    private func enable(folder: any SyncFolder, kind: SyncFolderKind) async throws {
        try await SyncFolderBootstrapper.prepare(folder: folder, deviceID: deviceID)
        self.folder = folder
        self.uploadsScanner = UploadsScanner(
            folder: folder, dataManager: dataManager, isSupportedFile: isSupportedFile)
        self.materializer = UploadMaterializer(
            folder: folder, dataManager: dataManager, localPathResolver: localPathResolver)
        let firstEnableForFolder = !defaults.bool(forKey: DefaultsKey.enabled)
            || defaults.string(forKey: DefaultsKey.folderKind) != kind.rawValue
        defaults.set(true, forKey: DefaultsKey.enabled)
        defaults.set(kind.rawValue, forKey: DefaultsKey.folderKind)
        lastError = nil
        FileLog.shared.addMessage("FileSync: enabled (\(kind.rawValue)) as device \(deviceID)")

        if firstEnableForFolder {
            // Union join: seed the full local library into the journal with
            // historical stamps; the next sync pass flushes it and merges
            // whatever already lives in the folder. Nothing is lost on
            // either side.
            FileSyncBootstrap(dataManager: dataManager).seedLocalState()
        }
    }

    /// Reattaches the persisted folder on app launch.
    public func restoreIfEnabled() async {
        guard isEnabled, folder == nil else { return }
        do {
            if defaults.string(forKey: DefaultsKey.folderKind) == SyncFolderKind.securityScopedBookmark.rawValue {
                // A configured picked folder whose bookmark data is gone must
                // fail loudly (the UI asks for a re-pick), not silently
                // re-point sync at the iCloud container.
                guard let bookmark = defaults.data(forKey: DefaultsKey.bookmarkData) else {
                    throw SyncFolderError.bookmarkUnresolvable
                }
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
        materializer = nil
        defaults.set(false, forKey: DefaultsKey.enabled)
        defaults.removeObject(forKey: DefaultsKey.bookmarkData)
        dataManager.deleteAllFileSyncCursors()
    }

    // MARK: - Uploads operations (app-facing passthroughs)

    /// Copies a picked/shared file into the Uploads folder and returns its
    /// folder-relative path (the in-app '+' import flow).
    public func importUpload(from sourceURL: URL, group: String? = nil) async throws -> String {
        guard let materializer else { throw SyncFolderError.ubiquityUnavailable }
        let relative = try await materializer.importUpload(from: sourceURL, group: group)
        onUploadsChanged?()
        return relative
    }

    /// Materializes ("downloads") a folder-backed upload into the local
    /// cache, then resolves its content-hash identity.
    public func materializeUpload(episodeUuid: String) async throws {
        guard let materializer, let uploadsScanner else { throw SyncFolderError.ubiquityUnavailable }
        let (_, folderURL) = try await materializer.materialize(episodeUuid: episodeUuid)
        try await uploadsScanner.resolveIdentity(
            episodeUuid: episodeUuid, materializedURL: folderURL, manifest: [])
        onUploadsChanged?()
    }

    /// Evicts the local cached copy; the folder file and episode remain.
    public func evictUpload(episodeUuid: String) async {
        await materializer?.evict(episodeUuid: episodeUuid)
        onUploadsChanged?()
    }

    /// Destructive delete: removes the real file from the sync folder (the
    /// provider's trash is the undo), journals the tombstone, and removes
    /// the episode row and cached copy.
    public func deleteUpload(episodeUuid: String) async throws {
        guard let folder else { throw SyncFolderError.ubiquityUnavailable }
        guard let episode = dataManager.findUserEpisode(uuid: episodeUuid) else { return }
        if let relativePath = episode.folderRelativePath {
            try await folder.coordinatedDelete("\(FileSyncFormat.uploadsDirectory)/\(relativePath)")
        }
        await materializer?.evict(episodeUuid: episodeUuid)
        dataManager.delete(userEpisodeUuid: episodeUuid)
        dataManager.journalFileSyncDelete(entityType: .userEpisode, uuid: episodeUuid)
        onUploadsChanged?()
    }

    /// Inspector action: drops a stale peer's directory and forgets its
    /// cursor. Other devices notice via the DeviceForget op once the op
    /// flush cycle lands; locally the directory removal is immediate.
    public func forgetDevice(id peerDeviceID: String) async throws {
        guard let folder else { throw SyncFolderError.ubiquityUnavailable }
        guard peerDeviceID != deviceID else { return }
        try await folder.coordinatedDelete(FileSyncFormat.deviceDirectory(deviceID: peerDeviceID))
        dataManager.deleteFileSyncCursor(peerDeviceId: peerDeviceID)
    }

    // MARK: Sync cycle: flush → ingest → apply → scan → snapshot

    private var syncPassRunning = false

    /// Runs one full sync pass. Re-entrant calls coalesce into the running
    /// pass (the next trigger picks up anything new).
    public func syncNow() async {
        guard isEnabled, let folder, let uploadsScanner else { return }
        guard !syncPassRunning else { return }
        syncPassRunning = true
        defer { syncPassRunning = false }

        do {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let flusher = OpJournalFlusher(folder: folder, dataManager: dataManager, deviceID: deviceID)
            let ingestor = RemoteOpIngestor(folder: folder, dataManager: dataManager, deviceID: deviceID)
            let applier = RemoteOpApplier(dataManager: dataManager, delegate: delegate)

            // 1. Flush pending local changes into our own log.
            let flushResult = try await flusher.flush(
                settings: delegate?.collectChangedSettings() ?? [],
                stats: delegate?.collectStats())

            // 2. Ingest peers' new ops and apply the merged consensus.
            let ingest = try await ingestor.ingest()
            var uploadsManifest: [Filesync_UploadIdentity] = []
            if ingest.opsRead > 0 || !ingest.state.uploads.isEmpty {
                let applyResult = await applier.apply(ingest.state)
                if applyResult.queueChanged || applyResult.episodesApplied > 0 || applyResult.podcastsApplied > 0 {
                    onUploadsChanged?()
                }
                uploadsManifest = ingest.state.uploads.values
                    .filter { ingest.state.uploadTombstones[$0.identity.uuid] == nil }
                    .map(\.identity)
            }
            // Cursors advance only after apply committed: replay after a
            // crash is idempotent because everything merges LWW.
            ingestor.commit(ingest)

            // 3. Reconcile the uploads folder against the merged manifest.
            let scanResult = try await uploadsScanner.scan(manifest: uploadsManifest)
            if scanResult.created + scanResult.adopted + scanResult.moved + scanResult.reset + scanResult.removed > 0 {
                onUploadsChanged?()
            }

            // 4. Periodic snapshot + compaction (full state built lazily).
            let snapshotWriter = SnapshotWriter(folder: folder, dataManager: dataManager, deviceID: deviceID)
            try await snapshotWriter.snapshotIfNeeded(headSeq: flushResult.headSeq, nowMs: nowMs) {
                try await ingestor.fullMerge()
            }

            // 5. Presence marker.
            try await SyncFolderBootstrapper.writeDeviceInfo(
                folder: folder,
                deviceID: deviceID,
                name: deviceName ?? deviceDisplayName(),
                model: deviceModelIdentifier(),
                appVersion: appVersion(),
                headSeq: UInt64(max(0, flushResult.headSeq)),
                nowMs: nowMs)

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
                    name: info?.name ?? "",
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

    /// Fallback only: the app injects the user-facing name
    /// (UIDevice.current.name, main-actor-bound) via
    /// `configureDeviceMetadata`; this actor can't read it directly.
    private func deviceDisplayName() -> String {
        ProcessInfo.processInfo.hostName
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
