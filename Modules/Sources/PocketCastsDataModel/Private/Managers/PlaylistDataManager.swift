import PocketCastsUtils
import Foundation
import GRDB
import GRDBMacros

/// Row record for manual-playlist entries in `SJPlaylistEpisode`, covering exactly the seven
/// columns the legacy manual-playlist INSERT writes. Up Next rows use `PlaylistEpisodeRow`'s
/// six-column shape; the two must stay separate so each path's record UPDATE only writes the
/// columns its legacy SQL wrote.
@GRDBRecord(table: "SJPlaylistEpisode")
struct ManualPlaylistEpisodeRow: Equatable, Sendable {
    var id: Int64 = 0
    var episodePosition: Int32 = 0
    var episodeUuid = ""
    @GRDBColumn("playlist_id")
    var playlistId: Int64 = 0
    var title = ""
    var podcastUuid = ""
    @GRDBColumn("playlist_uuid")
    var playlistUuid: String?
}

class PlaylistDataManager {
    /// Legacy column names for non-GRDB code path.
    let columnNames = [
        "id",
        "autoDownloadEpisodes",
        "customIcon",
        "filterAllPodcasts",
        "filterAudioVideoType",
        "filterDownloaded",
        "filterFinished",
        "filterNotDownloaded",
        "filterPartiallyPlayed",
        "filterStarred",
        "filterUnplayed",
        "filterHours",
        "playlistName",
        "sortPosition",
        "sortType",
        "uuid",
        "podcastUuids",
        "autoDownloadLimit",
        "syncStatus",
        "wasDeleted",
        "filterDuration",
        "longerThan",
        "shorterThan",
        "manual",
        "showArchivedEpisodes",
        "playlistUpdateDate"
    ]

    func count(includeDeleted: Bool, dbQueue: GRDBQueue) -> Int {
        if includeDeleted {
            return dbQueue.count(EpisodeFilter.self)
        }
        return dbQueue.count(EpisodeFilter.self, filter: EpisodeFilter.Columns.wasDeleted == false)
    }

    func playlistEpisodeCount(clause: PlaylistQueryBuilder.SelectClause, playlist: EpisodeFilter, episodeUuidToAdd: String?, shouldShowArchived: Bool, dbQueue: GRDBQueue) -> Int {
        var count = 0
        dbQueue.read { db in
            do {
                let query = PlaylistQueryBuilder.query(clause: clause, for: playlist, episodeUuidToAdd: episodeUuidToAdd, shouldShowArchived: shouldShowArchived)
                let resultSet = try db.executeQuery(query.sql, values: query.arguments) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - PlaylistQueryBuilder generated smart-playlist query, fully parameterized
                defer { resultSet.close() }

                if resultSet.next() {
                    count = resultSet.long(forColumnIndex: 0)
                }
            } catch {
                FileLog.shared.addMessage("PlaylistDataManager.smartPlaylistEpisodeCount error: \(error)")
            }
        }

        return count
    }

    func playlistContainsPodcast(podcastUuid: String, includeDeleted: Bool = false, dbQueue: GRDBQueue) -> Bool {
        var exists = false
        dbQueue.read { db in
            do {
                let query = PlaylistQueryBuilder.podcastExistsInPlaylistEpisodesQuery(includeDeleted: includeDeleted)
                let resultSet = try db.executeQuery(query, values: [podcastUuid]) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - PlaylistQueryBuilder generated query, fully parameterized
                defer { resultSet.close() }

                exists = resultSet.next()
            } catch {
                FileLog.shared.addMessage("PlaylistDataManager.playlistContainsPodcast error: \(error)")
            }
        }

        return exists
    }

