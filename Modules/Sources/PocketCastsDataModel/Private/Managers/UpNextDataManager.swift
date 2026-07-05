import PocketCastsUtils
import Foundation
import GRDB
import GRDBMacros

/// Row record for the `SJPlaylistEpisode` table covering exactly the six columns this manager
/// maintains — the legacy INSERT/UPDATE touch the same six, leaving the rest (e.g. `wasDeleted`)
/// on their schema defaults. Do not add further columns: a record UPDATE writes every declared
/// column, so including `wasDeleted` would reset flags the legacy path leaves untouched.
@GRDBRecord(table: "SJPlaylistEpisode")
struct PlaylistEpisodeRow: Equatable, Sendable {
    var id: Int64 = 0
    var episodePosition: Int32 = 0
    var episodeUuid = ""
    @GRDBColumn("playlist_id")
    var playlistId: Int64 = 0
    var title = ""
    var podcastUuid = ""

    init(playlistEpisode: PlaylistEpisode) {
        id = playlistEpisode.id
        episodePosition = playlistEpisode.episodePosition
        episodeUuid = playlistEpisode.episodeUuid
        playlistId = Int64(UpNextDataManager.upNextPlaylistId)
        title = playlistEpisode.title
        podcastUuid = playlistEpisode.podcastUuid
    }

    func asPlaylistEpisode() -> PlaylistEpisode {
        let episode = PlaylistEpisode()
        episode.id = id
        episode.episodePosition = episodePosition
        episode.episodeUuid = episodeUuid
        episode.title = title
        episode.podcastUuid = podcastUuid
        return episode
    }
}

class UpNextDataManager {
    static let upNextPlaylistId = 1

    private let columnNames = [
        "id",
        "episodePosition",
        "episodeUuid",
        "playlist_id",
        "title",
        "podcastUuid"
    ]

