import Foundation
import PocketCastsDataModel

/// "Downloads" a folder-backed upload: materializes the file out of the
/// sync folder into the app's local episode cache, exactly where
/// `UserEpisode.pathToDownloadedFile(pathFinder:)` already looks — so
/// playback needs no new code paths. The folder remains the source of
/// truth; the cached copy is evictable (eviction just resets the episode
/// to not-downloaded, it never removes the episode).
public actor UploadMaterializer {
    private let folder: any SyncFolder
    private let dataManager: DataManager
    /// Resolves an episode's local cache path; the app injects
    /// `episode.pathToDownloadedFile(pathFinder: DownloadManager.shared)`
    /// (a closure rather than FilePathProtocol keeps this Sendable-clean).
    private let localPathResolver: @Sendable (UserEpisode) -> String

    public init(folder: any SyncFolder, dataManager: DataManager,
                localPathResolver: @escaping @Sendable (UserEpisode) -> String) {
        self.folder = folder
        self.dataManager = dataManager
        self.localPathResolver = localPathResolver
    }

    /// Copies the episode's folder file into the local cache and marks the
    /// episode downloaded. Returns the local URL, and the materialized
    /// source URL for follow-up hashing by `UploadsScanner.resolveIdentity`.
    @discardableResult
    public func materialize(episodeUuid: String) async throws -> (localURL: URL, folderURL: URL) {
        guard let episode = dataManager.findUserEpisode(uuid: episodeUuid),
              let relativePath = episode.folderRelativePath else {
            throw SyncFolderError.fileNotFound(episodeUuid)
        }
        let folderRelative = "\(FileSyncFormat.uploadsDirectory)/\(relativePath)"
        let folderURL = try await folder.ensureMaterialized(folderRelative)

        let localPath = localPathResolver(episode)
        let localURL = URL(fileURLWithPath: localPath)
        try await folder.coordinatedRead(folderRelative) { sourceURL in
            try FileManager.default.createDirectory(
                at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: localURL)
        }

        var updated = episode
        updated.episodeStatus = DownloadStatus.downloaded.rawValue
        if let size = try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            updated.sizeInBytes = Int64(size)
        }
        dataManager.save(episode: updated)

        return (localURL, folderURL)
    }

    /// Evicts the local cached copy without touching the folder file.
    public func evict(episodeUuid: String) {
        guard let episode = dataManager.findUserEpisode(uuid: episodeUuid),
              episode.folderRelativePath != nil else { return }
        let localPath = localPathResolver(episode)
        try? FileManager.default.removeItem(atPath: localPath)
        var updated = episode
        updated.episodeStatus = DownloadStatus.notDownloaded.rawValue
        dataManager.save(episode: updated)
    }

    /// Imports a picked/shared file INTO the uploads folder (the in-app
    /// '+' flow): coordinated copy, then immediate registration without
    /// waiting for the next scan.
    public func importUpload(from sourceURL: URL, group: String?) async throws -> String {
        let fileName = sourceURL.lastPathComponent
        let relative = try Self.uploadRelativePath(fileName: fileName, group: group)
        let folderRelative = "\(FileSyncFormat.uploadsDirectory)/\(relative)"
        try await folder.coordinatedCopy(from: sourceURL, to: folderRelative)
        return relative
    }

    static func uploadRelativePath(fileName: String, group: String?) throws -> String {
        let group = try validatedGroup(group)
        return group.flatMap { "\($0)/\(fileName)" } ?? fileName
    }

    static func validatedGroup(_ group: String?) throws -> String? {
        guard let group, !group.isEmpty else { return nil }
        guard group != ".", group != "..",
              !group.contains("/"), !group.contains("\\") else {
            throw SyncFolderError.invalidPathComponent(group)
        }
        return group
    }
}