    /// The GRDB twin of the raw `SELECT *` playlist list queries: optional manual/deleted filters,
    /// ordered by sortPosition ascending like every legacy variant.
    private func grdbAllPlaylists(manual: Bool? = nil, includeDeleted: Bool, in dbQueue: GRDBQueue) -> [EpisodeFilter] {
        var request = EpisodeFilter.order(EpisodeFilter.Columns.sortPosition.asc)
        if let manual {
            request = request.filter(EpisodeFilter.Columns.manual == manual)
        }
        if !includeDeleted {
            request = request.filter(EpisodeFilter.Columns.wasDeleted == false)
        }
        return dbQueue.fetchAll(request)
    }

    func allPlaylists(includeDeleted: Bool, dbQueue: GRDBQueue) -> [EpisodeFilter] {
        return grdbAllPlaylists(includeDeleted: includeDeleted, in: dbQueue)
    }

    func allSmartPlaylists(includeDeleted: Bool, dbQueue: GRDBQueue) -> [EpisodeFilter] {
        return grdbAllPlaylists(manual: false, includeDeleted: includeDeleted, in: dbQueue)
    }

    func allManualPlaylists(includeDeleted: Bool, dbQueue: GRDBQueue) -> [EpisodeFilter] {
        return grdbAllPlaylists(manual: true, includeDeleted: includeDeleted, in: dbQueue)
    }

    func findBy(uuid: String, dbQueue: GRDBQueue) -> EpisodeFilter? {
        return dbQueue.fetchOne(EpisodeFilter.filter(EpisodeFilter.Columns.uuid == uuid))
    }

    func deleteDeletedPlaylists(dbQueue: GRDBQueue) {
        dbQueue.deleteAll(EpisodeFilter.self, filter: EpisodeFilter.Columns.wasDeleted == true)
    }

    func allUnsyncedPlaylists(dbQueue: GRDBQueue) -> [EpisodeFilter] {
        return dbQueue.fetchAll(
            EpisodeFilter
                .filter(EpisodeFilter.Columns.syncStatus == SyncStatus.notSynced.rawValue)
                .order(EpisodeFilter.Columns.sortPosition.asc)
        )
    }

    func playlistContainsEpisode(episodeUuid: String, includeDeleted: Bool, dbQueue: GRDBQueue) -> Bool {
        return dbQueue.read { (db: Database) -> Bool in
            var request = Table(DataManager.playlistEpisodeTableName)
                .filter(Column("episodeUuid") == episodeUuid)
                .filter(Column("playlist_uuid") != nil)
            if !includeDeleted {
                request = request.filter(Column("wasDeleted") == false)
            }
            return try !request.isEmpty(db)
        } ?? false
    }

    func manualPlaylistUUIDs(for episodeUUID: String, dbQueue: GRDBQueue) -> [String] {
        // DISTINCT over the nullable column matches the legacy GROUP BY; NULLs drop out like
        // the legacy `if let` did
        let uuids = dbQueue.read { (db: Database) -> [String?] in
            try Table(DataManager.playlistEpisodeTableName)
                .filter(Column("episodeUuid") == episodeUUID)
                .select([Column("playlist_uuid")], as: String?.self)
                .distinct()
                .fetchAll(db)
        } ?? []
        return uuids.compactMap { $0 }
    }

    func updatePosition(playlist: EpisodeFilter, newPosition: Int32, dbQueue: GRDBQueue) {
        var playlist = playlist
        playlist.sortPosition = newPosition
        playlist.syncStatus = SyncStatus.notSynced.rawValue

        dbQueue.updateAll(
            EpisodeFilter.self,
            filter: EpisodeFilter.Columns.uuid == playlist.uuid,
            EpisodeFilter.Columns.sortPosition.set(to: playlist.sortPosition),
            EpisodeFilter.Columns.syncStatus.set(to: playlist.syncStatus),
            EpisodeFilter.Columns.playlistUpdateDate.set(to: Date.now.timeIntervalSince1970)
        )
    }

