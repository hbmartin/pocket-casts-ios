import GRDB
@testable import PocketCastsDataModel
import XCTest

final class DatabaseHelperMigrationTests: XCTestCase {
    private enum TestMigrationError: Error {
        case intentionalFailure
    }

    private static let testMigrations = [
        SchemaMigration(toVersion: 74) { db in
            try db.executeUpdate("CREATE TABLE MigrationTest74 (id INTEGER PRIMARY KEY, name TEXT);", values: nil)
        },
        SchemaMigration(toVersion: 75) { db in
            try db.executeUpdate("CREATE INDEX migration_test_74_name ON MigrationTest74 (name);", values: nil)
        }
    ]

    func testFreshInstallEndsAtLatestVersionWithMigratedSchema() throws {
        let dbPool = try XCTUnwrap(DatabasePool.newTestDatabase(databaseName: "\(UUID().uuidString).sqlite3"))

        let setupSucceeded = DatabaseHelper.setup(queue: GRDBQueue(dbPool: dbPool), migrations: Self.testMigrations)

        XCTAssertTrue(setupSucceeded)
        try dbPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1, 75)
            XCTAssertEqual(try Self.schemaObjects(in: db).filter { $0.contains("MigrationTest74") }.count, 2)
        }
    }

    func testFreshInstallMatchesUpgradedDatabase() throws {
        let freshPool = try XCTUnwrap(DatabasePool.newTestDatabase(databaseName: "\(UUID().uuidString).sqlite3"))

        // Fresh install straight to the latest version.
        XCTAssertTrue(DatabaseHelper.setup(queue: GRDBQueue(dbPool: freshPool), migrations: Self.testMigrations))
        let freshSchema = try freshPool.read(Self.schemaObjects)

        // Baseline install first, then upgrade — must converge on the identical schema.
        let upgradedPool = try XCTUnwrap(DatabasePool.newTestDatabase(databaseName: "\(UUID().uuidString).sqlite3"))
        XCTAssertTrue(DatabaseHelper.setup(queue: GRDBQueue(dbPool: upgradedPool), migrations: []))
        try upgradedPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1, 73)
        }
        XCTAssertTrue(DatabaseHelper.setup(queue: GRDBQueue(dbPool: upgradedPool), migrations: Self.testMigrations))

        let upgradedSchema = try upgradedPool.read(Self.schemaObjects)
        XCTAssertEqual(freshSchema, upgradedSchema)
        try upgradedPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1, 75)
        }
    }

    func testSetupIsIdempotentAtLatestVersion() throws {
        let dbPool = try XCTUnwrap(DatabasePool.newTestDatabase(databaseName: "\(UUID().uuidString).sqlite3"))

        XCTAssertTrue(DatabaseHelper.setup(queue: GRDBQueue(dbPool: dbPool), migrations: Self.testMigrations))
        XCTAssertTrue(DatabaseHelper.setup(queue: GRDBQueue(dbPool: dbPool), migrations: Self.testMigrations))

        try dbPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1, 75)
        }
    }

    func testFailingMigrationRollsBackAndKeepsVersion() throws {
        let dbPool = try XCTUnwrap(DatabasePool.newTestDatabase(databaseName: "\(UUID().uuidString).sqlite3"))
        XCTAssertTrue(DatabaseHelper.setup(queue: GRDBQueue(dbPool: dbPool), migrations: []))

        let failingMigrations = [
            SchemaMigration(toVersion: 74) { db in
                try db.executeUpdate("CREATE TABLE MigrationTest74 (id INTEGER PRIMARY KEY);", values: nil)
                throw TestMigrationError.intentionalFailure
            }
        ]

        let setupSucceeded = DatabaseHelper.setup(queue: GRDBQueue(dbPool: dbPool), migrations: failingMigrations)

        XCTAssertFalse(setupSucceeded)
        try dbPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1, 73)
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            XCTAssertFalse(tables.contains("MigrationTest74"))
        }
    }

    func testPrebaselineDatabaseStillFailsWithMigrationsRegistered() throws {
        let dbPool = try XCTUnwrap(DatabasePool.newTestDatabase(databaseName: "\(UUID().uuidString).sqlite3"))
        try dbPool.write { db in
            try db.execute(sql: "PRAGMA user_version = 72;")
        }

        let setupSucceeded = DatabaseHelper.setup(queue: GRDBQueue(dbPool: dbPool), migrations: Self.testMigrations)

        XCTAssertFalse(setupSucceeded)
        try dbPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1, 72)
        }
    }

    func testPartialUpgradeOnlyRunsRemainingMigrations() throws {
        let dbPool = try XCTUnwrap(DatabasePool.newTestDatabase(databaseName: "\(UUID().uuidString).sqlite3"))

        XCTAssertTrue(DatabaseHelper.setup(queue: GRDBQueue(dbPool: dbPool), migrations: [Self.testMigrations[0]]))
        try dbPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1, 74)
        }

        XCTAssertTrue(DatabaseHelper.setup(queue: GRDBQueue(dbPool: dbPool), migrations: Self.testMigrations))
        try dbPool.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1, 75)
            XCTAssertEqual(try Self.schemaObjects(in: db).filter { $0.contains("MigrationTest74") }.count, 2)
        }
    }

    /// Upgrade path for migration 80 (smart highlights): a database migrated up to
    /// version 79, with a pre-existing bookmark row, gains the enrichment columns
    /// without disturbing existing data.
    func testMigration80AddsBookmarkEnrichmentColumns() throws {
        let dbPool = try XCTUnwrap(DatabasePool.newTestDatabase(databaseName: "\(UUID().uuidString).sqlite3"))

        let priorMigrations = DatabaseHelper.migrations.filter { $0.toVersion <= 79 }
        XCTAssertTrue(DatabaseHelper.setup(queue: GRDBQueue(dbPool: dbPool), migrations: priorMigrations))

        try dbPool.write { db in
            try db.execute(sql: """
            INSERT INTO Bookmark (uuid, title, episode_uuid, time, date_added)
            VALUES ('bm-1', 'Pre-upgrade row', 'ep-1', 12.0, 0)
            """)
        }

        XCTAssertTrue(DatabaseHelper.setup(queue: GRDBQueue(dbPool: dbPool), migrations: DatabaseHelper.migrations))

        try dbPool.read { db in
            XCTAssertGreaterThanOrEqual(try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1, 80)

            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(Bookmark)").map { $0["name"] as String }
            XCTAssertTrue(columns.contains("excerpt"))
            XCTAssertTrue(columns.contains("endTime"))

            let row = try Row.fetchOne(db, sql: "SELECT title, excerpt, endTime FROM Bookmark WHERE uuid = 'bm-1'")
            XCTAssertEqual(row?["title"] as String?, "Pre-upgrade row")
            XCTAssertNil(row?["excerpt"] as String?)
            XCTAssertNil(row?["endTime"] as Double?)
        }
    }

    /// Upgrade path for migration 82 (unified transcript index): a database at
    /// version 81 with rows in both former corpora — generated segments
    /// (TranscriptionSegmentFTS) and provided cues (TranscriptCueIndex +
    /// TranscriptIndexMeta) — ends with everything in TranscriptSegmentIndex,
    /// meta preserved, the old tables gone, and both corpora searchable.
    func testMigration82MergesBothTranscriptCorpora() throws {
        let dbPool = try XCTUnwrap(DatabasePool.newTestDatabase(databaseName: "\(UUID().uuidString).sqlite3"))
        let queue = GRDBQueue(dbPool: dbPool)

        let priorMigrations = DatabaseHelper.migrations.filter { $0.toVersion <= 81 }
        XCTAssertTrue(DatabaseHelper.setup(queue: queue, migrations: priorMigrations))

        try dbPool.write { db in
            try db.execute(sql: """
            INSERT INTO EpisodeTranscription (episodeUuid, podcastUuid, status, updatedAt)
            VALUES ('ep-gen', 'pod-1', 2, 1234.0)
            """)
            try db.execute(sql: """
            INSERT INTO TranscriptionSegmentFTS (text, episodeUuid, podcastUuid, segmentIndex, startTime, speaker)
            VALUES ('a generated segment about zebras', 'ep-gen', 'pod-1', 0, 10.0, 'Speaker 1')
            """)
            try db.execute(sql: """
            INSERT INTO TranscriptionSegmentFTS (text, episodeUuid, podcastUuid, segmentIndex, startTime, speaker)
            VALUES ('an orphaned segment with no record row', 'ep-orphan', NULL, 0, 0.0, NULL)
            """)
            try db.execute(sql: """
            INSERT INTO TranscriptCueIndex (text, episodeUuid, podcastUuid, cueIndex, startTime, endTime)
            VALUES ('a provided cue about aardvarks', 'ep-prov', 'pod-2', 3, 20.0, 25.0)
            """)
            try db.execute(sql: """
            INSERT INTO TranscriptIndexMeta (episodeUuid, podcastUuid, indexedDate, cueCount, textBytes)
            VALUES ('ep-prov', 'pod-2', 555.0, 1, 30)
            """)
        }

        XCTAssertTrue(DatabaseHelper.setup(queue: queue, migrations: DatabaseHelper.migrations))

        try dbPool.read { db in
            XCTAssertGreaterThanOrEqual(try Int.fetchOne(db, sql: "PRAGMA user_version") ?? -1, 82)

            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            XCTAssertFalse(tables.contains("TranscriptionSegmentFTS"))
            XCTAssertFalse(tables.contains("TranscriptCueIndex"))
            XCTAssertFalse(tables.contains("TranscriptIndexMeta"))
            XCTAssertTrue(tables.contains("EpisodeTranscription"), "The pipeline-state table must survive")

            let generated = try Row.fetchOne(db, sql: "SELECT * FROM TranscriptSegmentIndex WHERE episodeUuid = 'ep-gen'")
            XCTAssertEqual(generated?["source"] as String?, "generated")
            XCTAssertEqual(generated?["speaker"] as String?, "Speaker 1")
            XCTAssertNil(generated?["endTime"] as Double?)

            let provided = try Row.fetchOne(db, sql: "SELECT * FROM TranscriptSegmentIndex WHERE episodeUuid = 'ep-prov'")
            XCTAssertEqual(provided?["source"] as String?, "provided")
            XCTAssertEqual(provided?["segmentIndex"] as Int?, 3, "cueIndex must map onto segmentIndex")
            XCTAssertEqual(provided?["endTime"] as Double?, 25.0)

            // Meta: generated rows take indexedDate from the record's updatedAt
            // (orphans get the migration time); provided rows copy 1:1.
            let genMeta = try Row.fetchOne(db, sql: "SELECT * FROM TranscriptSearchIndexMeta WHERE episodeUuid = 'ep-gen' AND source = 'generated'")
            XCTAssertEqual(genMeta?["indexedDate"] as Double?, 1234.0)
            XCTAssertEqual(genMeta?["segmentCount"] as Int?, 1)

            let orphanMeta = try Row.fetchOne(db, sql: "SELECT * FROM TranscriptSearchIndexMeta WHERE episodeUuid = 'ep-orphan' AND source = 'generated'")
            XCTAssertGreaterThan(orphanMeta?["indexedDate"] as Double? ?? 0, 0)

            let provMeta = try Row.fetchOne(db, sql: "SELECT * FROM TranscriptSearchIndexMeta WHERE episodeUuid = 'ep-prov' AND source = 'provided'")
            XCTAssertEqual(provMeta?["indexedDate"] as Double?, 555.0)
            XCTAssertEqual(provMeta?["segmentCount"] as Int?, 1)
            XCTAssertEqual(provMeta?["textBytes"] as Int64?, 30)
        }

        // Both backfilled corpora are searchable through the unified manager.
        let search = TranscriptSearchDataManager(dbQueue: queue)
        XCTAssertTrue(search.isAvailable)
        XCTAssertEqual(search.search(term: "zebras").map(\.episodeUuid), ["ep-gen"])
        XCTAssertEqual(search.search(term: "aardvarks").map(\.episodeUuid), ["ep-prov"])
        XCTAssertTrue(search.isIndexed(episodeUuid: "ep-prov", source: .provided))
        XCTAssertTrue(search.isIndexed(episodeUuid: "ep-gen", source: .generated))
    }

    /// Migration 82 on a database where migration 81 self-disabled (no
    /// TranscriptCueIndex/TranscriptIndexMeta): the generated corpus still
    /// backfills and the migration succeeds.
    func testMigration82SucceedsWhenMigration81TablesAreAbsent() throws {
        let dbPool = try XCTUnwrap(DatabasePool.newTestDatabase(databaseName: "\(UUID().uuidString).sqlite3"))
        let queue = GRDBQueue(dbPool: dbPool)

        let priorMigrations = DatabaseHelper.migrations.filter { $0.toVersion <= 81 }
        XCTAssertTrue(DatabaseHelper.setup(queue: queue, migrations: priorMigrations))

        try dbPool.write { db in
            try db.execute(sql: "DROP TABLE TranscriptCueIndex")
            try db.execute(sql: "DROP TABLE TranscriptIndexMeta")
            try db.execute(sql: """
            INSERT INTO TranscriptionSegmentFTS (text, episodeUuid, podcastUuid, segmentIndex, startTime, speaker)
            VALUES ('a generated segment about zebras', 'ep-gen', 'pod-1', 0, 10.0, NULL)
            """)
        }

        XCTAssertTrue(DatabaseHelper.setup(queue: queue, migrations: DatabaseHelper.migrations))

        let search = TranscriptSearchDataManager(dbQueue: queue)
        XCTAssertTrue(search.isAvailable)
        XCTAssertEqual(search.search(term: "zebras").map(\.episodeUuid), ["ep-gen"])
        XCTAssertEqual(search.indexedEpisodeCount(source: .provided), 0)
    }

    /// Stable, comparable representation of every table and index in the database.
    private static func schemaObjects(in db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: "SELECT type || '|' || name || '|' || COALESCE(sql, '') FROM sqlite_master WHERE type IN ('table', 'index') ORDER BY 1"
        )
    }
}
