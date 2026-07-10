import Foundation

/// Path scheme for podcast-download mirrors in the sync folder.
///
/// Unlike Uploads, mirror identity needs no manifest or content hashing: podcast
/// episodes already have stable UUIDs (server-issued or deterministic local-feed
/// hashes), so identity is carried entirely by the path:
///
///     Podcast Mirrors/<podcastUuid>/<episodeUuid>.<ext>
///
/// Presence of a file means "some device mirrored this download"; episode metadata
/// and deletion sync through the regular op journal.
public enum PodcastMirrorFormat {
    public struct MirrorEntry: Sendable, Equatable {
        public let podcastUuid: String
        public let episodeUuid: String
        /// Full path relative to the sync root (includes the mirrors directory).
        public let relativePath: String
        public let sizeBytes: Int64
        public let isPlaceholder: Bool
    }

    public static func relativePath(podcastUuid: String, episodeUuid: String, fileExtension: String) -> String {
        let ext = fileExtension.isEmpty ? "mp3" : fileExtension
        return "\(FileSyncFormat.podcastMirrorsDirectory)/\(podcastUuid)/\(episodeUuid).\(ext)"
    }

    /// Parses a folder listing entry back into mirror identity; nil for anything that
    /// doesn't match the `<mirrors>/<podcastUuid>/<episodeUuid>.<ext>` shape.
    public static func entry(from folderEntry: FolderEntry) -> MirrorEntry? {
        guard !folderEntry.isDirectory else { return nil }

        let prefix = FileSyncFormat.podcastMirrorsDirectory + "/"
        guard folderEntry.relativePath.hasPrefix(prefix) else { return nil }

        let components = folderEntry.relativePath.dropFirst(prefix.count).components(separatedBy: "/")
        guard components.count == 2 else { return nil }

        let podcastUuid = components[0]
        let episodeUuid = (components[1] as NSString).deletingPathExtension
        guard !podcastUuid.isEmpty, !episodeUuid.isEmpty else { return nil }

        return MirrorEntry(
            podcastUuid: podcastUuid,
            episodeUuid: episodeUuid,
            relativePath: folderEntry.relativePath,
            sizeBytes: folderEntry.sizeBytes,
            isPlaceholder: folderEntry.isPlaceholder)
    }
}
