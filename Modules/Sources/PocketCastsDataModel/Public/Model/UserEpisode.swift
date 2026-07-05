import Foundation
import GRDB
import GRDBMacros

@GRDBRecord(table: "SJUserEpisode")
public struct UserEpisode: BaseEpisode, Identifiable, Equatable, Hashable, Sendable {
    public init() {}

    public var id = 0 as Int64
    public var addedDate: Date?
    @GRDBNullDateAsEpoch
    public var lastDownloadAttemptDate: Date?
    public var downloadErrorDetails: String?
    public var downloadTaskId: String?
    public var downloadUrl: String?
    public var episodeStatus = 0 as Int32
    public var fileType: String?
    // Note: contentType is saved separately via saveContentType() method.
    // The legacy SQL code doesn't include it in columnNames, so we ignore it for GRDB compatibility.
    @GRDBIgnore
    public var contentType: String?
    public var playedUpTo: Double = 0
    public var duration: Double = 0
    public var durationModified = 0 as Int64
    public var playingStatus = 1 as Int32
    public var autoDownloadStatus = 0 as Int32
    public var publishedDate: Date?
    public var sizeInBytes = 0 as Int64
    public var playingStatusModified = 0 as Int64
    public var playedUpToModified = 0 as Int64
    public var title: String?
    public var titleModified = 0 as Int64
    public var uuid = ""
    public var playbackErrorDetails: String?
    public var cachedFrameCount = 0 as Int64
    public var uploadStatus = 0 as Int32
    public var uploadTaskId: String?
    public var imageUrl: String?
    public var imageModified = 0 as Int64
    public var imageColor = 0 as Int32
    public var imageColorModified = 0 as Int64
    public var hasCustomImage = false
    @GRDBIgnore
    public var hasOnlyUuid = false
    // Note: These properties exist on the model but were never added to the SJUserEpisode table.
    // The legacy SQL code doesn't persist them, so we ignore them for GRDB compatibility.
    @GRDBIgnore
    public var deselectedChapters: String?
    @GRDBIgnore
    public var deselectedChaptersModified = 0 as Int64

    // UserEpisode's are never archived or starred
    @GRDBIgnore
    public var archived = false
    @GRDBIgnore
    public var keepEpisode = false
    @GRDBIgnore
    public var wasDeleted = false

    public var hasBookmarks: Bool {
        DataManager.sharedManager.bookmarks.bookmarkCount(forEpisode: uuid) > 0
    }

    public var isUserEpisode: Bool {
        true
    }

    public func displayableTitle() -> String {
        title ?? ""
    }

    public func parentIdentifier() -> String {
        DataConstants.userEpisodeFakePodcastId
    }

    public func jumpToOnStart() -> TimeInterval {
        0
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

    public func videoPodcast() -> Bool {
        if let fileType, fileType.startsWith(string: "video/") {
            return true
        }

        return false
    }

    public func mayContainChapters() -> Bool {
        guard let fileType else { return false }

        return (fileType.caseInsensitiveCompare("audio/x-m4a") == .orderedSame || fileType.caseInsensitiveCompare("audio/x-m4b") == .orderedSame || fileType.caseInsensitiveCompare("audio/mp3") == .orderedSame || fileType.caseInsensitiveCompare("audio/mpeg") == .orderedSame)
    }

    public func taggableId() -> Int {
        Int(truncatingIfNeeded: id)
    }

    // Equality/hashing are uuid-consistent, matching the other struct records
    public static func == (lhs: UserEpisode, rhs: UserEpisode) -> Bool {
        lhs.uuid == rhs.uuid
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }

    public func uploaded() -> Bool {
        uploadStatus == UploadStatus.uploaded.rawValue
    }

    public func uploadFailed() -> Bool {
        uploadStatus == UploadStatus.uploadFailed.rawValue
    }

    public func uploading() -> Bool {
        uploadStatus == UploadStatus.uploading.rawValue
    }

    public func uploadQueued() -> Bool {
        uploadStatus == UploadStatus.queued.rawValue
    }

    public func uploadWaitingForWifi() -> Bool {
        uploadStatus == UploadStatus.waitingForWifi.rawValue
    }
}