    /// Reorder a specific episode within a manual playlist to a new index
    func moveEpisode(_ episodeUuid: String, in playlist: EpisodeFilter, to newIndex: Int, dbQueue: GRDBQueue) {
        var playlist = playlist

        playlist.syncStatus = SyncStatus.notSynced.rawValue
        let syncStatus = playlist.syncStatus
        let playlistUuid = playlist.uuid

        dbQueue.write { db in
            // Load existing order (id + episodeUuid) for this playlist
            let items = try Row.fetchAll(
                db,
                Table(DataManager.playlistEpisodeTableName)
                    .filter(Column("playlist_uuid") == playlistUuid)
                    .order(Column("episodePosition").asc)
                    .select([Column("id"), Column("episodeUuid")])
                    .asRequest(of: Row.self)
            ).map { (id: $0["id"] as Int64, uuid: $0["episodeUuid"] as String) }

            guard let currentIndex = items.firstIndex(where: { $0.uuid == episodeUuid }) else { return }

            let clampedTargetIndex = newIndex.clamped(to: 0...max(items.count - 1, 0))
            if clampedTargetIndex == currentIndex { return }

            var reordered = items
            let element = reordered.remove(at: currentIndex)
            let clampedIndex = newIndex.clamped(to: 0...reordered.count)
            reordered.insert(element, at: clampedIndex)

            // Persist new positions
            for (index, item) in reordered.enumerated() {
                try Table(DataManager.playlistEpisodeTableName)
                    .filter(Column("id") == item.id)
                    .updateAll(db, Column("episodePosition").set(to: index))
            }

            try EpisodeFilter
                .filter(EpisodeFilter.Columns.uuid == playlistUuid)
                .updateAll(db, EpisodeFilter.Columns.syncStatus.set(to: syncStatus), EpisodeFilter.Columns.playlistUpdateDate.set(to: Date.now.timeIntervalSince1970))
        }
    }

    /// Set a specific position for an episode within a manual playlist.
    /// This is equivalent to calling moveEpisode to the given index.
    func updateEpisodePosition(_ episodeUuid: String, in playlist: EpisodeFilter, to position: Int32, dbQueue: GRDBQueue) {
        moveEpisode(episodeUuid, in: playlist, to: Int(position), dbQueue: dbQueue)
    }

    /// Delete specific episodes from a manual playlist and reindex remaining items
    func deleteEpisodes(_ episodeUuids: [String], from playlist: EpisodeFilter, dbQueue: GRDBQueue) {
        guard !episodeUuids.isEmpty else { return }
        var playlist = playlist

        playlist.syncStatus = SyncStatus.notSynced.rawValue
        let syncStatus = playlist.syncStatus
        let playlistUuid = playlist.uuid

        dbQueue.write { db in
            let removedCount = try Table(DataManager.playlistEpisodeTableName)
                .filter(Column("playlist_uuid") == playlistUuid)
                .filter(episodeUuids.contains(Column("episodeUuid")))
                .deleteAll(db)
            if removedCount == 0 { return }

            // Reindex remaining
            let ids = try Row.fetchAll(
                db,
                Table(DataManager.playlistEpisodeTableName)
                    .filter(Column("playlist_uuid") == playlistUuid)
                    .order(Column("episodePosition").asc)
                    .select([Column("id")])
                    .asRequest(of: Row.self)
            ).map { $0["id"] as Int64 }
            for (index, id) in ids.enumerated() {
                try Table(DataManager.playlistEpisodeTableName)
                    .filter(Column("id") == id)
                    .updateAll(db, Column("episodePosition").set(to: index))
            }

            try EpisodeFilter
                .filter(EpisodeFilter.Columns.uuid == playlistUuid)
                .updateAll(db, EpisodeFilter.Columns.syncStatus.set(to: syncStatus), EpisodeFilter.Columns.playlistUpdateDate.set(to: Date.now.timeIntervalSince1970))
        }
    }

