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

    func grdbSpellingRawSQL(uuid: String, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            // ruleid: pocketcasts.no-new-raw-sql-in-data-managers
            try db.execute(sql: "DELETE FROM SJEpisode WHERE uuid = ?", arguments: [uuid])
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

// Fixtures for pocketcasts.no-mixed-db-api-families-in-db-closure. The finding is
// reported at the legacy (PCDatabase-family) call anchored inside the mixed closure.

final class MixedDBFamiliesExample {
    func mixedWriteLegacyPlusQueryInterface(uuid: String, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            // ruleid: pocketcasts.no-mixed-db-api-families-in-db-closure, pocketcasts.no-new-raw-sql-in-data-managers
            try db.executeUpdate("UPDATE SJPodcast SET syncStatus = 1 WHERE uuid = ?", values: [uuid])
            try Podcast
                .filter(Podcast.Columns.uuid == uuid)
                .updateAll(db, Podcast.Columns.syncStatus.set(to: 1))
        }
    }

    func mixedWriteLegacyPlusExecute(uuid: String, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            // ruleid: pocketcasts.no-mixed-db-api-families-in-db-closure, pocketcasts.no-new-raw-sql-in-data-managers
            try db.executeQuery("SELECT 1", values: nil)
            // ruleid: pocketcasts.no-new-raw-sql-in-data-managers
            try db.execute(sql: "UPDATE SJPodcast SET syncStatus = 1", arguments: [uuid])
        }
    }

    func mixedNestedInsideDoCatch(uuid: String, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            do {
                if uuid.isEmpty {
                    // ruleid: pocketcasts.no-mixed-db-api-families-in-db-closure, pocketcasts.no-new-raw-sql-in-data-managers
                    try db.executeUpdate("UPDATE SJPodcast SET syncStatus = 1 WHERE uuid = ?", values: [uuid])
                } else {
                    try Podcast
                        .filter(Podcast.Columns.uuid == uuid)
                        .updateAll(db, Podcast.Columns.syncStatus.set(to: 1))
                }
            } catch {
                FileLog.shared.addMessage("failed: \(error)")
            }
        }
    }

    func mixedReadLegacyPlusFetch(uuid: String, dbQueue: GRDBQueue) {
        dbQueue.read { db in
            // ruleid: pocketcasts.no-mixed-db-api-families-in-db-closure, pocketcasts.no-new-raw-sql-in-data-managers
            try db.executeQuery("SELECT * FROM SJEpisode WHERE uuid = ?", values: [uuid])
            _ = try Episode.fetchOne(db, key: uuid)
        }
    }

    func mixedWriteLegacyPlusOptionalQueryInterface(uuid: String, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            // ruleid: pocketcasts.no-mixed-db-api-families-in-db-closure, pocketcasts.no-new-raw-sql-in-data-managers
            try db.executeUpdate("UPDATE SJPodcast SET syncStatus = 1 WHERE uuid = ?", values: [uuid])
            try? Podcast
                .filter(Podcast.Columns.uuid == uuid)
                .updateAll(db, Podcast.Columns.syncStatus.set(to: 1))
        }
    }

    func mixedWriteLegacyPlusForcedExecute(uuid: String, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            // ruleid: pocketcasts.no-mixed-db-api-families-in-db-closure, pocketcasts.no-new-raw-sql-in-data-managers
            try db.executeQuery("SELECT 1", values: nil)
            // ruleid: pocketcasts.no-new-raw-sql-in-data-managers
            try! db.execute(sql: "UPDATE SJPodcast SET syncStatus = 1", arguments: [uuid])
        }
    }

    func mixedReadLegacyPlusForcedFetch(uuid: String, dbQueue: GRDBQueue) {
        dbQueue.read { db in
            // ruleid: pocketcasts.no-mixed-db-api-families-in-db-closure, pocketcasts.no-new-raw-sql-in-data-managers
            try db.executeQuery("SELECT * FROM SJEpisode WHERE uuid = ?", values: [uuid])
            _ = try! Episode.fetchOne(db, key: uuid)
        }
    }

    func mixedReadLegacyPlusOptionalExecute(uuid: String, dbQueue: GRDBQueue) {
        dbQueue.read { db in
            // ruleid: pocketcasts.no-mixed-db-api-families-in-db-closure, pocketcasts.no-new-raw-sql-in-data-managers
            try db.executeQuery("SELECT 1", values: nil)
            // ruleid: pocketcasts.no-new-raw-sql-in-data-managers
            try? db.execute(sql: "SELECT 1")
        }
    }

    func pureLegacyWriteIsNotMixed(uuid: String, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            // ok: pocketcasts.no-mixed-db-api-families-in-db-closure
            // ruleid: pocketcasts.no-new-raw-sql-in-data-managers
            try db.executeUpdate("UPDATE SJPodcast SET syncStatus = 1 WHERE uuid = ?", values: [uuid])
            // ruleid: pocketcasts.no-new-raw-sql-in-data-managers
            try db.executeUpdate("UPDATE SJPodcast SET subscribed = 1 WHERE uuid = ?", values: [uuid])
        }
    }

    func pureGRDBWriteIsNotMixed(uuid: String, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try Podcast
                .filter(Podcast.Columns.uuid == uuid)
                .updateAll(db, Podcast.Columns.syncStatus.set(to: 1))
            // ok: pocketcasts.no-mixed-db-api-families-in-db-closure
            // ruleid: pocketcasts.no-new-raw-sql-in-data-managers
            try db.execute(sql: "UPDATE SJPodcast SET subscribed = 1", arguments: [uuid])
        }
    }
}
