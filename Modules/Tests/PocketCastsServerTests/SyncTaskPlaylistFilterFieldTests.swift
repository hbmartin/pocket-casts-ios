@testable import PocketCastsServer
@testable import PocketCastsDataModel
@testable import PocketCastsUtils
import XCTest
import GRDB
import SwiftProtobuf

/// Round-trips the smart-playlist *filter rule* fields through sync in both directions. The existing
/// suites cover manual-playlist episode membership/ordering; these cover the filter-criteria mapping
/// (`createSyncUserPlaylist` on push, `processServerPlaylist` on pull), which was previously untested.
final class SyncTaskPlaylistFilterFieldTests: XCTestCase {
    private var dataManager: DataManager!
    private var originalSharedManager: DataManager!
    private var syncTask: SyncTask!

    override func setUp() {
        super.setUp()
        originalSharedManager = DataManager.sharedManager
        dataManager = DataManager(dbQueue: GRDBQueue(dbPool: try! DatabasePool(path: NSTemporaryDirectory().appending("\(UUID().uuidString).sqlite"))))
        syncTask = SyncTask(dataManager: dataManager)
        DataManager.sharedManager = dataManager
    }

    override func tearDown() {
        DataManager.sharedManager = originalSharedManager
        originalSharedManager = nil
        dataManager = nil
        FeatureFlagMock().reset()
        super.tearDown()
    }

    func testSmartPlaylistPushIncludesFilterFields() throws {
        var filter = EpisodeFilter()
        filter.uuid = "smart-push"
        filter.playlistName = "Smart Push"
        filter.manual = false
        filter.syncStatus = SyncStatus.notSynced.rawValue
        filter.podcastUuids = "pod-a,pod-b"
        filter.filterAudioVideoType = 2
        filter.filterDownloaded = true
        filter.filterNotDownloaded = false
        filter.filterFinished = true
        filter.filterPartiallyPlayed = true
        filter.filterUnplayed = true
        filter.filterStarred = true
        filter.filterHours = 24
        filter.sortPosition = 7
        filter.sortType = 5
        filter.customIcon = 3
        filter.filterDuration = true
        filter.longerThan = 300
        filter.shorterThan = 3_600
        dataManager.save(playlist: filter)

        let proto = try XCTUnwrap(pushedPlaylist(uuid: "smart-push"))

        XCTAssertEqual(proto.title.value, "Smart Push")
        XCTAssertFalse(proto.manual.value)
        XCTAssertFalse(proto.allPodcasts.value, "allPodcasts is false when podcastUuids is non-empty")
        XCTAssertEqual(proto.podcastUuids.value, "pod-a,pod-b")
        XCTAssertEqual(proto.audioVideo.value, 2)
        XCTAssertTrue(proto.downloaded.value)
        XCTAssertFalse(proto.notDownloaded.value)
        XCTAssertTrue(proto.finished.value)
        XCTAssertTrue(proto.partiallyPlayed.value)
        XCTAssertTrue(proto.unplayed.value)
        XCTAssertTrue(proto.starred.value)
        XCTAssertEqual(proto.filterHours.value, 24)
        XCTAssertEqual(proto.sortPosition.value, 7)
        XCTAssertEqual(proto.sortType.value, 5)
        XCTAssertEqual(proto.iconID.value, 3)
        XCTAssertTrue(proto.filterDuration.value)
        XCTAssertEqual(proto.longerThan.value, 300)
        XCTAssertEqual(proto.shorterThan.value, 3_600)
    }

    func testServerPlaylistPullAppliesFilterFields() throws {
        var proto = Api_SyncUserPlaylist()
        proto.uuid = "smart-pull"
        proto.originalUuid = "smart-pull"
        proto.title.value = "Smart Pull"
        proto.manual.value = false
        proto.allPodcasts.value = false
        proto.podcastUuids.value = "x,y"
        proto.audioVideo.value = 1
        proto.downloaded.value = true
        proto.finished.value = true
        proto.partiallyPlayed.value = true
        proto.unplayed.value = true
        proto.starred.value = true
        proto.filterHours.value = 12
        proto.sortType.value = 3
        proto.iconID.value = 4
        proto.filterDuration.value = true
        proto.longerThan.value = 100
        proto.shorterThan.value = 200

        var record = Api_Record()
        record.playlist = proto
        var response = Api_SyncUpdateResponse()
        response.records = [record]

        syncTask.processServerData(response: response)

        let filter = try XCTUnwrap(dataManager.findPlaylist(uuid: "smart-pull"), "server playlist should be created")
        XCTAssertEqual(filter.playlistName, "Smart Pull")
        XCTAssertFalse(filter.manual)
        XCTAssertFalse(filter.filterAllPodcasts)
        XCTAssertEqual(filter.podcastUuids, "x,y")
        XCTAssertEqual(filter.filterAudioVideoType, 1)
        XCTAssertTrue(filter.filterDownloaded)
        XCTAssertTrue(filter.filterFinished)
        XCTAssertTrue(filter.filterPartiallyPlayed)
        XCTAssertTrue(filter.filterUnplayed)
        XCTAssertTrue(filter.filterStarred)
        XCTAssertEqual(filter.filterHours, 12)
        XCTAssertEqual(filter.sortType, 3)
        XCTAssertEqual(filter.customIcon, 4)
        XCTAssertTrue(filter.filterDuration)
        XCTAssertEqual(filter.longerThan, 100)
        XCTAssertEqual(filter.shorterThan, 200)
        XCTAssertEqual(filter.syncStatus, SyncStatus.synced.rawValue, "pull marks the playlist synced")
    }

    // MARK: - Helper

    private func pushedPlaylist(uuid: String) -> Api_SyncUserPlaylist? {
        let records = syncTask.changedPlaylists()
        let playlists = records?.compactMap { $0.record }.compactMap { record -> Api_SyncUserPlaylist? in
            if case let .playlist(p) = record { return p }
            return nil
        }
        return playlists?.first(where: { $0.uuid == uuid })
    }
}
