import GRDB
@testable import PocketCastsDataModel
import XCTest

final class DatabaseHelperBaselineTests: XCTestCase {
    func testBaselineSetupCreatesCurrentSchema() throws {
        let dataManager = DataManager.newTestDataManager()
        let dbPool = dataManager.testDbQueue.dbPool

        try dbPool.read { db in
            // Fresh installs create the baked baseline then run every registered migration,
            // so the resulting version tracks the migration registry, not the baseline.
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1,
                Int(DatabaseHelper.currentSchemaVersion(for: DatabaseHelper.migrations))
            )

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

    func testPrebaselineDatabaseFailsWithoutDroppingOrRebuilding() throws {
        let databaseName = "\(UUID().uuidString).sqlite3"
        guard let dbPool = try DatabasePool.newTestDatabase(databaseName: databaseName) else {
            XCTFail("Expected test database")
            return
        }

        try dbPool.write { db in
            try db.execute(sql: "CREATE TABLE LegacyOnly (id INTEGER PRIMARY KEY);")
            try db.execute(sql: "INSERT INTO LegacyOnly (id) VALUES (1);")
            try db.execute(sql: "PRAGMA user_version = 72;")
        }

        let setupSucceeded = DatabaseHelper.setup(queue: GRDBQueue(dbPool: dbPool))

        XCTAssertFalse(setupSucceeded)

        try dbPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1, 72)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM LegacyOnly") ?? -1, 1)

            let tables = Set(try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
            ))

            XCTAssertTrue(tables.contains("LegacyOnly"))
            XCTAssertTrue(Self.expectedTables.isDisjoint(with: tables))
        }
    }

    func testBaselineSetupFailureRollsBackPartialSchema() throws {
        let databaseName = "\(UUID().uuidString).sqlite3"
        guard let dbPool = try DatabasePool.newTestDatabase(databaseName: databaseName) else {
            XCTFail("Expected test database")
            return
        }

        try dbPool.write { db in
            try db.execute(sql: "CREATE TABLE SJEpisode (id INTEGER PRIMARY KEY);")
        }

        let setupSucceeded = DatabaseHelper.setup(queue: GRDBQueue(dbPool: dbPool))

        XCTAssertFalse(setupSucceeded)

        try dbPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1, 0)

            let tables = Set(try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
            ))

            XCTAssertTrue(tables.contains("SJEpisode"))
            let unexpectedTables = Self.expectedTables.subtracting(["SJEpisode"]).intersection(tables)
            XCTAssertTrue(
                unexpectedTables.isEmpty,
                "Unexpected partial schema tables: \(unexpectedTables)"
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
        "NetworkDataUsage",
        "FileSyncJournal",
        "FileSyncCursor"
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
        "network_data_timestamp",
        "file_sync_journal_unflushed",
        "user_episode_folder_relative_path",
        "user_episode_content_hash"
    ]
}
