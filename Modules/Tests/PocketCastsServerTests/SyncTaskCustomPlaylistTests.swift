@testable import PocketCastsServer
@testable import PocketCastsDataModel
@testable import PocketCastsUtils
import XCTest
import GRDB
import SwiftProtobuf

/// Custom playlists are device-local: these tests pin every sync guard — they are
/// never offered for upload (`allUnsyncedPlaylists` / `markAllPlaylistsUnsynced`),
/// an incremental server record with a colliding uuid is ignored (`importPlaylist`),
/// and a full sync preserves them instead of delete-rewriting (`processServerPlaylists`).
final class SyncTaskCustomPlaylistTests: XCTestCase {
    private var dataManager: DataManager!
    private var syncTask: SyncTask!

    private let customEnvelope = #"{"version":1,"mode":"sql","sql":"episode.duration > 1800"}"#

    override func setUp() {
        super.setUp()
        dataManager = DataManager(dbQueue: GRDBQueue(dbPool: try! DatabasePool(path: NSTemporaryDirectory().appending("\(UUID().uuidString).sqlite"))))
        syncTask = SyncTask(dataManager: dataManager)
        DataManager.sharedManager = dataManager
    }

    override func tearDown() {
        FeatureFlagMock().reset()
        super.tearDown()
    }

    @discardableResult
    private func saveCustomPlaylist(uuid: String, name: String = "Custom Local", syncStatus: Int32 = SyncStatus.notSynced.rawValue) -> EpisodeFilter {
        var playlist = EpisodeFilter()
        playlist.uuid = uuid
        playlist.playlistName = name
        playlist.manual = false
        playlist.syncStatus = syncStatus
        playlist.customQuery = customEnvelope
        return dataManager.save(playlist: playlist)
    }

    @discardableResult
    private func saveSmartPlaylist(uuid: String, name: String = "Smart Local", syncStatus: Int32 = SyncStatus.notSynced.rawValue) -> EpisodeFilter {
        var playlist = EpisodeFilter()
        playlist.uuid = uuid
        playlist.playlistName = name
        playlist.manual = false
        playlist.syncStatus = syncStatus
        return dataManager.save(playlist: playlist)
    }

    // MARK: - Upload exclusion

    func testAllUnsyncedPlaylistsExcludesCustomPlaylists() {
        saveCustomPlaylist(uuid: "custom-1")
        saveSmartPlaylist(uuid: "smart-1")

        let unsynced = dataManager.allUnsyncedPlaylists()

        XCTAssertEqual(unsynced.map(\.uuid), ["smart-1"], "custom playlists must never be offered for upload")
    }

    func testChangedPlaylistsNeverPushesCustomPlaylists() {
        saveCustomPlaylist(uuid: "custom-1")
        saveSmartPlaylist(uuid: "smart-1")

        let records = syncTask.changedPlaylists()

        let pushedUuids = records?.compactMap { record -> String? in
            if case let .playlist(playlist) = record.record { return playlist.uuid }
            return nil
        } ?? []
        XCTAssertEqual(pushedUuids, ["smart-1"])
    }

    func testMarkAllPlaylistsUnsyncedLeavesCustomPlaylistsSynced() {
        saveCustomPlaylist(uuid: "custom-1", syncStatus: SyncStatus.synced.rawValue)
        saveSmartPlaylist(uuid: "smart-1", syncStatus: SyncStatus.synced.rawValue)

        dataManager.markAllPlaylistsUnsynced()

        XCTAssertEqual(dataManager.findPlaylist(uuid: "custom-1")?.syncStatus, SyncStatus.synced.rawValue)
        XCTAssertEqual(dataManager.findPlaylist(uuid: "smart-1")?.syncStatus, SyncStatus.notSynced.rawValue)
        XCTAssertTrue(dataManager.allUnsyncedPlaylists().allSatisfy { !$0.isCustom })
    }

    // MARK: - Incremental import skip

    func testImportPlaylistSkipsWhenLocalPlaylistIsCustom() {
        saveCustomPlaylist(uuid: "custom-1", name: "Custom Local")

        var proto = Api_SyncUserPlaylist()
        proto.uuid = "custom-1"
        proto.originalUuid = "custom-1"
        proto.title.value = "Server Rename"
        proto.starred.value = true

        var record = Api_Record()
        record.playlist = proto
        var response = Api_SyncUpdateResponse()
        response.records = [record]

        syncTask.processServerData(response: response)

        let local = dataManager.findPlaylist(uuid: "custom-1")
        XCTAssertEqual(local?.playlistName, "Custom Local", "server record must not touch the local custom playlist")
        XCTAssertEqual(local?.customQuery, customEnvelope)
        XCTAssertEqual(local?.filterStarred, false)
    }

    func testImportPlaylistIgnoresServerDeleteForCustomPlaylist() {
        saveCustomPlaylist(uuid: "custom-1")

        var proto = Api_SyncUserPlaylist()
        proto.uuid = "custom-1"
        proto.originalUuid = "custom-1"
        proto.isDeleted.value = true

        var record = Api_Record()
        record.playlist = proto
        var response = Api_SyncUpdateResponse()
        response.records = [record]

        syncTask.processServerData(response: response)

        XCTAssertNotNil(dataManager.findPlaylist(uuid: "custom-1"), "a server tombstone must not delete a local custom playlist")
    }

    func testImportPlaylistStillAppliesToNonCustomPlaylists() {
        saveSmartPlaylist(uuid: "smart-1", name: "Old Name")

        var proto = Api_SyncUserPlaylist()
        proto.uuid = "smart-1"
        proto.originalUuid = "smart-1"
        proto.title.value = "New Name"

        var record = Api_Record()
        record.playlist = proto
        var response = Api_SyncUpdateResponse()
        response.records = [record]

        syncTask.processServerData(response: response)

        XCTAssertEqual(dataManager.findPlaylist(uuid: "smart-1")?.playlistName, "New Name")
    }

    // MARK: - Full sync preservation

    func testProcessServerPlaylistsPreservesLocalCustomPlaylist() {
        saveCustomPlaylist(uuid: "custom-1", name: "Custom Local", syncStatus: SyncStatus.synced.rawValue)

        var serverPlaylist = EpisodeFilter()
        serverPlaylist.uuid = "custom-1"
        serverPlaylist.playlistName = "Server Version"

        syncTask.processServerPlaylists([(serverPlaylist, [])])

        let local = dataManager.findPlaylist(uuid: "custom-1")
        XCTAssertEqual(local?.playlistName, "Custom Local", "full sync must not delete-rewrite a custom playlist")
        XCTAssertEqual(local?.customQuery, customEnvelope, "the customQuery envelope must survive a full sync")
        XCTAssertEqual(local?.syncStatus, SyncStatus.synced.rawValue, "markAllPlaylistsUnsynced skips custom playlists")
    }

    func testProcessServerPlaylistsStillRewritesNonCustomPlaylists() {
        saveSmartPlaylist(uuid: "smart-1", name: "Old Local")

        var serverPlaylist = EpisodeFilter()
        serverPlaylist.uuid = "smart-1"
        serverPlaylist.playlistName = "Server Version"

        syncTask.processServerPlaylists([(serverPlaylist, [])])

        let local = dataManager.findPlaylist(uuid: "smart-1")
        XCTAssertEqual(local?.playlistName, "Server Version")
        XCTAssertEqual(local?.syncStatus, SyncStatus.synced.rawValue)
    }
}
