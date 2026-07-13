import Foundation
import GRDB

// MARK: - Observation payloads

/// The database inputs of the home podcast grid, captured in one consistent read.
///
/// This is a change-detection payload, not a render model: the B6 pilot keeps the
/// grid's existing `refreshGridItems()` pipeline as the render path and uses
/// snapshot emissions purely as the "the grid's data changed" signal. Cells carry
/// only the columns the grid renders or sorts on, so unrelated writes (sync
/// bookkeeping, feed metadata the grid doesn't show) don't re-trigger it. Dates
/// stay in their stored representation (epoch seconds) — nothing here is displayed.
public struct HomeGridSnapshot: Equatable, Sendable {
    public struct PodcastCell: Equatable, Sendable {
        public let uuid: String
        public let title: String?
        public let folderUuid: String?
        public let sortOrder: Int32
        public let addedDate: Double?
        /// Unplayed/in-progress, unarchived episode count (the grid's unplayed badge).
        public let unfinishedCount: Int
        /// Newest unfinished episode date (episode-date sorts and latest-episode badges).
        public let latestUnfinishedEpisodeDate: Double?
    }

    public struct FolderCell: Equatable, Sendable {
        public let uuid: String
        public let name: String
        public let color: Int32
        public let sortOrder: Int32
        public let addedDate: Double?
    }

    public let podcasts: [PodcastCell]
    public let folders: [FolderCell]
}

/// A database-derived app-badge count source. Non-database inputs (the badge mode
/// setting, push permission, last-close date, the currently playing episode)
/// belong to the caller, which restarts the observation when they change.
public enum BadgeCountSource: Equatable, Sendable {
    /// Unplayed, unarchived episodes of subscribed podcasts, optionally only those
    /// added after a date. Observes exactly the SQL `subscribedUnplayedEpisodeCount`
    /// runs.
    case subscribedUnplayed(addedAfter: Date?)
    /// A playlist's episode count, using the same `PlaylistQueryBuilder` count
    /// request the filter UI runs. The playlist row itself is part of the observed
    /// region, so rule edits re-count without a restart. `episodeUuidToAdd` pins
    /// the currently playing episode into the count — playback state, not database
    /// state, so pass a fresh value (restart) when it changes.
    case playlistEpisodes(playlistUuid: String, episodeUuidToAdd: String?)
}

// MARK: - DatabaseObserving

/// Reactive read path (B6 ValueObservation pilot): database-driven `AsyncStream`s
/// that replace poll-on-notification refresh for bounded read models.
///
/// The pattern for adopting this on a new screen:
/// 1. Add a method here returning `AsyncStream<Value>` (`Value: Equatable &
///    Sendable`), implemented on `DataManager` via `dbQueue.observe { db in ... }`.
///    Fetch **the same SQL the screen's synchronous reads use** (reuse the query
///    builders, don't re-derive) and keep the payload small: the region the fetch
///    closure reads determines which writes trigger emissions.
/// 2. The stream emits an initial value, then one value per committed write
///    transaction that touches the observed region, with consecutive duplicates
///    dropped. Values are produced off the main actor.
/// 3. Consumers own the lifecycle:
///    `task = Task { for await value in stream { apply(value) } }`, started and
///    cancelled with the screen (the app target is MainActor-isolated, so
///    `apply` runs on the main actor). Inputs that live outside the database
///    (settings, playback state) are handled by restarting the observation.
public protocol DatabaseObserving: AnyObject, Sendable {
    /// Streams the home grid's database inputs (subscribed podcasts, folders and
    /// unplayed-badge counts) whenever any of them change.
    func observeHomeGrid() -> AsyncStream<HomeGridSnapshot>

    /// Streams `[playlist uuid: episode count]` for all non-deleted playlists,
    /// re-emitting when episodes or playlist definitions change.
    func observePlaylistEpisodeCounts() -> AsyncStream<[String: Int]>

    /// Streams the app-badge count for the given source.
    func observeBadgeCount(_ source: BadgeCountSource) -> AsyncStream<Int>
}

extension DataManager: DatabaseObserving {
    public func observeHomeGrid() -> AsyncStream<HomeGridSnapshot> {
        dbQueue.observe { db in try HomeGridSnapshot.fetch(db) }
    }

