import Foundation
import PocketCastsDataModel
import PocketCastsUtils
#if canImport(UIKit)
import UIKit
#endif

/// Facade for local-first file sync (mirrors RefreshManager's role for
/// server sync).
///
/// Owns the sync folder handle, this device's identity, the uploads
/// pipeline, and the flush/ingest/apply cycle. The app configures it at
/// startup and pokes `syncNow()` from cadence triggers.
public actor FileSyncManager {
    public static let shared = FileSyncManager()

    // MARK: Configuration persistence

    private enum DefaultsKey {
        static let deviceID = "FileSync.deviceId"
        static let enabled = "FileSync.enabled"
        static let folderKind = "FileSync.folderKind"
        static let bookmarkData = "FileSync.rootBookmark"
        static let mirrorEnabled = "FileSync.mirrorEnabled"
        static let mirrorWifiOnly = "FileSync.mirrorWifiOnly"
        static let mirrorMaxBytes = "FileSync.mirrorMaxBytes"
    }

    private let dataManager: DataManager
    private let defaults: UserDefaults
    private var folder: (any SyncFolder)?
    private var uploadsScanner: UploadsScanner?
    private var materializer: UploadMaterializer?
    private var mirrorScanner: PodcastMirrorScanner?
    private var mirrorMaterializer: PodcastMirrorMaterializer?
    private var isSupportedFile: @Sendable (String) -> Bool = { _ in false }
    private var localPathResolver: @Sendable (UserEpisode) -> String = { _ in "" }
    private var episodeLocalPathResolver: @Sendable (Episode) -> String = { _ in "" }
    private var isUnmeteredConnection: @Sendable () -> Bool = { false }
    private var onUploadsChanged: (@Sendable () -> Void)?
    private var delegate: (any FileSyncDelegate)?

    private var syncPassRunning = false
    private var uploadManifestState: UploadManifestState?

    private(set) var lastScanDate: Date?
    private(set) var lastError: String?

    struct UploadManifestState {
        var uploads: [String: MergeEngine.UploadEntry]
        var uploadTombstones: [String: OpStamp]

        init(mergedState: MergeEngine.MergedState) {
            uploads = mergedState.uploads
            uploadTombstones = mergedState.uploadTombstones
        }

        mutating func merge(_ mergedState: MergeEngine.MergedState) {
            for (uuid, upload) in mergedState.uploads {
                if let existing = uploads[uuid], upload.stamp <= existing.stamp {
                    continue
                }
                uploads[uuid] = upload
            }

            for (uuid, tombstone) in mergedState.uploadTombstones {
                if let existing = uploadTombstones[uuid], tombstone <= existing {
                    continue
                }
                uploadTombstones[uuid] = tombstone
            }
        }

        var manifest: [Filesync_UploadIdentity] {
            uploads.values
                .filter { upload in
                    guard let tombstoneStamp = uploadTombstones[upload.identity.uuid] else { return true }
                    return upload.stamp > tombstoneStamp
                }
                .map(\.identity)
        }
    }

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

    /// The app injects file-type support, local cache path resolution, and
    /// the upload-list reload bridge once at startup.
    public func configure(
        isSupportedFile: @escaping @Sendable (String) -> Bool,
        localPathResolver: @escaping @Sendable (UserEpisode) -> String,
        episodeLocalPathResolver: @escaping @Sendable (Episode) -> String = { _ in "" },
        isUnmeteredConnection: @escaping @Sendable () -> Bool = { false },
        onUploadsChanged: (@Sendable () -> Void)? = nil
    ) {
        self.isSupportedFile = isSupportedFile
        self.localPathResolver = localPathResolver
        self.episodeLocalPathResolver = episodeLocalPathResolver
        self.isUnmeteredConnection = isUnmeteredConnection
        self.onUploadsChanged = onUploadsChanged
    }

    // MARK: Podcast mirror configuration

    /// Whether downloaded podcast audio is mirrored into (and pulled from) the sync
    /// folder's `Podcast Mirrors/` area. Off by default: mirrors can be large.
    public var isMirroringEnabled: Bool {
        defaults.bool(forKey: DefaultsKey.mirrorEnabled)
    }

    public func setMirroringEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: DefaultsKey.mirrorEnabled)
    }

    /// When true (the default), mirrored audio is only pulled from the folder on
    /// unmetered connections; publishing this device's own downloads is always allowed.
    public var isMirroringWifiOnly: Bool {
        defaults.object(forKey: DefaultsKey.mirrorWifiOnly) == nil
            ? true
            : defaults.bool(forKey: DefaultsKey.mirrorWifiOnly)
    }

    public func setMirroringWifiOnly(_ wifiOnly: Bool) {
        defaults.set(wifiOnly, forKey: DefaultsKey.mirrorWifiOnly)
    }

    /// Per-sync-pass budget for pulled mirror audio in bytes; 0 = unlimited.
    public var mirroringMaxBytesPerPass: Int64 {
        Int64(defaults.integer(forKey: DefaultsKey.mirrorMaxBytes))
    }

    public func setMirroringMaxBytesPerPass(_ bytes: Int64) {
        defaults.set(Int(bytes), forKey: DefaultsKey.mirrorMaxBytes)
    }

    /// Write hook: publishes a just-downloaded episode's audio into the mirror area.
    /// Cheap no-op when sync or mirroring is off.
    public func mirrorDownloadedEpisode(episodeUuid: String) async {
        guard isEnabled, isMirroringEnabled, let mirrorMaterializer else { return }
        do {
            _ = try await mirrorMaterializer.mirror(episodeUuid: episodeUuid)
        } catch {
            FileLog.shared.addMessage("FileSync mirrors: publish of \(episodeUuid) failed: \(error)")
        }
    }

    /// Destructive recovery affordance: forgets everything this device knows about the
    /// folder's history (cursors and snapshot progress) and re-seeds the full local
    /// library into the journal, then runs a sync pass. Use when a folder is suspected
    /// out of step; it converges via the normal union-join merge.
    public func resetAndRebootstrap() async throws {
        guard folder != nil else { throw SyncFolderError.ubiquityUnavailable }
        dataManager.deleteAllFileSyncCursors()
        uploadManifestState = nil
        try FileSyncBootstrap(dataManager: dataManager).seedLocalState()
        FileLog.shared.addMessage("FileSync: reset & re-bootstrap requested")
        await syncNow()
    }

    public func configureDelegate(_ delegate: any FileSyncDelegate) {
        self.delegate = delegate
    }

    // MARK: Enable / disable

    /// Silently enables iCloud-backed sync when available and nothing was
    /// configured yet. The app decides whether to call this via feature
    /// flag/product gating.
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
            dataManager.deleteAllFileSyncCursors()
            defaults.set(false, forKey: DefaultsKey.enabled)
        }
        try await enable(folder: BookmarkSyncFolder(bookmarkData: pickedFolderBookmark),
                         kind: .securityScopedBookmark)
        defaults.set(pickedFolderBookmark, forKey: DefaultsKey.bookmarkData)
    }

    private func enable(folder: any SyncFolder, kind: SyncFolderKind) async throws {
        await self.folder?.stopChangeMonitoring()
        try await SyncFolderBootstrapper.prepare(folder: folder, deviceID: deviceID)
        self.folder = folder
        self.uploadsScanner = UploadsScanner(
            folder: folder,
            dataManager: dataManager,
            isSupportedFile: isSupportedFile)
        self.materializer = UploadMaterializer(
            folder: folder,
            dataManager: dataManager,
            localPathResolver: localPathResolver)
        let mirrorMaterializer = PodcastMirrorMaterializer(
            folder: folder,
            dataManager: dataManager,
            localPathResolver: episodeLocalPathResolver)
        self.mirrorMaterializer = mirrorMaterializer
        self.mirrorScanner = PodcastMirrorScanner(
            folder: folder,
            dataManager: dataManager,
            materializer: mirrorMaterializer)
        uploadManifestState = nil

        let firstEnableForFolder = !defaults.bool(forKey: DefaultsKey.enabled)
            || defaults.string(forKey: DefaultsKey.folderKind) != kind.rawValue
        defaults.set(true, forKey: DefaultsKey.enabled)
        defaults.set(kind.rawValue, forKey: DefaultsKey.folderKind)
        lastError = nil
        FileLog.shared.addMessage("FileSync: enabled (\(kind.rawValue)) as device \(deviceID)")

        if firstEnableForFolder {
            try FileSyncBootstrap(dataManager: dataManager).seedLocalState()
        }
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

    public func disable() {
        let currentFolder = folder
        folder = nil
        uploadsScanner = nil
        materializer = nil
        mirrorScanner = nil
        mirrorMaterializer = nil
        uploadManifestState = nil
        defaults.set(false, forKey: DefaultsKey.enabled)
        defaults.removeObject(forKey: DefaultsKey.bookmarkData)
        dataManager.deleteAllFileSyncCursors()
        Task { await currentFolder?.stopChangeMonitoring() }
    }

    // MARK: Upload operations

    public func importUpload(from sourceURL: URL, group: String? = nil) async throws -> String {
        guard let materializer else { throw SyncFolderError.ubiquityUnavailable }
        let relative = try await materializer.importUpload(from: sourceURL, group: group)
        uploadManifestState = nil
        onUploadsChanged?()
        return relative
    }

    public func materializeUpload(episodeUuid: String) async throws {
        guard let materializer, let uploadsScanner else { throw SyncFolderError.ubiquityUnavailable }
        let (_, folderURL) = try await materializer.materialize(episodeUuid: episodeUuid)
        try await uploadsScanner.resolveIdentity(episodeUuid: episodeUuid, materializedURL: folderURL, manifest: [])
        uploadManifestState = nil
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
        dataManager.journalFileSyncDelete(entityType: .userEpisode, uuid: episodeUuid)
        uploadManifestState = nil
        onUploadsChanged?()
        if let relativePath = episode.folderRelativePath {
            try await folder.coordinatedDelete("\(FileSyncFormat.uploadsDirectory)/\(relativePath)")
        }
    }

    public func forgetDevice(id peerDeviceID: String) async throws {
        guard let folder else { throw SyncFolderError.ubiquityUnavailable }
        guard peerDeviceID != deviceID else { return }
        try await folder.coordinatedDelete(FileSyncFormat.deviceDirectory(deviceID: peerDeviceID))
        dataManager.deleteFileSyncCursor(peerDeviceId: peerDeviceID)
    }

    // MARK: Sync cycle

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

            let flushResult = try await flusher.flush(
                settings: delegate?.collectChangedSettings() ?? [],
                stats: delegate?.collectStats())

            let ingest = try await ingestor.ingest()
            let hasRemoteChanges = ingest.opsRead > 0 || ingest.state.hasContent
            let uploadState = try await currentUploadManifestState(
                ingestor: ingestor,
                ingestState: ingest.state)
            if hasRemoteChanges {
                let applyResult = await applier.apply(ingest.state)
                if applyResult.queueChanged
                    || applyResult.episodesApplied > 0
                    || applyResult.podcastsApplied > 0
                    || applyResult.bookmarksApplied > 0 {
                    onUploadsChanged?()
                }
            }
            let uploadsManifest = uploadState.manifest
            ingestor.commit(ingest)

            let scanResult = try await uploadsScanner.scan(manifest: uploadsManifest)
            if scanResult.created + scanResult.adopted + scanResult.moved + scanResult.reset + scanResult.removed > 0 {
                uploadManifestState = nil
                onUploadsChanged?()
            }

            if isMirroringEnabled, let mirrorScanner {
                let materializeIn = isMirroringWifiOnly ? isUnmeteredConnection() : true
                let mirrorResult = try await mirrorScanner.scan(
                    materializeIn: materializeIn,
                    maxMaterializeBytes: mirroringMaxBytesPerPass)
                if mirrorResult.materialized > 0 {
                    onUploadsChanged?()
                }
            }

            let snapshotWriter = SnapshotWriter(folder: folder, dataManager: dataManager, deviceID: deviceID)
            try await snapshotWriter.snapshotIfNeeded(headSeq: flushResult.headSeq, nowMs: nowMs) {
                try await ingestor.fullMerge()
            }

            try await SyncFolderBootstrapper.writeDeviceInfo(
                folder: folder,
                deviceID: deviceID,
                name: await deviceDisplayName(),
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
                    name: info?.name ?? unknownDeviceName(),
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

    private func unknownDeviceName() -> String {
        NSLocalizedString(
            "file_sync_unknown_device",
            comment: "Fallback label for a file-sync peer device when its device name cannot be read")
    }

    private func deviceDisplayName() async -> String {
        #if canImport(UIKit) && !os(watchOS)
        return await MainActor.run { UIDevice.current.name }
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

    private func currentUploadManifestState(
        ingestor: RemoteOpIngestor,
        ingestState: MergeEngine.MergedState
    ) async throws -> UploadManifestState {
        if var cachedState = uploadManifestState {
            cachedState.merge(ingestState)
            uploadManifestState = cachedState
            return cachedState
        }

        let fullState = UploadManifestState(mergedState: try await ingestor.fullMerge())
        uploadManifestState = fullState
        return fullState
    }
}

private extension MergeEngine.MergedState {
    var hasContent: Bool {
        !podcasts.isEmpty
            || !episodes.isEmpty
            || !playlists.isEmpty
            || !folders.isEmpty
            || !bookmarks.isEmpty
            || !tombstones.isEmpty
            || !upNextOps.isEmpty
            || !settings.isEmpty
            || !statsByDevice.isEmpty
            || !uploads.isEmpty
            || !uploadTombstones.isEmpty
    }
}
