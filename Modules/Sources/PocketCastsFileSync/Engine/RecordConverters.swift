import Foundation
import PocketCastsDataModel
import SwiftProtobuf

/// DB model <-> sync record conversions shared by the flusher, applier,
/// bootstrap seed, and snapshot writer. The field maps mirror the server
/// sync engine so the file-sync format preserves the same semantics.
enum RecordConverters {
    // MARK: Outgoing

    static func record(from podcast: Podcast) -> Api_Record {
        var item = Api_SyncUserPodcast()
        item.uuid = podcast.uuid
        item.subscribed = .with { $0.value = podcast.subscribed > 0 }
        item.isDeleted = .with { $0.value = podcast.subscribed == 0 }
        item.autoStartFrom = .with { $0.value = podcast.startFrom }
        item.autoSkipLast = .with { $0.value = podcast.skipLast }
        item.sortPosition = .with { $0.value = podcast.sortOrder }
        if let folderUuid = podcast.folderUuid, !folderUuid.isEmpty {
            item.folderUuid = .with { $0.value = folderUuid }
        }
        if let addedDate = podcast.addedDate {
            item.dateAdded = Google_Protobuf_Timestamp(date: addedDate)
        }
        if let feedURL = podcast.podcastUrl, !feedURL.isEmpty {
            item.feedURL = feedURL
        }
        var record = Api_Record()
        record.podcast = item
        return record
    }

    static func record(from episode: Episode, changedFields: Set<String>) -> Api_Record {
        var item = Api_SyncUserEpisode()
        item.uuid = episode.uuid
        item.podcastUuid = episode.podcastUuid
        if changedFields.contains("playedUpTo"), episode.playedUpToModified > 0 {
            item.playedUpTo = .with { $0.value = Int64(episode.playedUpTo) }
            item.playedUpToModified = .with { $0.value = episode.playedUpToModified }
        }
        if changedFields.contains("playingStatus"), episode.playingStatusModified > 0 {
            item.playingStatus = .with { $0.value = episode.playingStatus }
            item.playingStatusModified = .with { $0.value = episode.playingStatusModified }
        }
        if changedFields.contains("archived"), episode.archivedModified > 0 {
            item.isDeleted = .with { $0.value = episode.archived }
            item.isDeletedModified = .with { $0.value = episode.archivedModified }
        }
        if changedFields.contains("starred"), episode.keepEpisodeModified > 0 {
            item.starred = .with { $0.value = episode.keepEpisode }
            item.starredModified = .with { $0.value = episode.keepEpisodeModified }
        }
        if changedFields.contains("duration"), episode.durationModified > 0, episode.duration > 0 {
            item.duration = .with { $0.value = Int64(episode.duration) }
            item.durationModified = .with { $0.value = episode.durationModified }
        }
        var record = Api_Record()
        record.episode = item
        return record
    }

    static func record(from playlist: EpisodeFilter) -> Api_Record {
        var item = Api_SyncUserPlaylist()
        item.uuid = playlist.uuid.lowercased()
        item.originalUuid = playlist.uuid
        item.isDeleted = .with { $0.value = playlist.wasDeleted }
        item.title = .with { $0.value = playlist.playlistName }
        item.allPodcasts = .with { $0.value = playlist.filterAllPodcasts }
        item.podcastUuids = .with { $0.value = playlist.podcastUuids }
        item.audioVideo = .with { $0.value = playlist.filterAudioVideoType }
        item.notDownloaded = .with { $0.value = playlist.filterNotDownloaded }
        item.downloaded = .with { $0.value = playlist.filterDownloaded }
        item.finished = .with { $0.value = playlist.filterFinished }
        item.partiallyPlayed = .with { $0.value = playlist.filterPartiallyPlayed }
        item.unplayed = .with { $0.value = playlist.filterUnplayed }
        item.starred = .with { $0.value = playlist.filterStarred }
        item.manual = .with { $0.value = playlist.manual }
        item.sortPosition = .with { $0.value = playlist.sortPosition }
        item.sortType = .with { $0.value = playlist.sortType }
        item.iconID = .with { $0.value = playlist.customIcon }
        item.filterHours = .with { $0.value = playlist.filterHours }
        item.filterDuration = .with { $0.value = playlist.filterDuration }
        item.longerThan = .with { $0.value = playlist.longerThan }
        item.shorterThan = .with { $0.value = playlist.shorterThan }
        item.showArchived = .with { $0.value = playlist.showArchivedEpisodes }
        var record = Api_Record()
        record.playlist = item
        return record
    }

    static func record(from folder: Folder) -> Api_Record {
        var item = Api_SyncUserFolder()
        item.folderUuid = folder.uuid
        item.isDeleted = folder.wasDeleted
        item.name = folder.name
        item.color = folder.color
        item.sortPosition = folder.sortOrder
        item.podcastsSortType = folder.sortType
        if let addedDate = folder.addedDate {
            item.dateAdded = Google_Protobuf_Timestamp(date: addedDate)
        }
        var record = Api_Record()
        record.folder = item
        return record
    }