    public func observePlaylistEpisodeCounts() -> AsyncStream<[String: Int]> {
        dbQueue.observe { db -> [String: Int] in
            let playlists = try EpisodeFilter
                .filter(EpisodeFilter.Columns.wasDeleted == false)
                .order(EpisodeFilter.Columns.sortPosition.asc)
                .fetchAll(db)
            var counts = [String: Int](minimumCapacity: playlists.count)
            for playlist in playlists {
                counts[playlist.uuid] = try PlaylistQueryBuilder
                    .countRequest(.episodeCount, for: playlist)
                    .fetchOne(db) ?? 0
            }
            return counts
        }
    }

    public func observeBadgeCount(_ source: BadgeCountSource) -> AsyncStream<Int> {
        switch source {
        case .subscribedUnplayed(let addedAfter):
            return dbQueue.observe { db in
                try DataManager.subscribedUnplayedCountRequest(addedAfter: addedAfter).fetchOne(db) ?? 0
            }
        case .playlistEpisodes(let playlistUuid, let episodeUuidToAdd):
            return dbQueue.observe { db -> Int in
                // The playlist row is fetched inside the tracking closure so the
                // count request is rebuilt (and stays correct) when its rules change.
                guard let playlist = try EpisodeFilter
                    .filter(EpisodeFilter.Columns.uuid == playlistUuid)
                    .fetchOne(db)
                else {
                    return 0
                }
                return try PlaylistQueryBuilder
                    .countRequest(.episodeCount, for: playlist, episodeUuidToAdd: episodeUuidToAdd)
                    .fetchOne(db) ?? 0
            }
        }
    }
}

// MARK: - Home grid fetch

extension HomeGridSnapshot {
    /// Decodes the per-podcast `(podcast_id, COUNT(id), MAX(publishedDate))` aggregate.
    private struct EpisodeAggregate: Decodable, FetchableRecord {
        let podcastId: Int64
        let count: Int
        let latest: Double?
    }

    /// Runs inside the observation's tracking closure: everything read here joins
    /// the observed region. The aggregate mirrors
    /// `PodcastDataManager.unfinishedCounts` (unfinished, unarchived episodes per
    /// podcast), widened with `MAX(publishedDate)` so new-episode arrivals and
    /// play/archive flips both surface as snapshot changes. Rows are ordered by
    /// uuid so equal database states always compare equal.
    static func fetch(_ db: Database) throws -> HomeGridSnapshot {
        let aggregates = try Table(DataManager.episodeTableName).all()
            .filter(Column("playingStatus") != PlayingStatus.completed.rawValue)
            .filter(Column("archived") == false)
            .select(
                [
                    Column("podcast_id").forKey("podcastId"),
                    GRDB.count(Column("id")).forKey("count"),
                    max(Column("publishedDate")).forKey("latest")
                ],
                as: EpisodeAggregate.self
            )
            .group(Column("podcast_id"))
            .fetchAll(db)
        let aggregatesById = Dictionary(aggregates.map { ($0.podcastId, $0) }, uniquingKeysWith: { first, _ in first })

        let podcastRows = try Row.fetchAll(
            db,
            Podcast
                .filter(Podcast.Columns.subscribed == 1)
                .select(Podcast.Columns.id, Podcast.Columns.uuid, Podcast.Columns.title, Podcast.Columns.folderUuid, Podcast.Columns.sortOrder, Podcast.Columns.addedDate)
                .order(Podcast.Columns.uuid)
                .asRequest(of: Row.self)
        )
        let podcasts = podcastRows.map { row in
            let aggregate = aggregatesById[row["id"] as Int64]
            return PodcastCell(
                uuid: row["uuid"],
                title: row["title"],
                folderUuid: row["folderUuid"],
                sortOrder: row["sortOrder"],
                addedDate: row["addedDate"],
                unfinishedCount: aggregate?.count ?? 0,
                latestUnfinishedEpisodeDate: aggregate?.latest
            )
        }

        let folderRows = try Row.fetchAll(
            db,
            Folder
                .filter(Folder.Columns.wasDeleted == false)
                .select(Folder.Columns.uuid, Folder.Columns.name, Folder.Columns.color, Folder.Columns.sortOrder, Folder.Columns.addedDate)
                .order(Folder.Columns.uuid)
                .asRequest(of: Row.self)
        )
        let folders = folderRows.map { row in
            FolderCell(
                uuid: row["uuid"],
                name: row["name"],
                color: row["color"],
                sortOrder: row["sortOrder"],
                addedDate: row["addedDate"]
            )
        }

        return HomeGridSnapshot(podcasts: podcasts, folders: folders)
    }
}
