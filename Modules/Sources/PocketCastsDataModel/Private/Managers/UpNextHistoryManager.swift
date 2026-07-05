import PocketCastsUtils
import Foundation
import GRDB
import GRDBMacros

/// Row record for the `PlaylistEpisodeHistory` table.
/// `date` is a raw `timeIntervalSince1970` Double rather than a `Date` for the same reason as
/// `PodcastFolderHistoryRow`: the table does exact-equality and GROUP BY on this column, and the
/// legacy SQL path binds dates as `timeIntervalSince1970` REALs — a `Date` property would encode
/// as a datetime string through the synthesized Codable conformance, splitting the storage format.
@GRDBRecord(table: "PlaylistEpisodeHistory")
struct PlaylistEpisodeHistoryRow: Equatable, Sendable {
    var id: Int64 = 0
    var episodePosition: Int32 = 0
    var episodeUuid = ""
    @GRDBColumn("playlist_id")
    var playlistId: Int64 = 0
    var upcoming: Int32 = 0
    var timeModified: Int64 = 0
    var wasDeleted = false
    var title: String?
    var podcastUuid: String?
    var date: Double = 0
}

public class UpNextHistoryManager {
    private let columnNames = [
        "id",
        "episodePosition",
        "episodeUuid",
        "playlist_id",
        "upcoming",
        "timeModified",
        "wasDeleted",
        "title",
        "podcastUuid",
    ]

    /// The number of days to keep the snapshots
    private let periodOfSnapshot: TimeInterval = 14.days

    // MARK: - Queries

    /// Saves the current Up Next state into another table
    /// So it can be reverted later in case of wrong syncs
    func snapshot(dbQueue: GRDBQueue) {
        let date = Date().timeIntervalSince1970
        let cutoff = Date().addingTimeInterval(-periodOfSnapshot).timeIntervalSince1970
        dbQueue.write { db in
            let upNextRows = try Row.fetchAll(
                db,
                Table(DataManager.playlistEpisodeTableName).filter(Column("playlist_id") == UpNextDataManager.upNextPlaylistId)
            )
            for row in upNextRows {
                try PlaylistEpisodeHistoryRow(
                    id: row["id"],
                    episodePosition: row["episodePosition"],
                    episodeUuid: row["episodeUuid"],
                    playlistId: row["playlist_id"],
                    upcoming: row["upcoming"],
                    timeModified: row["timeModified"],
                    wasDeleted: row["wasDeleted"],
                    title: row["title"],
                    podcastUuid: row["podcastUuid"],
                    date: date
                ).insert(db)
            }
            try PlaylistEpisodeHistoryRow.filter(PlaylistEpisodeHistoryRow.Columns.date <= cutoff).deleteAll(db)
        }
    }

    /// Return all the available Up Next entries
    func entries(dbQueue: GRDBQueue) -> [UpNextHistoryEntry] {
        let counts = dbQueue.read { db in
            try PlaylistEpisodeHistoryRow
                .select(PlaylistEpisodeHistoryRow.Columns.date, count(PlaylistEpisodeHistoryRow.Columns.date).forKey("count"), as: HistoryDateCount.self)
                .group(PlaylistEpisodeHistoryRow.Columns.date)
                .order(PlaylistEpisodeHistoryRow.Columns.date.desc)
                .fetchAll(db)
        } ?? []

        return counts.map { UpNextHistoryEntry(date: Date(timeIntervalSince1970: $0.date), episodeCount: $0.count) }
    }

    func episodes(entry: Date, dbQueue: GRDBQueue) -> [String] {
        return dbQueue.read { db in
            try PlaylistEpisodeHistoryRow
                .filter(PlaylistEpisodeHistoryRow.Columns.date == entry.timeIntervalSince1970)
                .order(PlaylistEpisodeHistoryRow.Columns.episodePosition.asc)
                .select(PlaylistEpisodeHistoryRow.Columns.episodeUuid, as: String.self)
                .fetchAll(db)
        } ?? []
    }

    public struct UpNextHistoryEntry: Hashable, Identifiable {
        public var id: Date {
            date
        }

        public let date: Date
        public let episodeCount: Int
    }

    /// Decodes the aggregate `(date, COUNT(date))` rows produced by `entries(dbQueue:)`.
    private struct HistoryDateCount: Decodable, FetchableRecord {
        let date: Double
        let count: Int
    }
}
