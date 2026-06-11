import Foundation

// Fixtures for pocketcasts.sql-quoted-value-interpolation and
// pocketcasts.sql-inlist-interpolation.
class SqlInterpolationFixture {
    func quotedValueInterpolation(db: PCDatabase, uuid: String, term: String) throws {
        // ruleid: pocketcasts.sql-quoted-value-interpolation
        _ = try db.executeQuery("SELECT * FROM SJEpisode WHERE uuid = '\(uuid)'", values: nil)
        // ruleid: pocketcasts.sql-quoted-value-interpolation
        _ = try db.executeQuery("SELECT * FROM SJEpisode WHERE title LIKE '%\(term)%'", values: nil)
        // ok: pocketcasts.sql-quoted-value-interpolation
        _ = try db.executeQuery("SELECT * FROM SJEpisode WHERE uuid = ?", values: [uuid])
        // ok: pocketcasts.sql-quoted-value-interpolation
        _ = try db.executeQuery("SELECT * FROM SJEpisode WHERE fileType LIKE 'video%'", values: nil)
    }

    func quotedJoinIdiom(uuids: [String]) -> String {
        // ruleid: pocketcasts.sql-quoted-value-interpolation
        let list = uuids.map { "'\($0)'" }.joined(separator: ",")
        return list
    }

    func inListInterpolation(db: PCDatabase, uuids: [String]) throws {
        // ruleid: pocketcasts.sql-inlist-interpolation
        try db.executeUpdate("DELETE FROM SJEpisode WHERE uuid IN (\(uuids.joined(separator: ",")))", values: nil)
        // ok: pocketcasts.sql-inlist-interpolation
        try db.executeUpdate("DELETE FROM SJEpisode WHERE uuid IN (\(DBUtils.placeholders(amount: uuids.count)))", values: uuids)
        // ok: pocketcasts.sql-inlist-interpolation
        try db.executeUpdate("DELETE FROM SJEpisode WHERE uuid IN (SELECT episodeUuid FROM playlist)", values: nil)
    }
}
