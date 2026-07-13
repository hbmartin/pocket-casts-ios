import XCTest
import PocketCastsDataModel
@testable import PocketCastsFileSync

final class RecordConvertersTests: XCTestCase {
    func testPodcastRoundTrip() {
        var podcast = Podcast()
        podcast.uuid = "pod-1"
        podcast.subscribed = 1
        podcast.sortOrder = 7
        podcast.startFrom = 30
        podcast.skipLast = 15
        podcast.folderUuid = "folder-9"
        podcast.podcastUrl = "https://example.com/feed.rss"
        podcast.addedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let record = RecordConverters.record(from: podcast)
        guard case .podcast(let item)? = record.record else {
            XCTFail("expected a podcast record")
            return
        }
        XCTAssertTrue(item.subscribed.value)
        XCTAssertEqual(item.sortPosition.value, 7)
        XCTAssertEqual(item.autoStartFrom.value, 30)
        XCTAssertEqual(item.autoSkipLast.value, 15)
        XCTAssertEqual(item.folderUuid.value, "folder-9")
        XCTAssertEqual(item.feedURL, "https://example.com/feed.rss")

        var blank = Podcast()
        blank.uuid = "pod-1"
        let applied = RecordConverters.apply(item, to: blank)
        XCTAssertEqual(applied.subscribed, 1)
        XCTAssertEqual(applied.sortOrder, 7)
        XCTAssertEqual(applied.startFrom, 30)
        XCTAssertEqual(applied.skipLast, 15)
        XCTAssertEqual(applied.folderUuid, "folder-9")
        XCTAssertEqual(applied.podcastUrl, "https://example.com/feed.rss")
    }

    func testEpisodeCarriesOnlyChangedFields() {
        var episode = Episode()
        episode.uuid = "ep-1"
        episode.podcastUuid = "pod-1"
        episode.playedUpTo = 120
        episode.playedUpToModified = 5000
        episode.keepEpisode = true
        episode.keepEpisodeModified = 6000
        episode.archived = true
        episode.archivedModified = 7000

        let record = RecordConverters.record(from: episode, changedFields: ["playedUpTo"])
        guard case .episode(let item)? = record.record else {
            XCTFail("expected an episode record")
            return
        }
        XCTAssertTrue(item.hasPlayedUpTo)
        XCTAssertEqual(item.playedUpTo.value, 120)
        XCTAssertEqual(item.playedUpToModified.value, 5000)
        XCTAssertFalse(item.hasStarred)
        XCTAssertFalse(item.hasIsDeleted)
    }

    func testBookmarkRecordCarriesHighlightEnrichmentThroughWireRoundTrip() throws {
        let bookmark = Bookmark(
            uuid: "bm-1",
            title: "A moment",
            time: 30,
            created: Date(timeIntervalSince1970: 1_700_000_000),
            episodeUuid: "ep-1",
            podcastUuid: "pod-1",
            excerpt: "Something worth quoting",
            endTime: 42.5,
            titleModified: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let record = RecordConverters.record(from: bookmark)
        guard case .bookmark(let item)? = record.record else {
            XCTFail("expected a bookmark record")
            return
        }
        XCTAssertTrue(item.hasExcerpt)
        XCTAssertEqual(item.excerpt.value, "Something worth quoting")
        XCTAssertTrue(item.hasEndTime)
        XCTAssertEqual(item.endTime.value, 42.5)

        // Wire round-trip: the fork-extension fields (1000/1001) must survive
        // serialization exactly.
        let decoded = try Api_Record(serializedBytes: record.serializedData())
        guard case .bookmark(let decodedItem)? = decoded.record else {
            XCTFail("expected a bookmark record after decode")
            return
        }
        XCTAssertEqual(decodedItem, item)
    }

    func testBookmarkRecordOmitsEnrichmentWhenAbsent() {
        let bookmark = Bookmark(
            uuid: "bm-2",
            title: "Plain",
            time: 10,
            created: Date(timeIntervalSince1970: 1_700_000_000),
            episodeUuid: "ep-1",
            podcastUuid: nil
        )

        let record = RecordConverters.record(from: bookmark)
        guard case .bookmark(let item)? = record.record else {
            XCTFail("expected a bookmark record")
            return
        }
        XCTAssertFalse(item.hasExcerpt)
        XCTAssertFalse(item.hasEndTime)
    }

    func testFolderAndPlaylistRoundTrip() {
        var folder = Folder()
        folder.uuid = "folder-1"
        folder.name = "News"
        folder.color = 3
        folder.sortOrder = 2
        folder.sortType = 1
        let folderRecord = RecordConverters.record(from: folder)
        guard case .folder(let folderItem)? = folderRecord.record else {
            XCTFail("expected a folder record")
            return
        }
        var blankFolder = Folder()
        blankFolder.uuid = "folder-1"
        let appliedFolder = RecordConverters.apply(folderItem, to: blankFolder)
        XCTAssertEqual(appliedFolder.name, "News")
        XCTAssertEqual(appliedFolder.color, 3)
        XCTAssertEqual(appliedFolder.sortOrder, 2)
        XCTAssertEqual(appliedFolder.sortType, 1)

        var playlist = EpisodeFilter()
        playlist.uuid = "PL-1"
        playlist.playlistName = "Long ones"
        playlist.filterDuration = true
        playlist.longerThan = 40
        playlist.filterUnplayed = true
        let playlistRecord = RecordConverters.record(from: playlist)
        guard case .playlist(let playlistItem)? = playlistRecord.record else {
            XCTFail("expected a playlist record")
            return
        }
        XCTAssertEqual(playlistItem.originalUuid, "PL-1")
        var blankPlaylist = EpisodeFilter()
        blankPlaylist.uuid = "PL-1"
        let appliedPlaylist = RecordConverters.apply(playlistItem, to: blankPlaylist)
        XCTAssertEqual(appliedPlaylist.playlistName, "Long ones")
        XCTAssertTrue(appliedPlaylist.filterDuration)
        XCTAssertEqual(appliedPlaylist.longerThan, 40)
        XCTAssertTrue(appliedPlaylist.filterUnplayed)
    }
}