    /// Just delete episodes from a playlist and nothing more
    func rawDeleteEpisodes(_ episodeUuids: [String], from playlist: EpisodeFilter, dbQueue: GRDBQueue) {
        guard !episodeUuids.isEmpty else { return }

        _ = dbQueue.write { db in
            try Table(DataManager.playlistEpisodeTableName)
                .filter(Column("playlist_uuid") == playlist.uuid)
                .filter(episodeUuids.contains(Column("episodeUuid")))
                .deleteAll(db)
        }
    }

    /// Delete all playlist-episode relationships for the given playlist
    func deleteAllEpisodes(in playlist: EpisodeFilter, dbQueue: GRDBQueue) {
        var playlist = playlist

        playlist.syncStatus = SyncStatus.notSynced.rawValue
        let syncStatus = playlist.syncStatus
        let playlistUuid = playlist.uuid
        let playlistId = playlist.id

        dbQueue.write { db in
            let removedCount = try Table(DataManager.playlistEpisodeTableName)
                .filter(Column("playlist_uuid") == playlistUuid || Column("playlist_id") == playlistId)
                .deleteAll(db)

            if removedCount > 0 {
                try EpisodeFilter
                    .filter(EpisodeFilter.Columns.uuid == playlistUuid)
                    .updateAll(db, EpisodeFilter.Columns.syncStatus.set(to: syncStatus), EpisodeFilter.Columns.playlistUpdateDate.set(to: Date.now.timeIntervalSince1970))
            }
        }
    }

    // Returns the saved playlist with `id`/`playlistUpdateDate` populated. Callers should prefer the
    // return value over the argument: a local `var` copy is mutated and persisted so this stays correct
    // when `EpisodeFilter` becomes a value-type struct (today, as a class, the copy aliases the same
    // instance, preserving the existing back-mutation behaviour).
    @discardableResult
    func save(playlist: EpisodeFilter, dbQueue: GRDBQueue) -> EpisodeFilter {
        var saved = playlist
        dbQueue.write { db in
            saved = try save(playlist: playlist, db: db)
        }
        return saved
    }

    @discardableResult
    func save(playlist: EpisodeFilter, db: Database) throws -> EpisodeFilter {
        var playlist = playlist
        // Resolve insert-vs-update by uuid (the stable identity), not by the local row id: value-type
        // callers don't get the assigned id back, so a re-save of an already-persisted filter still
        // arrives with id == 0. Keying on id alone would insert a duplicate row for the same uuid
        // (e.g. `save(filter)` then `add(episodes:to:filter)`, whose internal save still sees id == 0).
        if playlist.id == 0, !playlist.uuid.isEmpty, let existingId = try existingPlaylistId(uuid: playlist.uuid, db: db) {
            playlist.id = existingId
        }
        let isInsert = playlist.id == 0
        if isInsert {
            playlist.id = DBUtils.generateUniqueId()
        }
        playlist.playlistUpdateDate = .now

        try playlist.save(db)

        return playlist
    }

    /// The persisted row id for the playlist with this uuid, or nil if it isn't saved yet.
    private func existingPlaylistId(uuid: String, dbQueue: GRDBQueue) -> Int64? {
        return dbQueue.fetchOne(EpisodeFilter.filter(EpisodeFilter.Columns.uuid == uuid))?.id
    }

    private func existingPlaylistId(uuid: String, db: Database) throws -> Int64? {
        try EpisodeFilter
            .filter(EpisodeFilter.Columns.uuid == uuid)
            .fetchOne(db)?
            .id
    }

    /// Update the playlistUpdateDate for a specific playlist to the given date (defaults to now)
    func updatePlaylistUpdateDate(for playlist: EpisodeFilter, to date: Date, dbQueue: GRDBQueue) {
        dbQueue.updateAll(
            EpisodeFilter.self,
            filter: EpisodeFilter.Columns.uuid == playlist.uuid,
            EpisodeFilter.Columns.playlistUpdateDate.set(to: date.timeIntervalSince1970)
        )
    }

