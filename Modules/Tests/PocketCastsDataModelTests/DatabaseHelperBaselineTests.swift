import GRDB
@testable import PocketCastsDataModel
import XCTest

final class DatabaseHelperBaselineTests: XCTestCase {
    func testBaselineSetupCreatesCurrentSchema() throws {
        let dataManager = DataManager.newTestDataManager()
        let dbPool = dataManager.testDbQueue.dbPool

        try dbPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1, 73)

            let tables = Set(try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
            ))

            XCTAssertTrue(
                Self.expectedTables.isSubset(of: tables),
                "Missing expected tables: \(Self.expectedTables.subtracting(tables))"
            )
            XCTAssertFalse(tables.contains("EpisodeMetadata"))

            let indexes = Set(try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'index'"
            ))

            XCTAssertTrue(
                Self.expectedIndexes.isSubset(of: indexes),
                "Missing expected indexes: \(Self.expectedIndexes.subtracting(indexes))"
            )
        }
    }

    func testOutdatedDatabaseIsDroppedAndRebuilt() throws {
        let databaseName = "\(UUID().uuidString).sqlite3"
        guard let dbPool = try DatabasePool.newTestDatabase(databaseName: databaseName) else {
            XCTFail("Expected test database")
            return
        }

        try dbPool.write { db in
            try db.execute(sql: "CREATE TABLE LegacyOnly (id INTEGER PRIMARY KEY);")
            try db.execute(sql: "PRAGMA user_version = 72;")
        }

        DatabaseHelper.setup(queue: GRDBQueue(dbPool: dbPool))

        try dbPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1, 73)

            let tables = Set(try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
            ))

            XCTAssertFalse(tables.contains("LegacyOnly"))
            XCTAssertTrue(
                Self.expectedTables.isSubset(of: tables),
                "Missing expected tables after rebuild: \(Self.expectedTables.subtracting(tables))"
            )
        }
    }

    private static let expectedTables: Set<String> = [
        "SJPodcast",
        "SJEpisode",
        "SJFilteredPlaylist",
        "SJPlaylistEpisode",
        "UpNextChanges",
        "SJUserEpisode",
        "Folder",
        "AutoAddCandidates",
        "PlaylistEpisodeHistory",
        "PodcastFoldersHistory",
        "Bookmark",
        "NetworkDataUsage"
    ]

    private static let expectedIndexes: Set<String> = [
        "podcast_uuid",
        "episode_uuid",
        "episode_podcast_uuid",
        "episode_download_task_id",
        "episode_non_null_download_task_id",
        "episode_added_date",
        "playlist_episode_playlist_uuid",
        "candidate_episode",
        "bookmark_uuid",
        "network_data_timestamp"
    ]
}
