import XCTest
import GRDB
@testable import PocketCastsDataModel
@testable import PocketCastsUtils

/// Tests for UpNextHistoryManager using the public DataManager API.
/// These tests run with both SQL and GRDB implementations.
final class UpNextHistoryManagerTests: DataManagerTestCase {

    // MARK: - snapshotUpNext Tests

    func testSnapshotCreatesEntryWithEpisodeCount() throws {
        try runWithBothImplementations { dataManager, impl in
            self.addToUpNextBottom(episodeUuid: "episode-1", dataManager: dataManager)
            self.addToUpNextBottom(episodeUuid: "episode-2", dataManager: dataManager)
            self.addToUpNextBottom(episodeUuid: "episode-3", dataManager: dataManager)

            dataManager.snapshotUpNext()

            let entries = dataManager.upNextHistoryEntries()

            XCTAssertEqual(entries.count, 1, "\(impl): One snapshot should produce one entry")
            XCTAssertEqual(entries.first?.episodeCount, 3, "\(impl): Entry should count all Up Next episodes")
        }
    }

    func testSnapshotWithEmptyUpNextCreatesNoEntries() throws {
        try runWithBothImplementations { dataManager, impl in
            dataManager.snapshotUpNext()

            let entries = dataManager.upNextHistoryEntries()

            XCTAssertTrue(entries.isEmpty, "\(impl): Snapshotting an empty Up Next should not create entries")
        }
    }

    func testSnapshotPrunesEntriesOlderThanRetentionPeriod() throws {
        try runWithBothImplementations { dataManager, impl in
            let oldDate = Date().addingTimeInterval(-15.days)
            self.insertHistoryRow(episodeUuid: "episode-old", position: 0, date: oldDate, dataManager: dataManager)
            let recentDate = Date().addingTimeInterval(-1.days)
            self.insertHistoryRow(episodeUuid: "episode-recent", position: 0, date: recentDate, dataManager: dataManager)

            self.addToUpNextBottom(episodeUuid: "episode-1", dataManager: dataManager)
            dataManager.snapshotUpNext()

            let entries = dataManager.upNextHistoryEntries()

            XCTAssertEqual(entries.count, 2, "\(impl): The entry older than 14 days should be pruned")
            XCTAssertFalse(
                entries.contains { abs($0.date.timeIntervalSince(oldDate)) < 1 },
                "\(impl): The pruned entry should not be listed"
            )
        }
    }

    // MARK: - upNextHistoryEntries Tests

    func testEntriesReturnsEmptyWhenNoHistory() throws {
        try runWithBothImplementations { dataManager, impl in
            let entries = dataManager.upNextHistoryEntries()

            XCTAssertTrue(entries.isEmpty, "\(impl): Should return no entries for an empty table")
        }
    }

    func testEntriesAreOrderedNewestFirst() throws {
        try runWithBothImplementations { dataManager, impl in
            let older = Date().addingTimeInterval(-2.days)
            let newer = Date().addingTimeInterval(-1.days)
            self.insertHistoryRow(episodeUuid: "episode-1", position: 0, date: older, dataManager: dataManager)
            self.insertHistoryRow(episodeUuid: "episode-2", position: 0, date: newer, dataManager: dataManager)

            let entries = dataManager.upNextHistoryEntries()

            XCTAssertEqual(entries.count, 2, "\(impl): Should list one entry per snapshot date")
            XCTAssertEqual(entries.map(\.date), entries.map(\.date).sorted(by: >), "\(impl): Entries should be ordered newest first")
        }
    }

    func testEntriesGroupsRowsBySnapshotDate() throws {
        try runWithBothImplementations { dataManager, impl in
            let firstSnapshot = Date().addingTimeInterval(-2.days)
            let secondSnapshot = Date().addingTimeInterval(-1.days)
            self.insertHistoryRow(episodeUuid: "episode-1", position: 0, date: firstSnapshot, dataManager: dataManager)
            self.insertHistoryRow(episodeUuid: "episode-2", position: 1, date: firstSnapshot, dataManager: dataManager)
            self.insertHistoryRow(episodeUuid: "episode-3", position: 0, date: secondSnapshot, dataManager: dataManager)

            let entries = dataManager.upNextHistoryEntries()

            XCTAssertEqual(entries.count, 2, "\(impl): Rows sharing a date should group into one entry")
            XCTAssertEqual(entries.first?.episodeCount, 1, "\(impl): The newest entry has one episode")
            XCTAssertEqual(entries.last?.episodeCount, 2, "\(impl): The oldest entry has two episodes")
        }
    }

    // MARK: - upNextHistoryEpisodes Tests