    func delete(playlist: EpisodeFilter, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try delete(playlist: playlist, db: db)
        }
    }

    func delete(playlist: EpisodeFilter, db: Database) throws {
        try EpisodeFilter.filter(EpisodeFilter.Columns.uuid == playlist.uuid).deleteAll(db)
        try Table(DataManager.playlistEpisodeTableName)
            .filter(Column("playlist_uuid") == playlist.uuid || Column("playlist_id") == playlist.id)
            .deleteAll(db)
    }

    func markAllSynced(dbQueue: GRDBQueue) {
        dbQueue.updateAll(
            EpisodeFilter.self,
            filter: EpisodeFilter.Columns.syncStatus == SyncStatus.notSynced.rawValue,
            EpisodeFilter.Columns.syncStatus.set(to: SyncStatus.synced.rawValue)
        )
    }

    func markAllUnsynced(dbQueue: GRDBQueue) {
        dbQueue.updateAll(
            EpisodeFilter.self,
            filter: EpisodeFilter.Columns.syncStatus == SyncStatus.synced.rawValue,
            EpisodeFilter.Columns.syncStatus.set(to: SyncStatus.notSynced.rawValue)
        )
    }

    private func allPlaylists(query: String, values: [Any]?, dbQueue: GRDBQueue) -> [EpisodeFilter] {
        var allPlaylists = [EpisodeFilter]()
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery(query, values: values) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - caller-supplied-SQL API plumbing for query-builder episode fetches
                defer { resultSet.close() }

                while resultSet.next() {
                    let filter = self.createPlaylistFrom(resultSet: resultSet)
                    allPlaylists.append(filter)
                }
            } catch {
                FileLog.shared.addMessage("PlaylistDataManager.allPlaylists error: \(error)")
            }
        }
        return allPlaylists
    }

    func nextSortPositionForPlaylist(dbQueue: GRDBQueue) -> Int {
        let highest = dbQueue.read { (db: Database) -> Int? in
            try Int.fetchOne(db, EpisodeFilter.select(max(EpisodeFilter.Columns.sortPosition)))
        }
        return (highest.flatMap { $0 } ?? 0) + 1
    }

    func firstSortPositionForPlaylist(dbQueue: GRDBQueue) -> Int {
        let lowest = dbQueue.read { (db: Database) -> Int? in
            try Int.fetchOne(db, EpisodeFilter.select(min(EpisodeFilter.Columns.sortPosition)))
        }
        return lowest.flatMap { $0 } ?? 0
    }

    func bumpSortPositionForAllPlaylists(adding value: Int, dbQueue: GRDBQueue) {
        dbQueue.updateAll(
            EpisodeFilter.self,
            filter: EpisodeFilter.Columns.wasDeleted == false,
            EpisodeFilter.Columns.sortPosition.set(to: EpisodeFilter.Columns.sortPosition + value),
            EpisodeFilter.Columns.syncStatus.set(to: SyncStatus.notSynced.rawValue)
        )
    }

    /// Returns a value indicating whether the episodes were added. If `false`, the playlist is full.
    func add(episodes: [Episode], to playlist: EpisodeFilter, dbQueue: GRDBQueue) -> Bool {
        var playlist = playlist
        // If the episodes are empty or already larger than our max size, bail
        if episodes.isEmpty || episodes.count > EpisodeDataManager.Constants.Limits.maxPlaylistItems {
            return false
        }

        // Ensure the filter exists and has a valid id before inserting playlist items. Capture the
        // saved value: as a value-type, `playlist` here keeps id == 0 otherwise (see save()).
        if playlist.id == 0 {
            playlist = save(playlist: playlist, dbQueue: dbQueue)
        }

        // Check that the current episode count + new episodes wouldn't overflow, otherwise bail.
        // Callers should generally
        let playlistCount = playlistEpisodeCount(clause: .allEpisodeCount, playlist: playlist, episodeUuidToAdd: nil, shouldShowArchived: true, dbQueue: dbQueue)
        let isFull = playlistCount + episodes.count > EpisodeDataManager.Constants.Limits.maxPlaylistItems

        if isFull { return false }

        let playlistUuid = playlist.uuid
        let playlistId = playlist.id

        dbQueue.write { db in
            // Find current max position for this playlist (by playlist_uuid)
            let startPosition = try Int32.fetchOne(
                db,
                Table(DataManager.playlistEpisodeTableName)
                    .filter(Column("playlist_uuid") == playlistUuid)
                    .select([max(Column("episodePosition"))], as: Int32.self)
            ) ?? 0

            var nextPosition = startPosition

            // Insert each episode, avoiding duplicates for this playlist
            for episode in episodes {
                // Ensure uniqueness within this playlist
                try Table(DataManager.playlistEpisodeTableName)
                    .filter(Column("playlist_uuid") == playlistUuid)
                    .filter(Column("episodeUuid") == episode.uuid)
                    .deleteAll(db)

                nextPosition += 1
                try ManualPlaylistEpisodeRow(
                    id: DBUtils.generateUniqueId(),
                    episodePosition: nextPosition,
                    episodeUuid: episode.uuid,
                    playlistId: playlistId,
                    title: episode.displayableTitle(),
                    podcastUuid: episode.podcastUuid,
                    playlistUuid: playlistUuid
                ).insert(db)
            }
        }

        return true
    }

    // MARK: - Conversion

    private func createPlaylistFrom(resultSet rs: PCDBResultSet) -> EpisodeFilter {
        var playlist = EpisodeFilter()
        playlist.id = rs.longLongInt(forColumn: "id")
        playlist.autoDownloadEpisodes = rs.bool(forColumn: "autoDownloadEpisodes")
        playlist.customIcon = rs.int(forColumn: "customIcon")
        playlist.filterAllPodcasts = rs.bool(forColumn: "filterAllPodcasts")
        playlist.filterAudioVideoType = rs.int(forColumn: "filterAudioVideoType")
        playlist.filterDownloaded = rs.bool(forColumn: "filterDownloaded")
        playlist.filterFinished = rs.bool(forColumn: "filterFinished")
        playlist.filterNotDownloaded = rs.bool(forColumn: "filterNotDownloaded")
        playlist.filterPartiallyPlayed = rs.bool(forColumn: "filterPartiallyPlayed")
        playlist.filterStarred = rs.bool(forColumn: "filterStarred")
        playlist.filterUnplayed = rs.bool(forColumn: "filterUnplayed")
        playlist.filterHours = rs.int(forColumn: "filterHours")
        playlist.playlistName = DBUtils.nonNilStringFromColumn(resultSet: rs, columnName: "playlistName")
        playlist.sortPosition = rs.int(forColumn: "sortPosition")
        playlist.sortType = rs.int(forColumn: "sortType")
        playlist.uuid = DBUtils.nonNilStringFromColumn(resultSet: rs, columnName: "uuid")
        playlist.podcastUuids = DBUtils.nonNilStringFromColumn(resultSet: rs, columnName: "podcastUuids")
        playlist.autoDownloadLimit = rs.int(forColumn: "autoDownloadLimit")
        playlist.syncStatus = rs.int(forColumn: "syncStatus")
        playlist.wasDeleted = rs.bool(forColumn: "wasDeleted")
        playlist.filterDuration = rs.bool(forColumn: "filterDuration")
        playlist.longerThan = rs.int(forColumn: "longerThan")
        playlist.shorterThan = rs.int(forColumn: "shorterThan")
        playlist.manual = rs.bool(forColumn: "manual")
        playlist.showArchivedEpisodes = rs.bool(forColumn: "showArchivedEpisodes")
        playlist.playlistUpdateDate = DBUtils.convertDate(value: rs.double(forColumn: "playlistUpdateDate"))

        return playlist
    }
}
