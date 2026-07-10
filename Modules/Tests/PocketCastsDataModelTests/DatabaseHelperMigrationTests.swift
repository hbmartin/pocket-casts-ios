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

    /// Stable, comparable representation of every table and index in the database.
    private static func schemaObjects(in db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: "SELECT type || '|' || name || '|' || COALESCE(sql, '') FROM sqlite_master WHERE type IN ('table', 'index') ORDER BY 1"
        )
    }
}
