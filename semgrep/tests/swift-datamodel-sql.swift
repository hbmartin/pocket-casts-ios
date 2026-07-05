import Foundation

// Fixtures for pocketcasts.no-new-raw-sql-in-data-managers.

final class RawSQLDataManagerExample {
    func legacyFind(uuid: String, dbQueue: GRDBQueue) -> Episode? {
        // ruleid: pocketcasts.no-new-raw-sql-in-data-managers
        DataHelper.run(query: "SELECT * FROM SJEpisode WHERE uuid = ?", values: [uuid], methodName: "find", onQueue: dbQueue)
        return nil
    }

    func legacyRead(uuid: String, dbQueue: GRDBQueue) {
        dbQueue.read { db in
            // ruleid: pocketcasts.no-new-raw-sql-in-data-managers
            _ = try db.executeQuery("SELECT * FROM SJEpisode WHERE uuid = ?", values: [uuid])
        }
    }

    func legacyWrite(uuid: String, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            // ruleid: pocketcasts.no-new-raw-sql-in-data-managers
            try db.executeUpdate("DELETE FROM SJEpisode WHERE uuid = ?", values: [uuid])
        }
    }

    func queryInterfaceFind(uuid: String, dbQueue: GRDBQueue) -> Episode? {
        // ok: pocketcasts.no-new-raw-sql-in-data-managers
        dbQueue.fetchOne(Episode.filter(Episode.Columns.uuid == uuid))
    }

    func queryInterfaceDelete(uuid: String, dbQueue: GRDBQueue) {
        // ok: pocketcasts.no-new-raw-sql-in-data-managers
        dbQueue.deleteAll(Episode.self, filter: Episode.Columns.uuid == uuid)
    }
}
