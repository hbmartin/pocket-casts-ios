import GRDB
import Foundation
@testable import PocketCastsDataModel

extension DatabasePool {
    enum TestError: Error {
        case temporaryDirectoryCreationFailure
    }

    static func newTestDatabase(databaseName: String? = nil) throws -> DatabasePool? {
        var config = Configuration()
        config.busyMode = .timeout(10)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PocketCastsDataModelTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw TestError.temporaryDirectoryCreationFailure
        }

        let databaseURL = root.appendingPathComponent(databaseName ?? "database.sqlite3")
        return try DatabasePool(path: databaseURL.path, configuration: config)
    }
}

extension DataManager {
    static func newTestDataManager() -> DataManager {
        try! DataManager(dbQueue: GRDBQueue(dbPool: DatabasePool.newTestDatabase()!))
    }

    func setPodcastSettingsForTest(podcastUuid: String, settings: String, syncStatus: Int32 = SyncStatus.synced.rawValue) throws {
        try testDbQueue.dbPool.write { db in
            try db.execute(
                sql: "UPDATE \(DataManager.podcastTableName) SET settings = ?, syncStatus = ? WHERE uuid = ?",
                arguments: [settings, syncStatus, podcastUuid]
            )
        }
    }

    /// Test-only accessor for the database queue. Used for low-level GRDB Record type tests.
    var testDbQueue: GRDBQueue {
        dbQueue
    }
}
