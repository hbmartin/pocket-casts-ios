import XCTest
import GRDB
@testable import PocketCastsDataModel
@testable import PocketCastsUtils

/// Coverage for the previously-untested PlaylistDataManager episode-membership query and mutation
/// helpers. Runs against both the legacy SQL and GRDB code paths.
final class PlaylistDataManagerQueryTests: DataManagerTestCase {

    // MARK: - playlistContainsPodcast

    func testPlaylistContainsPodcast() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(uuid: "pod-A", dataManager: dataManager)
            let episode = self.createTestEpisode(podcast: podcast, dataManager: dataManager)
            let playlist = self.createTestPlaylist(uuid: "pl-A", manual: true, dataManager: dataManager)

            XCTAssertFalse(dataManager.playlistContainsPodcast(podcastUuid: "pod-A"),
                           "\(impl): empty playlist contains no podcast")

            XCTAssertTrue(dataManager.add(episodes: [episode], to: playlist), "\(impl): add should succeed")

            XCTAssertTrue(dataManager.playlistContainsPodcast(podcastUuid: "pod-A"),
                          "\(impl): podcast is now represented in a manual playlist")
            XCTAssertFalse(dataManager.playlistContainsPodcast(podcastUuid: "pod-unrelated"),
                           "\(impl): unrelated podcast is not present")
        }
    }

    // MARK: - manualPlaylistUUIDs

    func testManualPlaylistUUIDsReturnsEveryContainingPlaylist() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(uuid: "pod-M", dataManager: dataManager)
            let episode = self.createTestEpisode(uuid: "ep-M", podcast: podcast, dataManager: dataManager)
            let playlistA = self.createTestPlaylist(uuid: "pl-M1", manual: true, dataManager: dataManager)
            let playlistB = self.createTestPlaylist(uuid: "pl-M2", manual: true, dataManager: dataManager)

            XCTAssertTrue(dataManager.add(episodes: [episode], to: playlistA))
            XCTAssertTrue(dataManager.add(episodes: [episode], to: playlistB))

            XCTAssertEqual(Set(dataManager.manualPlaylistUUIDs(for: "ep-M")), ["pl-M1", "pl-M2"],
                           "\(impl): returns every manual playlist containing the episode")
            XCTAssertTrue(dataManager.manualPlaylistUUIDs(for: "ep-not-in-any").isEmpty,
                          "\(impl): episode in no playlist returns empty")
        }
    }

    // MARK: - rawDeleteEpisodes

    func testRawDeleteEpisodesRemovesMembership() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(uuid: "pod-R", dataManager: dataManager)
            let e1 = self.createTestEpisode(uuid: "r1", podcast: podcast, dataManager: dataManager)
            let e2 = self.createTestEpisode(uuid: "r2", podcast: podcast, dataManager: dataManager)
            let playlist = self.createTestPlaylist(uuid: "pl-R", manual: true, dataManager: dataManager)
            XCTAssertTrue(dataManager.add(episodes: [e1, e2], to: playlist))

            dataManager.rawDeleteEpisodes(["r1"], from: playlist)

            XCTAssertTrue(dataManager.manualPlaylistUUIDs(for: "r1").isEmpty, "\(impl): r1 removed")
            XCTAssertEqual(dataManager.manualPlaylistUUIDs(for: "r2"), ["pl-R"], "\(impl): r2 retained")
        }
    }

    // MARK: - updateEpisodePosition

    func testUpdateEpisodePositionReorders() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(uuid: "pod-P", dataManager: dataManager)
            let e1 = self.createTestEpisode(uuid: "p1", podcast: podcast, dataManager: dataManager)
            let e2 = self.createTestEpisode(uuid: "p2", podcast: podcast, dataManager: dataManager)
            let e3 = self.createTestEpisode(uuid: "p3", podcast: podcast, dataManager: dataManager)
            let playlist = self.createTestPlaylist(uuid: "pl-P", manual: true, dataManager: dataManager)
            XCTAssertTrue(dataManager.add(episodes: [e1, e2, e3], to: playlist))

            try assertPlaylistOrder(dataManager: dataManager, playlistUuid: "pl-P", expected: ["p1", "p2", "p3"], impl: impl)

            // Move the first episode to the last position.
            dataManager.updateEpisodePosition("p1", in: playlist, to: 2)

            try assertPlaylistOrder(dataManager: dataManager, playlistUuid: "pl-P", expected: ["p2", "p3", "p1"], impl: impl)
        }
    }

    // MARK: - Regression: save + add must not duplicate the playlist row

    func testSaveThenAddDoesNotDuplicatePlaylist() throws {
        try runWithBothImplementations { dataManager, impl in
            let podcast = self.createTestPodcast(uuid: "pod-D", dataManager: dataManager)
            let episode = self.createTestEpisode(uuid: "ep-D", podcast: podcast, dataManager: dataManager)

            var filter = EpisodeFilter()
            filter.uuid = "dup-test"
            filter.playlistName = "Dup"
            filter.manual = true
            dataManager.save(playlist: filter)
            // Value-type save does not back-mutate id, so `filter` is still the stale id == 0 instance
            // that callers historically re-used; add(...) must not insert a second row for it.
            XCTAssertEqual(filter.id, 0, "\(impl): value-type save does not back-mutate the argument")

            XCTAssertTrue(dataManager.add(episodes: [episode], to: filter), "\(impl): add succeeds")

            let matches = dataManager.allPlaylists(includeDeleted: true).filter { $0.uuid == "dup-test" }
            XCTAssertEqual(matches.count, 1, "\(impl): save + add must not create a duplicate playlist row")
        }
    }

    // MARK: - Helper

    private func assertPlaylistOrder(dataManager: DataManager, playlistUuid: String, expected: [String], impl: String) throws {
        let sql = """
        SELECT episodeUuid FROM \(DataManager.playlistEpisodeTableName)
        WHERE playlist_uuid = ?
        ORDER BY episodePosition ASC
        """
        var actual = [String]()
        dataManager.testDbQueue.read { db in
            do {
                let rs = try db.executeQuery(sql, values: [playlistUuid])
                defer { rs.close() }
                while rs.next() {
                    actual.append(DBUtils.nonNilStringFromColumn(resultSet: rs, columnName: "episodeUuid"))
                }
            } catch {
                XCTFail("\(impl): query failed \(error)")
            }
        }
        XCTAssertEqual(actual, expected, "\(impl): playlist order")
    }
}
