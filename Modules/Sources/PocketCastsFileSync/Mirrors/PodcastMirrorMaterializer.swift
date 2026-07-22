import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Moves podcast audio between the app's download cache and the sync folder's
/// `Podcast Mirrors/` area, in both directions. The folder is a shared cache of
/// downloaded audio: any device that downloaded an episode can publish it, and any
/// device that has the episode row can materialize the audio without re-downloading
/// from the feed's host. (Mirror of `UploadMaterializer`, minus identity resolution —
/// episode UUIDs are already stable across devices.)
public actor PodcastMirrorMaterializer {
    private let folder: any SyncFolder
    private let dataManager: DataManager
    /// Resolves an episode's local cache path; the app injects
    /// `episode.pathToDownloadedFile(pathFinder: DownloadManager.shared)`.
    private let localPathResolver: @Sendable (Episode) -> String

    public init(folder: any SyncFolder, dataManager: DataManager,
                localPathResolver: @escaping @Sendable (Episode) -> String) {
        self.folder = folder
        self.dataManager = dataManager
        self.localPathResolver = localPathResolver
    }

    /// Publishes a downloaded episode's audio into the mirror area (the write hook,
    /// called after a download completes and from the reconcile scan). No-op when the
    /// local file is missing.
    @discardableResult
    public func mirror(episodeUuid: String) async throws -> Bool {
        guard let episode = dataManager.findEpisode(uuid: episodeUuid) else { return false }

        let localPath = localPathResolver(episode)
        guard !localPath.isEmpty, FileManager.default.fileExists(atPath: localPath) else { return false }

        let fileExtension = (localPath as NSString).pathExtension
        let relativePath = PodcastMirrorFormat.relativePath(
            podcastUuid: episode.podcastUuid,
            episodeUuid: episode.uuid,
            fileExtension: fileExtension)
        let podcastDirectory = PodcastMirrorFormat.podcastDirectory(podcastUuid: episode.podcastUuid)

        try await folder.createDirectory(podcastDirectory)
        try await folder.coordinatedCopy(from: URL(fileURLWithPath: localPath), to: relativePath)
        return true
    }

    /// Copies a mirrored file into the local download cache and marks the episode
    /// downloaded — exactly where `pathToDownloadedFile` already looks, so playback
    /// needs no new code paths.
    public func materialize(entry: PodcastMirrorFormat.MirrorEntry) async throws {
        guard var episode = dataManager.findEpisode(uuid: entry.episodeUuid) else { return }
        guard episode.episodeStatus != DownloadStatus.downloaded.rawValue else { return }

        _ = try await folder.ensureMaterialized(entry.relativePath)

        let localPath = localPathResolver(episode)
        guard !localPath.isEmpty else { return }
        let localURL = URL(fileURLWithPath: localPath)

        try await folder.coordinatedRead(entry.relativePath) { sourceURL in
            try FileManager.default.createDirectory(
                at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: localURL)
        }

        episode.episodeStatus = DownloadStatus.downloaded.rawValue
        if let size = try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            episode.sizeInBytes = Int64(size)
        }
        dataManager.save(episode: episode)
    }
}
