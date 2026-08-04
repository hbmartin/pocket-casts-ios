import PocketCastsUtils
import Foundation
import GRDB

final class EpisodeDataManager: Sendable {
    /// Legacy column names for non-GRDB code path.
    let columnNames = [
        "id",
        "addedDate",
        "lastDownloadAttemptDate",
        "detailedDescription",
        "downloadErrorDetails",
        "downloadTaskId",
        "downloadUrl",
        "episodeDescription",
        "episodeStatus",
        "fileType",
        "contentType",
        "keepEpisode",
        "playedUpTo",
        "duration",
        "playingStatus",
        "autoDownloadStatus",
        "publishedDate",
        "sizeInBytes",
        "playingStatusModified",
        "playedUpToModified",
        "durationModified",
        "keepEpisodeModified",
        "title",
        "uuid",
        "podcastUuid",
        "playbackErrorDetails",
        "cachedFrameCount",
        "cachedLoudness",
        "lastPlaybackInteractionDate",
        "lastPlaybackInteractionSyncStatus",
        "podcast_id",
        "episodeNumber",
        "seasonNumber",
        "episodeType",
        "archived",
        "archivedModified",
        "lastArchiveInteractionDate",
        "excludeFromEpisodeLimit",
        "starredModified",
        "deselectedChapters",
        "deselectedChaptersModified",
        "wasDeleted",
        "hasGeneratedTranscript"
    ]

    enum Constants {
        enum Limits {
            static let maxPlaylistItems = 1000
        }
    }

    // MARK: - Query

    func findBy(uuid: String, dbQueue: GRDBQueue) -> Episode? {
        return dbQueue.fetchOne(Episode.filter(Episode.Columns.uuid == uuid))
    }

    func findByAsync(uuid: String, dbQueue: GRDBQueue) async -> Episode? {
        do {
            return try await dbQueue.dbPool.read { db in
                try Episode.filter(Episode.Columns.uuid == uuid).fetchOne(db)
            }
        } catch {
            FileLog.shared.addMessage("EpisodeDataManager.findByAsync error: \(error)")
            return nil
        }
    }

    func findWhere(customWhere: String, arguments: [Any]?, dbQueue: GRDBQueue) -> Episode? {
        loadSingle(query: "SELECT * from \(DataManager.episodeTableName) WHERE \(customWhere)", values: arguments, dbQueue: dbQueue)
    }

    func findPlayedEpisodes(uuids: [String], dbQueue: GRDBQueue) -> [String] {
        return dbQueue.read { (db: Database) -> [String] in
            try Episode
                .filter(uuids.contains(Episode.Columns.uuid))
                .filter(Episode.Columns.playingStatus == PlayingStatus.completed.rawValue)
                .limit(uuids.count)
                .select(Episode.Columns.uuid, as: String.self)
                .fetchAll(db)
        } ?? []
    }

    func findMatchingEpisodes(uuids: [String], dbQueue: GRDBQueue) -> [String] {
        return dbQueue.read { (db: Database) -> [String] in
            try Episode
                .filter(uuids.contains(Episode.Columns.uuid))
                .limit(uuids.count)
                .select(Episode.Columns.uuid, as: String.self)
                .fetchAll(db)
        } ?? []
    }

    func findPlayedEpisodesCount(podcastId: Int64, dbQueue: GRDBQueue) async -> Int {
        // Uses the genuinely-async `read` (off the caller's executor) rather than the
        // synchronous `read` wrapped in a continuation, which would block whatever thread
        // the caller runs on — main-thread-blocking when awaited from a `@MainActor` caller.
        do {
            return try await dbQueue.dbPool.read { db in
                try Episode
                    .filter(Episode.Columns.podcast_id == podcastId)
                    .filter(Episode.Columns.playedUpTo > Episode.Columns.duration / 2)
                    .fetchCount(db)
            }
        } catch {
            FileLog.shared.addMessage("EpisodeDataManager.findPlayedEpisodesCount error: \(error)")
            return 0
        }
    }

    func downloadedEpisodeExists(uuid: String, dbQueue: GRDBQueue) -> Bool {
        return dbQueue.count(
            Episode.self,
            filter: Episode.Columns.episodeStatus == DownloadStatus.downloaded.rawValue && Episode.Columns.uuid == uuid
        ) > 0
    }

    func findBy(downloadTaskId: String, dbQueue: GRDBQueue) -> Episode? {
        return dbQueue.fetchOne(Episode.filter(Episode.Columns.downloadTaskId == downloadTaskId))
    }

    func findWhereNotNull(columnName: String, dbQueue: GRDBQueue) -> [Episode] {
        return dbQueue.fetchAll(Episode.filter(Column(columnName) != nil))
    }

    /// SQLite's UPPER() only folds ASCII letters; the GRDB search paths must uppercase bound
    /// terms the same way to keep LIKE matching identical to the legacy `UPPER(?)` binding.
    private static func sqliteUppercased(_ term: String) -> String {
        String(term.map { $0.isASCII ? Character($0.uppercased()) : $0 })
    }