    func testEpisodesReturnsUuidsOrderedByPosition() throws {
        try runWithBothImplementations { dataManager, impl in
            let snapshotDate = Date().addingTimeInterval(-1.days)
            self.insertHistoryRow(episodeUuid: "episode-c", position: 2, date: snapshotDate, dataManager: dataManager)
            self.insertHistoryRow(episodeUuid: "episode-a", position: 0, date: snapshotDate, dataManager: dataManager)
            self.insertHistoryRow(episodeUuid: "episode-b", position: 1, date: snapshotDate, dataManager: dataManager)

            guard let entry = dataManager.upNextHistoryEntries().first else {
                XCTFail("\(impl): Seeded rows should produce an entry")
                return
            }

            let episodes = dataManager.upNextHistoryEpisodes(entry: entry.date)

            XCTAssertEqual(episodes, ["episode-a", "episode-b", "episode-c"], "\(impl): Episodes should be ordered by episodePosition")
        }
    }

    func testEpisodesReturnsEmptyForUnknownDate() throws {
        try runWithBothImplementations { dataManager, impl in
            self.addToUpNextBottom(episodeUuid: "episode-1", dataManager: dataManager)
            dataManager.snapshotUpNext()

            let episodes = dataManager.upNextHistoryEpisodes(entry: Date(timeIntervalSince1970: 1000))

            XCTAssertTrue(episodes.isEmpty, "\(impl): Should return no episodes for a date with no snapshot")
        }
    }

    func testSnapshotRoundTripsThroughEpisodes() throws {
        try runWithBothImplementations { dataManager, impl in
            self.addToUpNextBottom(episodeUuid: "episode-1", dataManager: dataManager)
            self.addToUpNextBottom(episodeUuid: "episode-2", dataManager: dataManager)

            dataManager.snapshotUpNext()

            guard let entry = dataManager.upNextHistoryEntries().first else {
                XCTFail("\(impl): Snapshot should produce an entry")
                return
            }

            let episodes = dataManager.upNextHistoryEpisodes(entry: entry.date)

            XCTAssertEqual(episodes, ["episode-1", "episode-2"], "\(impl): Should restore the snapshotted Up Next order")
        }
    }

    func testEpisodesOnlyReturnsRowsForRequestedSnapshot() throws {
        try runWithBothImplementations { dataManager, impl in
            let firstSnapshot = Date().addingTimeInterval(-2.days)
            let secondSnapshot = Date().addingTimeInterval(-1.days)
            self.insertHistoryRow(episodeUuid: "episode-1", position: 0, date: firstSnapshot, dataManager: dataManager)
            self.insertHistoryRow(episodeUuid: "episode-2", position: 0, date: secondSnapshot, dataManager: dataManager)

            let entries = dataManager.upNextHistoryEntries()
            XCTAssertEqual(entries.count, 2, "\(impl): Should list both snapshots")

            guard let newest = entries.first else { return }
            let episodes = dataManager.upNextHistoryEpisodes(entry: newest.date)

            XCTAssertEqual(episodes, ["episode-2"], "\(impl): Should only return the requested snapshot's episodes")
        }
    }

    // MARK: - Column Consistency

    /// The legacy path copies Up Next rows with a positional
    /// `INSERT INTO PlaylistEpisodeHistory SELECT <columns>, ? as 'date'`, so the history table's
    /// column order must keep matching that SELECT list.
    func testDatabaseTableColumnsMatchLegacyInsertOrder() throws {
        let dataManager = DataManager.newTestDataManager()

        guard let grdbQueue = dataManager.dbQueue as? GRDBQueue else {
            XCTFail("Expected GRDBQueue for database introspection")
            return
        }

        let tableColumns = try grdbQueue.dbPool.read { db -> [String] in
            try db.columns(in: PlaylistEpisodeHistoryRow.databaseTableName).map { $0.name }
        }

        XCTAssertEqual(
            tableColumns,
            ["id", "episodePosition", "episodeUuid", "playlist_id", "upcoming", "timeModified", "wasDeleted", "title", "podcastUuid", "date"],
            "Table columns must stay in the order the legacy positional INSERT…SELECT expects"
        )
    }

    // MARK: - Helpers

    /// Inserts a history row with a controlled date. Uses the legacy shim directly (independent of
    /// the feature flag) — it binds `Date` as a `timeIntervalSince1970` REAL, the storage format
    /// shared by both implementations.
    private func insertHistoryRow(episodeUuid: String, position: Int32, date: Date, dataManager: DataManager) {
        dataManager.dbQueue.write { db in
            do {
                try db.executeUpdate(
                    "INSERT INTO PlaylistEpisodeHistory (episodePosition, episodeUuid, playlist_id, upcoming, timeModified, wasDeleted, title, podcastUuid, date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    values: [position, episodeUuid, UpNextDataManager.upNextPlaylistId, 0, 0, false, "Test Episode", "podcast-1", date]
                )
            } catch {
                XCTFail("Failed to insert history row: \(error)")
            }
        }
    }
}
