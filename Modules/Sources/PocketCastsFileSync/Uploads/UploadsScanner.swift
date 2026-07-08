import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Discovers audio files in the uploads area of the sync folder and keeps
/// SJUserEpisode rows in step with them. The decision logic lives in
/// `UploadScanPlanner` (pure); this type is the side-effecting shell.
public actor UploadsScanner {
    private let folder: any SyncFolder
    private let dataManager: DataManager
    private let isSupportedFile: @Sendable (String) -> Bool

    /// - Parameter isSupportedFile: filename -> supported, the app injects
    ///   FileTypeUtil.isSupportedUserFileType so the module doesn't own the
    ///   format list.
    public init(folder: any SyncFolder, dataManager: DataManager,
                isSupportedFile: @escaping @Sendable (String) -> Bool) {
        self.folder = folder
        self.dataManager = dataManager
        self.isSupportedFile = isSupportedFile
    }

    public struct ScanResult: Sendable {
        public var created = 0
        public var adopted = 0
        public var moved = 0
        public var reset = 0
        public var removed = 0
    }

    /// One full reconcile pass over the Uploads/ directory.
    /// `manifest` is the merged cross-device upload identity list from
    /// `MergeEngine.MergedState.uploads` (minus tombstoned entries).
    @discardableResult
    public func scan(manifest: [Filesync_UploadIdentity]) async throws -> ScanResult {
        let listing = try await folder.list(FileSyncFormat.uploadsDirectory)
        let supported = isSupportedFile
        let media = FolderScanner.mediaFiles(in: listing) { supported($0) }
            // Planner works in paths relative to the uploads root, matching
            // UploadIdentity.relative_path.
            .map { entry in
                FolderEntry(
                    relativePath: stripUploadsPrefix(entry.relativePath),
                    sizeBytes: entry.sizeBytes,
                    mtimeMs: entry.mtimeMs,
                    isDirectory: false,
                    isPlaceholder: entry.isPlaceholder)
            }

        let known = dataManager.allFolderBackedUserEpisodes().compactMap { episode -> UploadScanPlanner.KnownEpisode? in
            guard let path = episode.folderRelativePath else { return nil }
            return UploadScanPlanner.KnownEpisode(
                uuid: episode.uuid,
                relativePath: path,
                sizeBytes: episode.sizeInBytes,
                mtimeMs: 0, // mtime isn't persisted; rename matching uses size via planner rules
                contentHash: episode.contentHash,
                isCanonical: episode.identity == .canonical)
        }

        let actions = UploadScanPlanner.plan(mediaEntries: media, knownEpisodes: known, manifest: manifest)
        var result = ScanResult()

        for action in actions {
            switch action {
            case let .createProvisional(entry, group):
                var episode = UserEpisode()
                episode.uuid = UUID().uuidString.lowercased()
                episode.addedDate = Date()
                episode.title = (entry.fileName as NSString).deletingPathExtension
                episode.sizeInBytes = entry.sizeBytes
                episode.episodeStatus = DownloadStatus.notDownloaded.rawValue
                episode.playingStatus = PlayingStatus.notPlayed.rawValue
                episode.folderRelativePath = entry.relativePath
                episode.groupName = group
                episode.identity = .provisional
                dataManager.save(episode: episode)
                result.created += 1

            case let .adoptIdentity(entry, identity):
                var episode = dataManager.findUserEpisode(uuid: identity.uuid) ?? {
                    var new = UserEpisode()
                    new.uuid = identity.uuid
                    new.addedDate = Date()
                    return new
                }()
                episode.title = identity.title.isEmpty
                    ? (entry.fileName as NSString).deletingPathExtension
                    : identity.title
                episode.sizeInBytes = identity.sizeBytes
                episode.duration = identity.durationSeconds
                episode.fileType = identity.fileType.isEmpty ? nil : identity.fileType
                episode.folderRelativePath = entry.relativePath
                episode.groupName = identity.group
                episode.contentHash = identity.sha256.isEmpty ? nil : identity.sha256
                episode.identity = identity.sha256.isEmpty ? .provisional : .canonical
                if episode.episodeStatus == 0 {
                    episode.episodeStatus = DownloadStatus.notDownloaded.rawValue
                }
                dataManager.save(episode: episode)
                result.adopted += 1

            case let .updatePath(episodeUuid, entry, group):
                if var episode = dataManager.findUserEpisode(uuid: episodeUuid) {
                    episode.folderRelativePath = entry.relativePath
                    episode.groupName = group
                    dataManager.save(episode: episode)
                    journalIdentityChange(episodeUuid: episodeUuid)
                    result.moved += 1
                }

            case let .resetIdentity(episodeUuid, entry):
                if var episode = dataManager.findUserEpisode(uuid: episodeUuid) {
                    episode.sizeInBytes = entry.sizeBytes
                    episode.contentHash = nil
                    episode.identity = .provisional
                    // The cached copy (if any) is stale bytes now.
                    episode.episodeStatus = DownloadStatus.notDownloaded.rawValue
                    dataManager.save(episode: episode)
                    result.reset += 1
                }

            case let .removeEpisode(episodeUuid):
                if let episode = dataManager.findUserEpisode(uuid: episodeUuid) {
                    dataManager.delete(userEpisodeUuid: episode.uuid)
                    dataManager.journalFileSyncDelete(entityType: .userEpisode, uuid: episode.uuid)
                    result.removed += 1
                }
            }
        }
        return result
    }

    /// Promotes a provisional episode after its file was fully materialized:
    /// hashes it, then either publishes the identity or re-keys onto the
    /// existing canonical episode owning that content.
    public func resolveIdentity(episodeUuid: String, materializedURL: URL,
                                manifest: [Filesync_UploadIdentity]) throws {
        guard var episode = dataManager.findUserEpisode(uuid: episodeUuid) else { return }
        let sha256 = try UploadIdentityResolver.sha256Hex(of: materializedURL)

        var hashOwners: [String: String] = [:]
        for identity in manifest where !identity.sha256.isEmpty {
            hashOwners[identity.sha256] = identity.uuid
        }
        for other in dataManager.allFolderBackedUserEpisodes() {
            if let hash = other.contentHash { hashOwners[hash] = other.uuid }
        }

        switch UploadScanPlanner.resolveHash(sha256, for: episodeUuid,
                                             currentHash: episode.contentHash,
                                             hashOwners: hashOwners) {
        case .unchanged:
            return
        case .promote:
            episode.contentHash = sha256
            episode.identity = .canonical
            dataManager.save(episode: episode)
            journalIdentityChange(episodeUuid: episodeUuid)
        case let .rekey(provisionalUuid, canonicalUuid):
            guard var canonical = dataManager.findUserEpisode(uuid: canonicalUuid) else { return }
            // The folder file the provisional row pointed at IS the
            // canonical content: repoint the canonical row and merge the
            // freshest playback state, then drop the duplicate row.
            canonical.folderRelativePath = episode.folderRelativePath
            canonical.groupName = episode.groupName
            if episode.playedUpToModified > canonical.playedUpToModified {
                canonical.playedUpTo = episode.playedUpTo
                canonical.playedUpToModified = episode.playedUpToModified
            }
            if episode.playingStatusModified > canonical.playingStatusModified {
                canonical.playingStatus = episode.playingStatus
                canonical.playingStatusModified = episode.playingStatusModified
            }
            dataManager.save(episode: canonical)
            dataManager.delete(userEpisodeUuid: provisionalUuid)
            journalIdentityChange(episodeUuid: canonicalUuid)
        }
    }

    private func journalIdentityChange(episodeUuid: String) {
        dataManager.journalFileSyncUpsert(
            entityType: .userEpisode, uuid: episodeUuid, changedFields: ["uploadIdentity"])
    }

    private func stripUploadsPrefix(_ path: String) -> String {
        let prefix = FileSyncFormat.uploadsDirectory + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}