    func findEpisodesAndPodcastsWhere(customWhere: String, listenedTo: Bool, dbQueue: GRDBQueue) -> [Episode] {
        return dbQueue.read { (db: Database) -> [Episode] in
            // Two-step equivalent of the legacy LEFT JOIN: matching podcast ids first, then
            // episodes whose own title matches or whose podcast matched
            let pattern = "%\(Self.sqliteUppercased(customWhere))%"
            let matchingPodcastIds = try Podcast
                .filter(Podcast.Columns.title.uppercased.like(pattern, escape: "\\"))
                .select(Podcast.Columns.id, as: Int64.self)
                .fetchAll(db)

            var request = Episode.filter(
                Episode.Columns.title.uppercased.like(pattern, escape: "\\")
                    || matchingPodcastIds.contains(Episode.Columns.podcast_id)
            )
            if listenedTo {
                request = request
                    .filter(Episode.Columns.lastPlaybackInteractionDate != nil)
                    .filter(Episode.Columns.lastPlaybackInteractionDate > 0)
            }
            return try request
                .order(Episode.Columns.lastPlaybackInteractionDate.desc)
                .limit(1000)
                .fetchAll(db)
        } ?? []
    }

    func findEpisodesWhere(customWhere: String, arguments: [Any]?, dbQueue: GRDBQueue) -> [Episode] {
        loadMultiple(query: "SELECT * from \(DataManager.episodeTableName) WHERE \(customWhere)", values: arguments, dbQueue: dbQueue)
    }

    func findEpisodes(with term: String, podcastUUID: String, dbQueue: GRDBQueue) -> [Episode] {
        let escapedSearch = term.escapeLike(escapeChar: "\\")

        return dbQueue.fetchAll(
            Episode
                .filter(Episode.Columns.title.uppercased.like("%\(Self.sqliteUppercased(escapedSearch))%", escape: "\\"))
                .filter(Episode.Columns.podcastUuid == podcastUUID)
                .filter(Episode.Columns.wasDeleted == false)
                .order(Episode.Columns.publishedDate.desc, Episode.Columns.addedDate.desc)
        )
    }

    func findPlaylistEpisodesWhere(query: String, arguments: [Any]?, dbQueue: GRDBQueue) -> [Episode] {
        loadMultiple(query: query, values: arguments, dbQueue: dbQueue)
    }

    func unsyncedEpisodes(limit: Int, dbQueue: GRDBQueue) -> [Episode] {
        dbQueue.fetchAll(
            Episode
                .filter(
                    Episode.Columns.playingStatusModified > 0
                        || Episode.Columns.playedUpToModified > 0
                        || Episode.Columns.durationModified > 0
                        || Episode.Columns.keepEpisodeModified > 0
                        || Episode.Columns.archivedModified > 0
                )
                .order(Episode.Columns.publishedDate.desc, Episode.Columns.addedDate.desc)
                .limit(limit)
        )
    }

    func allEpisodesForPodcast(id: Int64, dbQueue: GRDBQueue) -> [Episode] {
        return dbQueue.fetchAll(
            Episode
                .filter(Episode.Columns.podcast_id == id)
                .filter(Episode.Columns.wasDeleted == false)
        )
    }

    func episodesWithListenHistory(limit: Int, dbQueue: GRDBQueue) -> [Episode] {
        return dbQueue.fetchAll(
            Episode
                .filter(Episode.Columns.lastPlaybackInteractionDate != nil)
                .filter(Episode.Columns.lastPlaybackInteractionDate > 0)
                .order(Episode.Columns.lastPlaybackInteractionDate.desc)
                .limit(limit)
        )
    }

    /// Returns daily listening totals as `[dateString: totalSeconds]` for the past N days.
    /// Date strings are formatted as "yyyy-MM-dd" in the device's local timezone.
    func dailyListeningTime(forLast days: Int, dbQueue: GRDBQueue) -> [String: Double] {
        // strftime('%s','now','-N days') subtracts exact days from UTC epoch seconds, i.e.
        // now - N*86400; the per-day bucketing replicates date(x,'unixepoch','localtime')
        let cutoff = Date().timeIntervalSince1970 - Double(days) * 86400
        let rows = dbQueue.read { (db: Database) -> [Row] in
            try Row.fetchAll(
                db,
                Episode
                    .filter(Episode.Columns.lastPlaybackInteractionDate != nil)
                    .filter(Episode.Columns.lastPlaybackInteractionDate >= cutoff)
                    .select([Episode.Columns.lastPlaybackInteractionDate, Episode.Columns.playedUpTo])
                    .asRequest(of: Row.self)
            )
        } ?? []

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        var result: [String: Double] = [:]
        for row in rows {
            guard let interval: Double = row["lastPlaybackInteractionDate"] else { continue }
            let day = formatter.string(from: Date(timeIntervalSince1970: interval))
            let playedUpTo: Double = row["playedUpTo"] ?? 0
            result[day, default: 0] += playedUpTo
        }
        return result
    }

    func findLatestEpisode(podcast: Podcast, dbQueue: GRDBQueue) -> Episode? {
        return dbQueue.fetchOne(latestEpisodesRequest(podcastId: podcast.id).limit(1))
    }

    func findLatestEpisodes(podcast: Podcast, limit: Int, dbQueue: GRDBQueue) -> [Episode] {
        return dbQueue.fetchAll(latestEpisodesRequest(podcastId: podcast.id).limit(limit))
    }

    private func latestEpisodesRequest(podcastId: Int64) -> QueryInterfaceRequest<Episode> {
        Episode
            .filter(Episode.Columns.podcast_id == podcastId)
            .filter(Episode.Columns.wasDeleted == false)
            .order(Episode.Columns.publishedDate.desc, Episode.Columns.addedDate.desc)
    }