    static func record(from bookmark: Bookmark) -> Api_Record {
        var item = Api_SyncUserBookmark()
        item.bookmarkUuid = bookmark.uuid
        item.episodeUuid = bookmark.episodeUuid
        item.podcastUuid = bookmark.podcastUuid ?? ""
        item.createdAt = Google_Protobuf_Timestamp(date: bookmark.created)
        item.time = .with { $0.value = Int32(bookmark.time) }
        item.title = .with { $0.value = bookmark.title }
        if let titleModified = bookmark.titleModified {
            item.titleModified = .with { $0.value = Int64(titleModified.timeIntervalSince1970 * 1000) }
        }
        item.isDeleted = .with { $0.value = bookmark.deleted }
        if let deletedModified = bookmark.deletedModified {
            item.isDeletedModified = .with { $0.value = Int64(deletedModified.timeIntervalSince1970 * 1000) }
        }
        var record = Api_Record()
        record.bookmark = item
        return record
    }

    static func uploadIdentity(from episode: UserEpisode) -> Filesync_UploadIdentity? {
        guard let relativePath = episode.folderRelativePath else { return nil }
        var identity = Filesync_UploadIdentity()
        identity.uuid = episode.uuid
        identity.relativePath = relativePath
        identity.sizeBytes = episode.sizeInBytes
        identity.sha256 = episode.contentHash ?? ""
        identity.group = episode.groupName ?? ""
        identity.title = episode.title ?? ""
        identity.durationSeconds = episode.duration
        identity.fileType = episode.fileType ?? ""
        return identity
    }

    // MARK: Incoming

    static func apply(_ item: Api_SyncUserPodcast, to podcast: Podcast) -> Podcast {
        var podcast = podcast
        if item.hasSubscribed {
            podcast.subscribed = item.subscribed.value ? 1 : 0
        }
        if item.hasAutoStartFrom {
            podcast.startFrom = item.autoStartFrom.value
        }
        if item.hasAutoSkipLast {
            podcast.skipLast = item.autoSkipLast.value
        }
        if item.hasSortPosition {
            podcast.sortOrder = item.sortPosition.value
        }
        if item.hasFolderUuid {
            let value = item.folderUuid.value
            podcast.folderUuid = value.isEmpty ? nil : value
        }
        if !item.feedURL.isEmpty, podcast.podcastUrl == nil {
            podcast.podcastUrl = item.feedURL
        }
        return podcast
    }

    static func apply(_ item: Api_SyncUserPlaylist, to playlist: EpisodeFilter) -> EpisodeFilter {
        var playlist = playlist
        playlist.syncStatus = SyncStatus.synced.rawValue
        if item.hasTitle { playlist.playlistName = item.title.value }
        if item.hasAllPodcasts { playlist.filterAllPodcasts = item.allPodcasts.value }
        if item.hasPodcastUuids { playlist.podcastUuids = item.podcastUuids.value }
        if item.hasAudioVideo { playlist.filterAudioVideoType = item.audioVideo.value }
        if item.hasNotDownloaded { playlist.filterNotDownloaded = item.notDownloaded.value }
        if item.hasDownloaded { playlist.filterDownloaded = item.downloaded.value }
        if item.hasFinished { playlist.filterFinished = item.finished.value }
        if item.hasPartiallyPlayed { playlist.filterPartiallyPlayed = item.partiallyPlayed.value }
        if item.hasUnplayed { playlist.filterUnplayed = item.unplayed.value }
        if item.hasStarred { playlist.filterStarred = item.starred.value }
        if item.hasManual { playlist.manual = item.manual.value }
        if item.hasSortPosition { playlist.sortPosition = item.sortPosition.value }
        if item.hasSortType { playlist.sortType = item.sortType.value }
        if item.hasIconID { playlist.customIcon = item.iconID.value }
        if item.hasFilterHours { playlist.filterHours = item.filterHours.value }
        if item.hasFilterDuration { playlist.filterDuration = item.filterDuration.value }
        if item.hasLongerThan { playlist.longerThan = item.longerThan.value }
        if item.hasShorterThan { playlist.shorterThan = item.shorterThan.value }
        if item.hasShowArchived { playlist.showArchivedEpisodes = item.showArchived.value }
        return playlist
    }

    static func apply(_ item: Api_SyncUserFolder, to folder: Folder) -> Folder {
        var folder = folder
        folder.name = item.name
        folder.color = item.color
        folder.sortOrder = item.sortPosition
        folder.sortType = item.podcastsSortType
        if item.hasDateAdded, folder.addedDate == nil {
            folder.addedDate = item.dateAdded.date
        }
        return folder
    }
}