    private var cachedItems = [PlaylistEpisode]()
    private var allUuids = Set<String>()
    private lazy var cachedItemsQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "au.com.pocketcasts.UpNextItemsQueue")

        return queue
    }()

    func setup(dbQueue: GRDBQueue) {
        cacheEpisodes(dbQueue: dbQueue)
    }

    // MARK: - Queries

    func allUpNextPlaylistEpisodes(dbQueue: GRDBQueue) -> [PlaylistEpisode] {
        cachedItemsQueue.sync {
            cachedItems
        }
    }

    func findPlaylistEpisode(uuid: String, dbQueue: GRDBQueue) -> PlaylistEpisode? {
        cachedItemsQueue.sync {
            for episode in cachedItems {
                if episode.episodeUuid == uuid {
                    return episode
                }
            }

            return nil
        }
    }

    func playlistEpisodeAt(index: Int, dbQueue: GRDBQueue) -> PlaylistEpisode? {
        cachedItemsQueue.sync {
            cachedItems[safe: index]
        }
    }

    func positionForPlaylistEpisode(bottomOfList: Bool, dbQueue: GRDBQueue) -> Int32 {
        cachedItemsQueue.sync {
            if bottomOfList {
                if let lastItem = cachedItems.last {
                    return lastItem.episodePosition + 1
                }
            }

            return 1
        }
    }

    func playlistEpisodeCount(dbQueue: GRDBQueue) -> Int {
        cachedItemsQueue.sync {
            cachedItems.count
        }
    }

    func isEpisodePresent(uuid: String, dbQueue: GRDBQueue) -> Bool {
        cachedItemsQueue.sync {
            return allUuids.contains(uuid)
        }
    }

    // MARK: - Updates

    func save(playlistEpisode: PlaylistEpisode, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            // move every episode after this one down one, if there are any
            try PlaylistEpisodeRow
                .filter(PlaylistEpisodeRow.Columns.episodePosition >= playlistEpisode.episodePosition)
                .filter(PlaylistEpisodeRow.Columns.episodeUuid != playlistEpisode.episodeUuid)
                .filter(Column("wasDeleted") == false)
                .filter(PlaylistEpisodeRow.Columns.playlistId == UpNextDataManager.upNextPlaylistId)
                .updateAll(db, PlaylistEpisodeRow.Columns.episodePosition.set(to: PlaylistEpisodeRow.Columns.episodePosition + 1))

            if playlistEpisode.id == 0 {
                playlistEpisode.id = DBUtils.generateUniqueId()
                try PlaylistEpisodeRow(playlistEpisode: playlistEpisode).insert(db)
            } else {
                // catch recordNotFound: the legacy UPDATE ... WHERE id silently no-ops on a missing row
                try? PlaylistEpisodeRow(playlistEpisode: playlistEpisode).update(db)
            }
        }
        saveOrdering(dbQueue: dbQueue)
        cacheEpisodes(dbQueue: dbQueue)
    }

    func save(playlistEpisodes: [PlaylistEpisode], dbQueue: GRDBQueue) {
        dbQueue.write { db in
            let topPosition = playlistEpisodes[0].episodePosition
            let uuids = playlistEpisodes.map(\.episodeUuid)

            // move every episode after this one down, if there are any
            try PlaylistEpisodeRow
                .filter(PlaylistEpisodeRow.Columns.episodePosition >= topPosition)
                .filter(Column("wasDeleted") == false)
                .filter(PlaylistEpisodeRow.Columns.playlistId == UpNextDataManager.upNextPlaylistId)
                .filter(!uuids.contains(PlaylistEpisodeRow.Columns.episodeUuid))
                .updateAll(db, PlaylistEpisodeRow.Columns.episodePosition.set(to: PlaylistEpisodeRow.Columns.episodePosition + playlistEpisodes.count))

            for playlistEpisode in playlistEpisodes {
                if playlistEpisode.id == 0 {
                    playlistEpisode.id = DBUtils.generateUniqueId()
                    try PlaylistEpisodeRow(playlistEpisode: playlistEpisode).insert(db)
                } else {
                    // catch recordNotFound: the legacy UPDATE ... WHERE id silently no-ops on a missing row
                    try? PlaylistEpisodeRow(playlistEpisode: playlistEpisode).update(db)
                }
            }
        }
        saveOrdering(dbQueue: dbQueue)
        cacheEpisodes(dbQueue: dbQueue)
    }

    func delete(playlistEpisode: PlaylistEpisode, dbQueue: GRDBQueue) {
        dbQueue.deleteAll(
            PlaylistEpisodeRow.self,
            filter: PlaylistEpisodeRow.Columns.id == playlistEpisode.id && PlaylistEpisodeRow.Columns.playlistId == UpNextDataManager.upNextPlaylistId
        )

        saveOrdering(dbQueue: dbQueue)
        cacheEpisodes(dbQueue: dbQueue)
    }

    func deleteAllUpNextEpisodes(dbQueue: GRDBQueue) {
        dbQueue.deleteAll(
            PlaylistEpisodeRow.self,
            filter: PlaylistEpisodeRow.Columns.playlistId == UpNextDataManager.upNextPlaylistId
        )

        cacheEpisodes(dbQueue: dbQueue)
    }

    func deleteAllUpNextEpisodesExcept(episodeUuid: String, dbQueue: GRDBQueue) {
        dbQueue.deleteAll(
            PlaylistEpisodeRow.self,
            filter: PlaylistEpisodeRow.Columns.episodeUuid != episodeUuid && PlaylistEpisodeRow.Columns.playlistId == UpNextDataManager.upNextPlaylistId
        )

        cacheEpisodes(dbQueue: dbQueue)
    }

    func deleteAllUpNextEpisodesNotIn(uuids: [String], dbQueue: GRDBQueue) {
        if uuids.isEmpty {
            dbQueue.deleteAll(
                PlaylistEpisodeRow.self,
                filter: PlaylistEpisodeRow.Columns.playlistId == UpNextDataManager.upNextPlaylistId
            )
        } else {
            dbQueue.deleteAll(
                PlaylistEpisodeRow.self,
                filter: !uuids.contains(PlaylistEpisodeRow.Columns.episodeUuid) && PlaylistEpisodeRow.Columns.playlistId == UpNextDataManager.upNextPlaylistId
            )
        }
        cacheEpisodes(dbQueue: dbQueue)
    }

    func deleteAllUpNextEpisodesIn(uuids: [String], dbQueue: GRDBQueue) {
        guard !uuids.isEmpty else { return }

        dbQueue.deleteAll(
            PlaylistEpisodeRow.self,
            filter: uuids.contains(PlaylistEpisodeRow.Columns.episodeUuid) && PlaylistEpisodeRow.Columns.playlistId == UpNextDataManager.upNextPlaylistId
        )
        saveOrdering(dbQueue: dbQueue)
        cacheEpisodes(dbQueue: dbQueue)
    }

    func movePlaylistEpisode(from: Int, to: Int, dbQueue: GRDBQueue) {
        var resortedItems = cachedItems

        if from == -1, to == 0 {
            // special case where we just added a new episode to the top, nothing needs to be done just redo the ordering below
        } else if let episodeToMove = resortedItems[safe: from] {
            resortedItems.remove(at: from)

            if to >= resortedItems.count {
                resortedItems.append(episodeToMove)
            } else {
                resortedItems.insert(episodeToMove, at: to)
            }
        }

        // persist index changes
        persistOrdering(of: resortedItems, dbQueue: dbQueue, logContext: "movePlaylistEpisode")
        cacheEpisodes(dbQueue: dbQueue)
    }

    // MARK: - Up Next History (Restoring)

    public func refresh(dbQueue: GRDBQueue) {
        cacheEpisodes(dbQueue: dbQueue)
    }

    // MARK: - Caching

    private func cacheEpisodes(dbQueue: GRDBQueue) {
        let rows = dbQueue.fetchAll(
            PlaylistEpisodeRow
                .filter(PlaylistEpisodeRow.Columns.playlistId == UpNextDataManager.upNextPlaylistId)
                .order(PlaylistEpisodeRow.Columns.episodePosition)
        )

        let newItems = rows.map { $0.asPlaylistEpisode() }
        cachedItemsQueue.sync {
            cachedItems = newItems
            allUuids = Set(newItems.map(\.episodeUuid))
        }
    }

    // MARK: - Ordering

    private func saveOrdering(dbQueue: GRDBQueue) {
        cacheEpisodes(dbQueue: dbQueue)
        let sortedItems = cachedItems
        persistOrdering(of: sortedItems, dbQueue: dbQueue, logContext: "saveOrdering")
    }

    /// Writes each episode's index in `items` back as its `episodePosition`
    private func persistOrdering(of items: [PlaylistEpisode], dbQueue: GRDBQueue, logContext: String) {
        dbQueue.write { db in
            for (index, episode) in items.enumerated() {
                try PlaylistEpisodeRow
                    .filter(PlaylistEpisodeRow.Columns.id == episode.id)
                    .updateAll(db, PlaylistEpisodeRow.Columns.episodePosition.set(to: index))
            }
        }
    }

    // MARK: - Conversion

    private func createEpisodeFrom(resultSet rs: PCDBResultSet) -> PlaylistEpisode {
        let episode = PlaylistEpisode()

        episode.id = rs.longLongInt(forColumn: "id")
        episode.episodePosition = rs.int(forColumn: "episodePosition")
        episode.episodeUuid = DBUtils.nonNilStringFromColumn(resultSet: rs, columnName: "episodeUuid")
        episode.title = DBUtils.nonNilStringFromColumn(resultSet: rs, columnName: "title")
        episode.podcastUuid = DBUtils.nonNilStringFromColumn(resultSet: rs, columnName: "podcastUuid")

        return episode
    }
}