    func allUpNextEpisodes(dbQueue: GRDBQueue) -> [Episode] {
        return dbQueue.read { (db: Database) -> [Episode] in
            // Two-step equivalent of the legacy INNER JOIN, ordered by queue position
            let queueRows = try Table(DataManager.playlistEpisodeTableName)
                .filter(Column("playlist_id") == UpNextDataManager.upNextPlaylistId)
                .order(Column("episodePosition").asc)
                .fetchAll(db)
            let uuids = queueRows.map { $0["episodeUuid"] as String }

            let episodes = try Episode.filter(uuids.contains(Episode.Columns.uuid)).fetchAll(db)
            let episodesByUuid = Dictionary(episodes.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })

            return uuids.compactMap { episodesByUuid[$0] }
        } ?? []
    }

    func allUpNextEpisodes(from uuids: [String], dbQueue: GRDBQueue) -> [Episode] {
        return dbQueue.read { (db: Database) -> [Episode] in
            // Two-step equivalent of the legacy DISTINCT INNER JOIN: queue order, first
            // occurrence wins, only uuids present in both the queue and the episode table
            let queueRows = try Table(DataManager.playlistEpisodeTableName)
                .filter(uuids.contains(Column("episodeUuid")))
                .order(Column("episodePosition").asc)
                .fetchAll(db)

            let episodes = try Episode.filter(uuids.contains(Episode.Columns.uuid)).fetchAll(db)
            let episodesByUuid = Dictionary(episodes.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })

            var seen = Set<String>()
            var results = [Episode]()
            for row in queueRows {
                let uuid: String = row["episodeUuid"]
                guard !seen.contains(uuid), let episode = episodesByUuid[uuid] else { continue }
                seen.insert(uuid)
                results.append(episode)
            }
            return results
        } ?? []
    }

    private func loadSingle(query: String, values: [Any]?, dbQueue: GRDBQueue) -> Episode? {
        var episode: Episode?
        dbQueue.read { db in
            do {
                episode = try self.loadSingle(query: query, values: values, db: db)
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.loadSingle error: \(error)")
            }
        }

        return episode
    }

    private func loadSingle(query: String, values: [Any]?, db: PCDatabase) throws -> Episode? {
        let resultSet = try db.executeQuery(query, values: values) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - caller-supplied-SQL API plumbing (findWhere/findEpisodesWhere)
        defer { resultSet.close() }

        return resultSet.next() ? createEpisodeFrom(resultSet: resultSet) : nil
    }

    private func loadMultiple(query: String, values: [Any]?, dbQueue: GRDBQueue) -> [Episode] {
        var episodes = [Episode]()
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery(query, values: values) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - caller-supplied-SQL API plumbing (findWhere/findEpisodesWhere)
                defer { resultSet.close() }

                while resultSet.next() {
                    if let episode = self.createEpisodeFrom(resultSet: resultSet) {
                        episodes.append(episode)
                    }
                }
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.loadMultiple Episode error: \(error)")
            }
        }

        return episodes
    }

    func downloadedEpisodeCount(dbQueue: GRDBQueue) -> Int {
        return dbQueue.count(Episode.self, filter: Episode.Columns.episodeStatus == DownloadStatus.downloaded.rawValue)
    }

    func failedDownloadEpisodeCount(dbQueue: GRDBQueue) -> Int {
        return dbQueue.count(Episode.self, filter: Episode.Columns.episodeStatus == DownloadStatus.downloadFailed.rawValue)
    }

    func failedDownloadFirstDate(dbQueue: GRDBQueue, sortOrder: SortOrder) -> Date? {
        var request = Episode
            .filter(Episode.Columns.episodeStatus == DownloadStatus.downloadFailed.rawValue)
            .filter(Episode.Columns.lastDownloadAttemptDate != nil)
        request = sortOrder == .forward
            ? request.order(Episode.Columns.lastDownloadAttemptDate.desc)
            : request.order(Episode.Columns.lastDownloadAttemptDate.asc)
        return dbQueue.fetchOne(request)?.lastDownloadAttemptDate
    }


    // MARK: - Updates

    func saveIfNotModified(starred: Bool, episodeUuid: String, dbQueue: GRDBQueue) -> Bool {
        if !starred {
            saveEpisode(starredModified: 0, episodeUuid: episodeUuid, dbQueue: dbQueue)
        }
        return saveFieldIfNotModified(fieldName: "keepEpisode", modifiedFieldName: "keepEpisodeModified", value: starred, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveIfNotModified(archived: Bool, episodeUuid: String, dbQueue: GRDBQueue) -> Bool {
        saveFieldIfNotModified(fieldName: "archived", modifiedFieldName: "archivedModified", value: archived, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveIfNotModified(playingStatus: PlayingStatus, episodeUuid: String, dbQueue: GRDBQueue) -> Bool {
        saveFieldIfNotModified(fieldName: "playingStatus", modifiedFieldName: "playingStatusModified", value: playingStatus.rawValue, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveIfNotModified(chapters: String, remoteModified: Int64, episodeUuid: String, dbQueue: GRDBQueue) -> Bool {
        saveFieldIfNotModified(fieldName: "deselectedChapters", modifiedFieldName: "deselectedChaptersModified", value: chapters, remoteModified: remoteModified, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    /// Value-type Episode: returns the saved copy carrying the generated row id.
    @discardableResult
    func save(episode: Episode, dbQueue: GRDBQueue) -> Episode {
        var episode = episode
        let isInsert = episode.id == 0
        if isInsert {
            episode.id = DBUtils.generateUniqueId()
        }

        do {
            try dbQueue.dbPool.write { db in
                try episode.save(db)
            }
        } catch {
            FileLog.shared.addMessage("EpisodeDataManager.save Episode error: \(error)")
        }
        return episode
    }

    func bulkSave(episodes: [Episode], dbQueue: GRDBQueue) {
        do {
            try dbQueue.dbPool.write { db in
                for episode in episodes {
                    var episode = episode
                    if episode.id == 0 {
                        episode.id = DBUtils.generateUniqueId()
                    }
                    try episode.save(db)
                }
            }
        } catch {
            FileLog.shared.addMessage("EpisodeDataManager.bulkSave error: \(error)")
        }
    }

    /// Applies one `(fields, values)` update per episode uuid inside a single transaction on
    /// either path — the shared execution for the bulk mutation methods below.
    private func performBulkUpdates(_ updates: [(fields: [String], values: [Any], uuid: String)], methodName: String, dbQueue: GRDBQueue) {
        if updates.isEmpty { return }

        dbQueue.write { db in
            for update in updates {
                let assignments = zip(update.fields, update.values).map { field, value in
                    Column(field).set(to: Self.databaseValue(from: value))
                }
                try Episode.filter(Episode.Columns.uuid == update.uuid).updateAll(db, assignments)
            }
        }
    }

    func bulkSetStarred(starred: Bool, episodes: [Episode], updateSyncFlag: Bool, dbQueue: GRDBQueue) {
        if episodes.isEmpty { return }

        var updates = [(fields: [String], values: [Any], uuid: String)]()
        let firstModified = DBUtils.currentUTCTimeInMillis() + Int64(episodes.count) - 1
        for (index, episode) in episodes.enumerated() {
            if episode.keepEpisode == starred { continue }

            var fields = ["keepEpisode"]
            var values: [Any] = [starred]
            if updateSyncFlag {
                fields.append("keepEpisodeModified")
                values.append(firstModified - Int64(index))
            }

            let starredModifiedValue = starred ? (firstModified - Int64(index)) : 0
            fields.append("starredModified")
            values.append(starredModifiedValue)

            updates.append((fields, values, episode.uuid))
        }

        performBulkUpdates(updates, methodName: "bulkSetStarred", dbQueue: dbQueue)
    }

    func bulkUserFileDelete(episodes: [Episode], dbQueue: GRDBQueue) {
        if episodes.isEmpty { return }

        let updates = episodes.map { episode -> (fields: [String], values: [Any], uuid: String) in
            (
                fields: ["episodeStatus", "autoDownloadStatus", "cachedFrameCount", "cachedLoudness"],
                values: [DownloadStatus.notDownloaded.rawValue, AutoDownloadStatus.userDeletedFile.rawValue, 0, 0],
                uuid: episode.uuid
            )
        }

        performBulkUpdates(updates, methodName: "bulkUserFileDelete", dbQueue: dbQueue)
    }

    func saveFileType(episode: Episode, fileType: String, dbQueue: GRDBQueue) {
        var episode = episode
        episode.fileType = fileType
        save(fieldName: "fileType", value: fileType, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveContentType(episode: Episode, contentType: String, dbQueue: GRDBQueue) {
        var episode = episode
        episode.contentType = contentType
        save(fieldName: "contentType", value: contentType, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveFileSize(episode: Episode, fileSize: Int64, dbQueue: GRDBQueue) {
        var episode = episode
        episode.sizeInBytes = fileSize
        save(fieldName: "sizeInBytes", value: fileSize, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveBulkEpisodeSyncInfo(episodes: [EpisodeBasicData], dbQueue: GRDBQueue) {
        if episodes.isEmpty { return }

        var updates = [(fields: [String], values: [Any], uuid: String)]()
        for episode in episodes {
            guard let uuid = episode.uuid else { continue }

            var fields = [String]()
            var values = [Any]()
            if let duration = episode.duration, duration > 0 {
                fields.append("duration")
                values.append(duration)
            }

            if let playingStatus = episode.playingStatus {
                let actualStatus = PlayingStatus(rawValue: Int32(playingStatus))?.rawValue ?? PlayingStatus.notPlayed.rawValue
                fields.append("playingStatus")
                values.append(actualStatus)
            }

            if let playedUpTo = episode.playedUpTo, playedUpTo > 0 {
                fields.append("playedUpTo")
                values.append(playedUpTo)
            }
            if let isArchived = episode.isArchived {
                fields.append("archived")
                values.append(isArchived)

                fields.append("lastArchiveInteractionDate")
                values.append(Date())
            }
            if let starred = episode.starred {
                fields.append("keepEpisode")
                values.append(starred)
            }
            if let deselectedChapters = episode.deselectedChapters {
                fields.append("deselectedChapters")
                values.append(deselectedChapters)
            }

            updates.append((fields, values, uuid))
        }

        performBulkUpdates(updates, methodName: "saveBulkEpisodeSyncInfo", dbQueue: dbQueue)
    }

    func saveFrameCount(episodeId: Int64, frameCount: Int64, dbQueue: GRDBQueue) {
        save(fieldName: "cachedFrameCount", value: frameCount, episodeId: episodeId, dbQueue: dbQueue)
    }

    func findFrameCount(episodeId: Int64, dbQueue: GRDBQueue) -> Int64 {
        return dbQueue.fetchOne(Episode.filter(Episode.Columns.id == episodeId))?.cachedFrameCount ?? 0
    }

    func saveLoudness(episodeId: Int64, loudness: Double, dbQueue: GRDBQueue) {
        save(fieldName: "cachedLoudness", value: loudness, episodeId: episodeId, dbQueue: dbQueue)
    }

    func findLoudness(episodeId: Int64, dbQueue: GRDBQueue) -> Double {
        return dbQueue.fetchOne(Episode.filter(Episode.Columns.id == episodeId))?.cachedLoudness ?? 0
    }

    /// Zeroes both cached audio measurements (frame count + loudness); call when
    /// the local file changes so stale values never seed the player.
    func clearCachedAudioMetadata(episodeId: Int64, dbQueue: GRDBQueue) {
        save(fieldName: "cachedFrameCount", value: 0, episodeId: episodeId, dbQueue: dbQueue)
        save(fieldName: "cachedLoudness", value: 0, episodeId: episodeId, dbQueue: dbQueue)
    }

    func saveEpisode(playbackError: String?, episode: Episode, dbQueue: GRDBQueue) {
        var episode = episode
        episode.playbackErrorDetails = playbackError
        save(fieldName: "playbackErrorDetails", value: DBUtils.replaceNilWithNull(value: episode.playbackErrorDetails), episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveEpisode(playedUpTo: Double, episode: Episode, updateSyncFlag: Bool, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try saveEpisode(playedUpTo: playedUpTo, episode: episode, updateSyncFlag: updateSyncFlag, db: db)
        }
    }

    func saveEpisode(playedUpTo: Double, episode: Episode, updateSyncFlag: Bool, db: Database) throws {
        var episode = episode
        episode.playedUpTo = playedUpTo
        var fields = ["playedUpTo"]
        var values = [episode.playedUpTo] as [Any]

        if updateSyncFlag {
            episode.playedUpToModified = DBUtils.currentUTCTimeInMillis()
            fields.append("playedUpToModified")
            values.append(episode.playedUpToModified)
        }
        values.append(episode.id)

        try save(fields: fields, values: values, db: db)
    }

    func updateEpisodePlaybackInteractionDate(episode: Episode, dbQueue: GRDBQueue) {
        var episode = episode
        let now = Date()
        let syncStatus = SyncStatus.notSynced.rawValue
        episode.lastPlaybackInteractionDate = now
        episode.lastPlaybackInteractionSyncStatus = syncStatus
        let fields = ["lastPlaybackInteractionDate", "lastPlaybackInteractionSyncStatus"]
        let values = [now, syncStatus, episode.id] as [Any]
        FileLog.shared.console("[Episode Save] Episode id \(episode.id) - title: \(episode.title ?? "no title")")
        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func clearEpisodePlaybackInteractionDate(episodeUuid: String, dbQueue: GRDBQueue) {
        save(fieldName: "lastPlaybackInteractionDate", value: NSNull(), episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func setEpisodePlaybackInteractionDate(interactionDate: Date, episodeUuid: String, dbQueue: GRDBQueue) {
        save(fieldName: "lastPlaybackInteractionDate", value: interactionDate, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func markAllEpisodePlaybackHistorySynced(dbQueue: GRDBQueue) {
        _ = dbQueue.write { db in
            try Episode.updateAll(db, Episode.Columns.lastPlaybackInteractionSyncStatus.set(to: SyncStatus.synced.rawValue))
        }
    }

    func clearEpisodePlaybackInteractionDatesBefore(date: Date, dbQueue: GRDBQueue) {
        dbQueue.updateAll(
            Episode.self,
            filter: Episode.Columns.lastPlaybackInteractionDate <= date.timeIntervalSince1970,
            Episode.Columns.lastPlaybackInteractionDate.set(to: nil as Double?)
        )
    }

    func clearAllEpisodePlaybackInteractions(dbQueue: GRDBQueue) {
        dbQueue.updateAll(
            Episode.self,
            filter: Episode.Columns.lastPlaybackInteractionDate > 0,
            Episode.Columns.lastPlaybackInteractionDate.set(to: nil as Double?)
        )
    }

    func saveEpisode(playingStatus: PlayingStatus, episode: Episode, updateSyncFlag: Bool, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try saveEpisode(playingStatus: playingStatus, episode: episode, updateSyncFlag: updateSyncFlag, db: db)
        }
    }

    func saveEpisode(playingStatus: PlayingStatus, episode: Episode, updateSyncFlag: Bool, db: Database) throws {
        var episode = episode
        episode.playingStatus = playingStatus.rawValue
        var fields = ["playingStatus"]
        var values = [episode.playingStatus] as [Any]

        if updateSyncFlag {
            episode.playingStatusModified = DBUtils.currentUTCTimeInMillis()
            fields.append("playingStatusModified")
            values.append(episode.playingStatusModified)
        }
        values.append(episode.id)

        try save(fields: fields, values: values, db: db)
    }

    func saveEpisode(archived: Bool, episode: Episode, updateSyncFlag: Bool, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try saveEpisode(archived: archived, episode: episode, updateSyncFlag: updateSyncFlag, db: db)
        }
    }

    func saveEpisode(archived: Bool, episode: Episode, updateSyncFlag: Bool, db: Database) throws {
        var episode = episode
        let now = Date()
        episode.archived = archived
        episode.lastArchiveInteractionDate = now
        var fields = ["archived", "lastArchiveInteractionDate"]
        var values = [episode.archived, now] as [Any]

        if updateSyncFlag {
            episode.archivedModified = DBUtils.currentUTCTimeInMillis()
            fields.append("archivedModified")
            values.append(episode.archivedModified)
        }
        values.append(episode.id)

        try save(fields: fields, values: values, db: db)
    }

    func saveEpisode(excludeFromEpisodeLimit: Bool, episode: Episode, dbQueue: GRDBQueue) {
        var episode = episode
        episode.excludeFromEpisodeLimit = excludeFromEpisodeLimit
        save(fieldName: "excludeFromEpisodeLimit", value: episode.excludeFromEpisodeLimit, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveEpisode(duration: Double, episode: Episode, updateSyncFlag: Bool, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try saveEpisode(duration: duration, episode: episode, updateSyncFlag: updateSyncFlag, db: db)
        }
    }

    func saveEpisode(duration: Double, episode: Episode, updateSyncFlag: Bool, db: Database) throws {
        var episode = episode
        episode.duration = duration
        var fields = ["duration"]
        var values = [episode.duration] as [Any]

        if updateSyncFlag {
            episode.durationModified = DBUtils.currentUTCTimeInMillis()
            fields.append("durationModified")
            values.append(episode.durationModified)
        }
        values.append(episode.id)

        try save(fields: fields, values: values, db: db)
    }

    func saveEpisode(starred: Bool, starredModified: Int64?, episode: Episode, updateSyncFlag: Bool, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try saveEpisode(starred: starred, starredModified: starredModified, episode: episode, updateSyncFlag: updateSyncFlag, db: db)
        }
    }

    func saveEpisode(starred: Bool, starredModified: Int64?, episode: Episode, updateSyncFlag: Bool, db: Database) throws {
        var episode = episode
        episode.keepEpisode = starred
        var fields = ["keepEpisode"]
        var values = [episode.keepEpisode] as [Any]

        fields.append("starredModified")
        if let starredModified {
            values.append(starredModified)
        } else {
            let starredModifiedValue = starred ? DBUtils.currentUTCTimeInMillis() : 0
            values.append(starredModifiedValue)
        }

        if updateSyncFlag {
            episode.keepEpisodeModified = DBUtils.currentUTCTimeInMillis()
            fields.append("keepEpisodeModified")
            values.append(episode.keepEpisodeModified)
        }
        values.append(episode.id)

        try save(fields: fields, values: values, db: db)
    }

    func saveEpisode(downloadStatus: DownloadStatus, episode: Episode, dbQueue: GRDBQueue) {
        var episode = episode
        episode.episodeStatus = downloadStatus.rawValue
        save(fieldName: "episodeStatus", value: episode.episodeStatus, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, lastDownloadAttemptDate: Date, autoDownloadStatus: AutoDownloadStatus, episode: Episode, dbQueue: GRDBQueue) {
        var episode = episode
        episode.episodeStatus = downloadStatus.rawValue
        episode.lastDownloadAttemptDate = lastDownloadAttemptDate
        episode.autoDownloadStatus = autoDownloadStatus.rawValue

        let fields = ["episodeStatus", "lastDownloadAttemptDate", "autoDownloadStatus"]
        let values = [episode.episodeStatus, DBUtils.replaceNilWithNull(value: episode.lastDownloadAttemptDate), episode.autoDownloadStatus, episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(autoDownloadStatus: AutoDownloadStatus, episode: Episode, dbQueue: GRDBQueue) {
        var episode = episode
        episode.autoDownloadStatus = autoDownloadStatus.rawValue
        save(fieldName: "autoDownloadStatus", value: episode.autoDownloadStatus, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, downloadError: String?, downloadTaskId: String?, episode: Episode, dbQueue: GRDBQueue) {
        var episode = episode
        episode.episodeStatus = downloadStatus.rawValue
        episode.downloadErrorDetails = downloadError
        episode.downloadTaskId = downloadTaskId

        let fields = ["episodeStatus", "downloadErrorDetails", "downloadTaskId"]
        let values = [episode.episodeStatus, DBUtils.replaceNilWithNull(value: episode.downloadErrorDetails), DBUtils.replaceNilWithNull(value: episode.downloadTaskId), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, downloadTaskId: String?, episode: Episode, dbQueue: GRDBQueue) {
        var episode = episode
        episode.episodeStatus = downloadStatus.rawValue
        episode.downloadTaskId = downloadTaskId

        let fields = ["episodeStatus", "downloadTaskId"]
        let values = [episode.episodeStatus, DBUtils.replaceNilWithNull(value: episode.downloadTaskId), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, sizeInBytes: Int64, downloadTaskId: String?, episode: Episode, dbQueue: GRDBQueue) {
        var episode = episode
        episode.episodeStatus = downloadStatus.rawValue
        episode.sizeInBytes = sizeInBytes
        episode.downloadTaskId = downloadTaskId

        let fields = ["episodeStatus", "sizeInBytes", "downloadTaskId"]
        let values = [episode.episodeStatus, episode.sizeInBytes, DBUtils.replaceNilWithNull(value: episode.downloadTaskId), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(downloadUrl: String, episodeUuid: String, dbQueue: GRDBQueue) {
        save(fieldName: "downloadUrl", value: downloadUrl, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveEpisode(starredModified: Int64, episodeUuid: String, dbQueue: GRDBQueue) {
        save(fieldName: "starredModified", value: starredModified, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func clearKeepEpisodeModified(episode: Episode, dbQueue: GRDBQueue) {
        let fields = ["keepEpisodeModified"]
        var values = [episode.keepEpisodeModified] as [Any]
        values.append(episode.id)

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func clearDownloadTaskId(episode: Episode, dbQueue: GRDBQueue) {
        save(fieldName: "downloadTaskId", value: NSNull(), episodeId: episode.id, dbQueue: dbQueue)
    }

    func delete(episodeUuid: String, dbQueue: GRDBQueue) {
        dbQueue.deleteAll(Episode.self, filter: Episode.Columns.uuid == episodeUuid)
    }

    func deleteAllEpisodesInPodcast(podcastId: Int64, dbQueue: GRDBQueue) {
        dbQueue.deleteAll(Episode.self, filter: Episode.Columns.podcast_id == podcastId)
    }

    func markAllSynced(episodes: [Episode], dbQueue: GRDBQueue) {
        if episodes.isEmpty {
            return
        }

        // Single IN-statement form; equivalent to both legacy sub-branches
        let ids = episodes.map(\.id)
        dbQueue.updateAll(
            Episode.self,
            filter: ids.contains(Episode.Columns.id),
            Episode.Columns.playingStatusModified.set(to: 0),
            Episode.Columns.playedUpToModified.set(to: 0),
            Episode.Columns.durationModified.set(to: 0),
            Episode.Columns.keepEpisodeModified.set(to: 0),
            Episode.Columns.archivedModified.set(to: 0)
        )
    }

    func markAllSynced(episodeIDs ids: [String], dbQueue: GRDBQueue) {
        if ids.isEmpty {
            return
        }

        // Single IN-statement form; equivalent to both legacy sub-branches
        dbQueue.updateAll(
            Episode.self,
            filter: ids.contains(Episode.Columns.uuid),
            Episode.Columns.playingStatusModified.set(to: 0),
            Episode.Columns.playedUpToModified.set(to: 0),
            Episode.Columns.durationModified.set(to: 0),
            Episode.Columns.keepEpisodeModified.set(to: 0),
            Episode.Columns.archivedModified.set(to: 0)
        )
    }

    func markAllUnarchivedForPodcast(id: Int64, dbQueue: GRDBQueue) {
        dbQueue.updateAll(
            Episode.self,
            filter: Episode.Columns.podcast_id == id,
            Episode.Columns.archived.set(to: false)
        )
    }

    func bulkMarkAsPlayed(episodes: [Episode], updateSyncFlag: Bool, dbQueue: GRDBQueue) {
        if episodes.isEmpty { return }

        var updates = [(fields: [String], values: [Any], uuid: String)]()
        for episode in episodes {
            if episode.playingStatus == PlayingStatus.completed.rawValue { continue }

            var fields = ["playingStatus"]
            var values: [Any] = [PlayingStatus.completed.rawValue]

            if updateSyncFlag {
                fields.append("playingStatusModified")
                values.append(DBUtils.currentUTCTimeInMillis())
            }

            updates.append((fields, values, episode.uuid))
        }

        performBulkUpdates(updates, methodName: "bulkMarkAsPlayed", dbQueue: dbQueue)
    }

    func bulkMarkAsUnPlayed(episodes: [Episode], updateSyncFlag: Bool, dbQueue: GRDBQueue) {
        if episodes.isEmpty { return }

        var updates = [(fields: [String], values: [Any], uuid: String)]()
        for episode in episodes {
            if episode.playingStatus == PlayingStatus.notPlayed.rawValue { continue }

            var fields = ["playingStatus", "playedUpTo"]
            var values: [Any] = [PlayingStatus.notPlayed.rawValue, 0]

            if updateSyncFlag {
                fields.append("playingStatusModified")
                values.append(DBUtils.currentUTCTimeInMillis())
            }

            updates.append((fields, values, episode.uuid))
        }

        performBulkUpdates(updates, methodName: "bulkMarkAsUnPlayed", dbQueue: dbQueue)
    }

    func bulkArchive(episodes: [Episode], markAsNotDownloaded: Bool, markAsPlayed: Bool, updateSyncFlag: Bool, dbQueue: GRDBQueue) {
        if episodes.isEmpty { return }

        var updates = [(fields: [String], values: [Any], uuid: String)]()
        for episode in episodes {
            var fields = [String]()
            var values = [Any]()
            if !episode.archived {
                fields.append("archived")
                values.append(true)

                if updateSyncFlag {
                    fields.append("archivedModified")
                    values.append(DBUtils.currentUTCTimeInMillis())
                }
            }
            if markAsNotDownloaded, episode.episodeStatus != DownloadStatus.notDownloaded.rawValue {
                fields.append("episodeStatus")
                values.append(DownloadStatus.notDownloaded.rawValue)
                fields.append("autoDownloadStatus")
                values.append(AutoDownloadStatus.userDeletedFile.rawValue)
                fields.append("cachedFrameCount")
                values.append(0)
            }
            if markAsPlayed, episode.playingStatus != PlayingStatus.completed.rawValue {
                fields.append("playingStatus")
                values.append(PlayingStatus.completed.rawValue)

                if updateSyncFlag {
                    fields.append("playingStatusModified")
                    values.append(DBUtils.currentUTCTimeInMillis())
                }
            }
            if fields.isEmpty { continue }

            updates.append((fields, values, episode.uuid))
        }

        performBulkUpdates(updates, methodName: "bulkArchive", dbQueue: dbQueue)
    }

    func bulkUnarchive(episodes: [Episode], updateSyncFlag: Bool, dbQueue: GRDBQueue) {
        if episodes.isEmpty { return }

        var updates = [(fields: [String], values: [Any], uuid: String)]()
        for episode in episodes {
            if !episode.archived { continue }

            var fields = ["archived"]
            var values: [Any] = [false]

            if updateSyncFlag {
                fields.append("archivedModified")
                values.append(DBUtils.currentUTCTimeInMillis())
            }

            if let podcastAutoArchiveLimit = episode.parentPodcast()?.autoArchiveEpisodeLimitCount, podcastAutoArchiveLimit > 0 {
                fields.append("excludeFromEpisodeLimit")
                values.append(true)
            }

            updates.append((fields, values, episode.uuid))
        }

        performBulkUpdates(updates, methodName: "bulkUnarchive", dbQueue: dbQueue)
    }

    /// Converts legacy `[Any]` binding values for the GRDB path, matching the legacy shim's
    /// conversions: `Date` binds as `timeIntervalSince1970` and `NSNull` as NULL.
    private static func databaseValue(from value: Any) -> DatabaseValue {
        if let date = value as? Date {
            return date.timeIntervalSince1970.databaseValue
        }
        if value is NSNull {
            return .null
        }
        return DatabaseValue(value: value) ?? .null
    }

    private func save(fields: [String], values: [Any], useId: Bool = true, dbQueue: GRDBQueue) {
        // The last value is the id/uuid used by the WHERE clause, mirroring the legacy layout
        guard values.count == fields.count + 1 else { return }

        _ = dbQueue.write { db in
            try save(fields: fields, values: values, useId: useId, db: db)
        }
    }

    private func save(fields: [String], values: [Any], useId: Bool = true, db: Database) throws {
        // The last value is the id/uuid used by the WHERE clause, mirroring the legacy layout
        guard values.count == fields.count + 1, let identifier = values.last else { return }

        let assignments = zip(fields, values).map { field, value in
            Column(field).set(to: Self.databaseValue(from: value))
        }
        let filter: SQLSpecificExpressible = useId
            ? Episode.Columns.id == Self.databaseValue(from: identifier)
            : Episode.Columns.uuid == Self.databaseValue(from: identifier)

        try Episode.filter(filter).updateAll(db, assignments)
    }

    private func save(fieldName: String, value: Any, episodeId: Int64, dbQueue: GRDBQueue) {
        _ = dbQueue.write { db in
            try Episode
                .filter(Episode.Columns.id == episodeId)
                .updateAll(db, Column(fieldName).set(to: Self.databaseValue(from: value)))
        }
    }

    private func save(fieldName: String, value: Any, episodeUuid: String, dbQueue: GRDBQueue) {
        _ = dbQueue.write { db in
            try Episode
                .filter(Episode.Columns.uuid == episodeUuid)
                .updateAll(db, Column(fieldName).set(to: Self.databaseValue(from: value)))
        }
    }

    private func saveFieldIfNotModified(fieldName: String, modifiedFieldName: String, value: Any, episodeUuid: String, dbQueue: GRDBQueue) -> Bool {
        let updated = dbQueue.write { (db: Database) -> Int in
            try Episode
                .filter(Episode.Columns.uuid == episodeUuid)
                .filter(Column(modifiedFieldName) == 0)
                .updateAll(db, Column(fieldName).set(to: Self.databaseValue(from: value)))
        }
        return (updated ?? 0) > 0
    }

    private func saveFieldIfNotModified(fieldName: String, modifiedFieldName: String, value: Any, remoteModified: Int64, episodeUuid: String, dbQueue: GRDBQueue) -> Bool {
        let updated = dbQueue.write { (db: Database) -> Int in
            try Episode
                .filter(Episode.Columns.uuid == episodeUuid)
                .filter(Column(modifiedFieldName) < remoteModified)
                .updateAll(db, Column(fieldName).set(to: Self.databaseValue(from: value)))
        }
        return (updated ?? 0) > 0
    }

    private func updateAll(fields: [String], values: [Any], whereClause: String?, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            do {
                var query = "UPDATE \(DataManager.episodeTableName) SET \(fields.joined(separator: " = ?, ")) = ?"
                if let whereClause {
                    query += " WHERE \(whereClause)"
                }
                try db.executeUpdate(query, values: values) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - generic bulk field-update writer; fields are internal callers' column lists, values bound
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.updateAll error: \(error)")
            }
        }
    }

    // MARK: - Conversion

    private func createEpisodeFrom(resultSet rs: PCDBResultSet) -> Episode? {
        Episode.from(resultSet: rs)
    }
}



// MARK: - 👻 Ghost Episodes 👻

extension EpisodeDataManager {
    func findGhostEpisodes(_ dbQueue: GRDBQueue) -> [Episode] {
        return dbQueue.read { (db: Database) -> [Episode] in
            // Anti-join equivalent of the legacy LEFT JOIN ... IS NULL pairs: episodes whose
            // podcast row is gone and that aren't referenced by a live playlist entry
            let podcastUuids = try Podcast.select(Podcast.Columns.uuid, as: String.self).fetchAll(db)
            let playlistEpisodeUuids = try Table(DataManager.playlistEpisodeTableName)
                .filter(Column("wasDeleted") == false)
                .filter(Column("playlist_uuid") != nil)
                .select([Column("episodeUuid")], as: String.self)
                .fetchAll(db)

            return try Episode
                .filter(!podcastUuids.contains(Episode.Columns.podcastUuid))
                .filter(!playlistEpisodeUuids.contains(Episode.Columns.uuid))
                .fetchAll(db)
        } ?? []
    }
}
