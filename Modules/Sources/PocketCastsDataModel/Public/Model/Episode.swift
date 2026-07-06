import Foundation
import GRDB
import GRDBMacros
import PocketCastsUtils

@GRDBRecord(table: "SJEpisode")
public struct Episode: BaseEpisode, Identifiable, Equatable, Hashable, Sendable {
    public init() {}

    private static let bonusType = "bonus"
    private static let trailerType = "trailer"

    public var id = 0 as Int64
    public var addedDate: Date?
    @GRDBNullDateAsEpoch
    public var lastDownloadAttemptDate: Date?
    public var detailedDescription: String?
    public var downloadErrorDetails: String?
    public var downloadTaskId: String?
    public var downloadUrl: String?
    public var episodeDescription: String?
    public var episodeStatus = 0 as Int32
    public var fileType: String?
    public var contentType: String?
    public var keepEpisode = false
    public var playedUpTo: Double = 0
    public var duration: Double = 0
    public var playingStatus = 0 as Int32
    public var autoDownloadStatus = 0 as Int32
    public var publishedDate: Date?
    public var sizeInBytes = 0 as Int64
    public var playingStatusModified = 0 as Int64
    public var playedUpToModified = 0 as Int64
    public var durationModified = 0 as Int64
    public var keepEpisodeModified = 0 as Int64
    public var starredModified = 0 as Int64
    public var lastPlaybackInteractionDate: Date?
    public var lastPlaybackInteractionSyncStatus = 1 as Int32
    public var title: String?
    public var uuid = ""
    public var podcastUuid = ""
    public var playbackErrorDetails: String?
    public var cachedFrameCount = 0 as Int64
    public var podcast_id = 0 as Int64
    public var episodeNumber = -1 as Int64
    public var seasonNumber = -1 as Int64
    public var episodeType: String?
    public var archived = false
    public var archivedModified = 0 as Int64
    @GRDBNullDateAsEpoch
    public var lastArchiveInteractionDate: Date?
    public var excludeFromEpisodeLimit = false
    @GRDBIgnore
    public var hasOnlyUuid = false
    public var deselectedChapters: String?
    public var deselectedChaptersModified = 0 as Int64
    public var wasDeleted = false
    public var hasGeneratedTranscript: Bool? = nil

    public var hasBookmarks: Bool {
        // This wil cause a regression in which the bookmarks won't be displayed
        // for episodes with bookmarks.
        // However, this call is happening on the main thread and can block the whole app.
        // We will re-add this again in a way that's not a blocker
        //DataManager.sharedManager.bookmarks.bookmarkCount(forEpisode: uuid) > 0
        false
    }

    public var isUserEpisode: Bool {
        false
    }

    public func displayableTitle() -> String {
        title ?? ""
    }

    public func pathToDownloadedFile(pathFinder: FilePathProtocol) -> String {
        if downloaded(pathFinder: pathFinder) {
            return pathFinder.pathForEpisode(self)
        } else if bufferedForStreaming() {
            return pathFinder.streamingBufferPathForEpisode(self)
        }

        return pathToTempFile(pathFinder: pathFinder)
    }

    public func pathToTempFile(pathFinder: FilePathProtocol) -> String {
        pathFinder.tempPathForEpisode(self)
    }

    // MARK: - State

    public func downloaded(pathFinder: FilePathProtocol) -> Bool {
        if episodeStatus != DownloadStatus.downloaded.rawValue { return false }

        let path = pathFinder.pathForEpisode(self)

        return FileManager.default.fileExists(atPath: path)
    }

    public func streamDownloaded(pathFinder: FilePathProtocol) -> Bool {
        if episodeStatus != DownloadStatus.downloadedForStreaming.rawValue { return false }

        let path = pathFinder.streamingBufferPathForEpisode(self)

        return FileManager.default.fileExists(atPath: path)
    }

    public func bufferedForStreaming() -> Bool {
        episodeStatus == DownloadStatus.downloadedForStreaming.rawValue
    }

    public func downloadFailed() -> Bool {
        episodeStatus == DownloadStatus.downloadFailed.rawValue
    }

    public func downloading() -> Bool {
        episodeStatus == DownloadStatus.downloading.rawValue
    }

    public func queued() -> Bool {
        episodeStatus == DownloadStatus.queued.rawValue
    }

    public func waitingForWifi() -> Bool {
        episodeStatus == DownloadStatus.waitingForWifi.rawValue
    }

    public func inProgress() -> Bool {
        playingStatus == PlayingStatus.inProgress.rawValue
    }

    public func played() -> Bool {
        playingStatus == PlayingStatus.completed.rawValue
    }

    public func unplayed() -> Bool {
        playingStatus == PlayingStatus.notPlayed.rawValue
    }

    public func exemptFromAutoDownload() -> Bool {
        autoDownloadStatus == AutoDownloadStatus.userDeletedFile.rawValue || autoDownloadStatus == AutoDownloadStatus.userCancelledDownload.rawValue
    }

    public func playbackError() -> Bool {
        playbackErrorDetails != nil
    }

    public func isBonus() -> Bool {
        episodeType?.lowercased() == Episode.bonusType
    }

    public func isTrailer() -> Bool {
        episodeType?.lowercased() == Episode.trailerType
    }

    public func parentIdentifier() -> String {
        podcastUuid
    }

    // MARK: - Meta

    public func videoPodcast() -> Bool {
        if let fileType, fileType.startsWith(string: "video/") {
            return true
        }

        return false
    }

    // MARK: - Helpers

    public func mayContainChapters() -> Bool {
        guard let fileType else { return false }

        return (fileType.caseInsensitiveCompare("audio/x-m4a") == .orderedSame ||
            fileType.caseInsensitiveCompare("audio/x-m4b") == .orderedSame ||
            fileType.caseInsensitiveCompare("audio/mp4") == .orderedSame ||
            fileType.caseInsensitiveCompare("audio/mp3") == .orderedSame ||
            fileType.caseInsensitiveCompare("audio/mpeg") == .orderedSame)
    }

    public func parentPodcast(dataManager: DataManager = .sharedManager) -> Podcast? {
        dataManager.findPodcast(uuid: podcastUuid, includeUnsubscribed: true)
    }

    public func taggableId() -> Int {
        Int(truncatingIfNeeded: id)
    }

    // Equality/hashing are uuid-consistent, matching the other struct records
    public static func == (lhs: Episode, rhs: Episode) -> Bool {
        lhs.uuid == rhs.uuid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }

    // MARK: - Metadata

    public struct Metadata: Decodable, Sendable {
        public let showNotes: String?
        public let image: String?

        /// Podlove chapters
        public let chapters: [EpisodeChapter]?

        /// Podcast Index chapters
        public let chaptersUrl: String?

        public struct EpisodeChapter: Decodable, Sendable {
            public let startTime: TimeInterval
            public let title: String?
            public let endTime: TimeInterval?
        }

        public let transcripts: [Transcript]
        public let pocketCastsTranscripts: [Transcript]?

        public struct Transcript: Decodable, Sendable {
            public let url: String
            public let type: String
            public let language: String?

            public init(url: String, type: String, language: String?) {
                self.url = url
                self.type = type
                self.language = language
            }
        }
    }
}
