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

    func findBy(uuid: String, dbQueue: PCDBQueue) -> Episode? {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.fetchOne(Episode.filter(Episode.Columns.uuid == uuid))
        }

        return loadSingle(query: "SELECT * from \(DataManager.episodeTableName) WHERE uuid = ?", values: [uuid], dbQueue: dbQueue)
    }

    func findByAsync(uuid: String, dbQueue: PCDBQueue) async -> Episode? {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            do {
                return try await grdbQueue.dbPool.read { db in
                    try Episode.filter(Episode.Columns.uuid == uuid).fetchOne(db)
                }
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.findByAsync error: \(error)")
                return nil
            }
        }

        let query = "SELECT * from \(DataManager.episodeTableName) WHERE uuid = ?"
        do {
            return try await dbQueue.read { db in
                try self.loadSingle(query: query, values: [uuid], db: db)
            }
        } catch {
            FileLog.shared.addMessage("EpisodeDataManager.findByAsync error: \(error)")
            return nil
        }
    }

    func findWhere(customWhere: String, arguments: [Any]?, dbQueue: PCDBQueue) -> Episode? {
        loadSingle(query: "SELECT * from \(DataManager.episodeTableName) WHERE \(customWhere)", values: arguments, dbQueue: dbQueue)
    }

    func findPlayedEpisodes(uuids: [String], dbQueue: PCDBQueue) -> [String] {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.read { (db: Database) -> [String] in
                try Episode
                    .filter(uuids.contains(Episode.Columns.uuid))
                    .filter(Episode.Columns.playingStatus == PlayingStatus.completed.rawValue)
                    .limit(uuids.count)
                    .select(Episode.Columns.uuid, as: String.self)
                    .fetchAll(db)
            } ?? []
        }

        let query = """
        SELECT * from \(DataManager.episodeTableName)
        WHERE uuid IN (\(DBUtils.placeholders(amount: uuids.count)))
        AND playingStatus = ?
        LIMIT \(uuids.count)
        """

        var episodes = [String]()
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery(query, values: uuids + [PlayingStatus.completed.rawValue])
                defer { resultSet.close() }

                while resultSet.next() {
                    let uuid = DBUtils.nonNilStringFromColumn(resultSet: resultSet, columnName: "uuid")
                    episodes.append(uuid)
                }
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.loadMultiple Episode error: \(error)")
            }
        }
        return episodes
    }

    func findMatchingEpisodes(uuids: [String], dbQueue: PCDBQueue) -> [String] {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.read { (db: Database) -> [String] in
                try Episode
                    .filter(uuids.contains(Episode.Columns.uuid))
                    .limit(uuids.count)
                    .select(Episode.Columns.uuid, as: String.self)
                    .fetchAll(db)
            } ?? []
        }

        let query = """
        SELECT uuid from \(DataManager.episodeTableName)
        WHERE uuid IN (\(DBUtils.placeholders(amount: uuids.count)))
        LIMIT \(uuids.count)
        """

        var episodes = [String]()
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery(query, values: uuids)
                defer { resultSet.close() }

                while resultSet.next() {
                    let uuid = DBUtils.nonNilStringFromColumn(resultSet: resultSet, columnName: "uuid")
                    episodes.append(uuid)
                }
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.findMissingEpisodes error: \(error)")
            }
        }

        return episodes
    }

    func findPlayedEpisodesCount(podcastId: Int64, dbQueue: PCDBQueue) async -> Int {
        // Uses the genuinely-async `read` (off the caller's executor) rather than the
        // synchronous `read` wrapped in a continuation, which would block whatever thread
        // the caller runs on — main-thread-blocking when awaited from a `@MainActor` caller.
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            do {
                return try await grdbQueue.dbPool.read { db in
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

        let query = "SELECT COUNT(*) as Count from \(DataManager.episodeTableName) WHERE podcast_id = ? AND playedUpTo > (duration / 2)"
        do {
            return try await dbQueue.read { db in
                let resultSet = try db.executeQuery(query, values: [podcastId])
                defer { resultSet.close() }

                if resultSet.next() {
                    return Int(resultSet.int(forColumn: "Count"))
                }
                return 0
            }
        } catch {
            FileLog.shared.addMessage("EpisodeDataManager.findPlayedEpisodesCount error: \(error)")
            return 0
        }
    }

    func downloadedEpisodeExists(uuid: String, dbQueue: PCDBQueue) -> Bool {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.count(
                Episode.self,
                filter: Episode.Columns.episodeStatus == DownloadStatus.downloaded.rawValue && Episode.Columns.uuid == uuid
            ) > 0
        }

        var found = false
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery("SELECT id from \(DataManager.episodeTableName) WHERE episodeStatus = ? AND uuid = ?", values: [DownloadStatus.downloaded.rawValue, uuid])
                defer { resultSet.close() }

                if resultSet.next() {
                    found = true
                }
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.downloadedEpisodeExists error: \(error)")
            }
        }

        return found
    }

    func findBy(downloadTaskId: String, dbQueue: PCDBQueue) -> Episode? {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.fetchOne(Episode.filter(Episode.Columns.downloadTaskId == downloadTaskId))
        }

        return loadSingle(query: "SELECT * from \(DataManager.episodeTableName) WHERE downloadTaskId = ?", values: [downloadTaskId], dbQueue: dbQueue)
    }

    func findWhereNotNull(columnName: String, dbQueue: PCDBQueue) -> [Episode] {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.fetchAll(Episode.filter(Column(columnName) != nil))
        }

        return loadMultiple(query: "SELECT * from \(DataManager.episodeTableName) WHERE \(columnName) IS NOT NULL", values: nil, dbQueue: dbQueue)
    }

    /// SQLite's UPPER() only folds ASCII letters; the GRDB search paths must uppercase bound
    /// terms the same way to keep LIKE matching identical to the legacy `UPPER(?)` binding.
    private static func sqliteUppercased(_ term: String) -> String {
        String(term.map { $0.isASCII ? Character($0.uppercased()) : $0 })
    }

    func findEpisodesAndPodcastsWhere(customWhere: String, listenedTo: Bool, dbQueue: PCDBQueue) -> [Episode] {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.read { (db: Database) -> [Episode] in
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

        let listenedToQuery: String = """
        lastPlaybackInteractionDate IS NOT NULL
        AND lastPlaybackInteractionDate > 0
        AND
        """
        let query = """
        SELECT episode.* FROM \(DataManager.episodeTableName) episode
        LEFT JOIN \(DataManager.podcastTableName) podcast ON episode.podcast_id = podcast.id
        WHERE
        \(listenedTo ? listenedToQuery : "")
        (UPPER(episode.title) LIKE '%' || UPPER(?) || '%'  ESCAPE '\\'
         OR UPPER(podcast.title) LIKE '%' || UPPER(?) || '%'  ESCAPE '\\')
        ORDER BY lastPlaybackInteractionDate DESC LIMIT 1000
        """
        return loadMultiple(query: query, values: [customWhere, customWhere], dbQueue: dbQueue)
    }

    func findEpisodesWhere(customWhere: String, arguments: [Any]?, dbQueue: PCDBQueue) -> [Episode] {
        loadMultiple(query: "SELECT * from \(DataManager.episodeTableName) WHERE \(customWhere)", values: arguments, dbQueue: dbQueue)
    }

    func findEpisodes(with term: String, podcastUUID: String, dbQueue: PCDBQueue) -> [Episode] {
        let escapedSearch = term.escapeLike(escapeChar: "\\")

        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.fetchAll(
                Episode
                    .filter(Episode.Columns.title.uppercased.like("%\(Self.sqliteUppercased(escapedSearch))%", escape: "\\"))
                    .filter(Episode.Columns.podcastUuid == podcastUUID)
                    .filter(Episode.Columns.wasDeleted == false)
                    .order(Episode.Columns.publishedDate.desc, Episode.Columns.addedDate.desc)
            )
        }

        let query = """
        (UPPER(title) LIKE '%' || UPPER(?) || '%'  ESCAPE '\\' AND
        podcastUuid = ? AND wasDeleted = 0)
        ORDER BY publishedDate DESC, addedDate DESC
        """

        return findEpisodesWhere(customWhere: query, arguments: [escapedSearch, podcastUUID], dbQueue: dbQueue)
    }

    func findPlaylistEpisodesWhere(query: String, arguments: [Any]?, dbQueue: PCDBQueue) -> [Episode] {
        loadMultiple(query: query, values: arguments, dbQueue: dbQueue)
    }

    func unsyncedEpisodes(limit: Int, dbQueue: PCDBQueue) -> [Episode] {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.fetchAll(
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

        return loadMultiple(query: "SELECT * from \(DataManager.episodeTableName) WHERE playingStatusModified > 0 OR playedUpToModified > 0 OR durationModified > 0 OR keepEpisodeModified > 0 OR archivedModified > 0 ORDER BY publishedDate DESC, addedDate DESC LIMIT \(limit)", values: nil, dbQueue: dbQueue)
    }

    func allEpisodesForPodcast(id: Int64, dbQueue: PCDBQueue) -> [Episode] {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.fetchAll(
                Episode
                    .filter(Episode.Columns.podcast_id == id)
                    .filter(Episode.Columns.wasDeleted == false)
            )
        }

        return loadMultiple(query: "SELECT * from \(DataManager.episodeTableName) WHERE podcast_id = ? AND wasDeleted = 0", values: [id], dbQueue: dbQueue)
    }

    func episodesWithListenHistory(limit: Int, dbQueue: PCDBQueue) -> [Episode] {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.fetchAll(
                Episode
                    .filter(Episode.Columns.lastPlaybackInteractionDate != nil)
                    .filter(Episode.Columns.lastPlaybackInteractionDate > 0)
                    .order(Episode.Columns.lastPlaybackInteractionDate.desc)
                    .limit(limit)
            )
        }

        return loadMultiple(query: "SELECT * from \(DataManager.episodeTableName) WHERE lastPlaybackInteractionDate IS NOT NULL AND lastPlaybackInteractionDate > 0 ORDER BY lastPlaybackInteractionDate DESC LIMIT \(limit)", values: nil, dbQueue: dbQueue)
    }

    /// Returns daily listening totals as `[dateString: totalSeconds]` for the past N days.
    /// Date strings are formatted as "yyyy-MM-dd" in the device's local timezone.
    func dailyListeningTime(forLast days: Int, dbQueue: PCDBQueue) -> [String: Double] {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            // strftime('%s','now','-N days') subtracts exact days from UTC epoch seconds, i.e.
            // now - N*86400; the per-day bucketing replicates date(x,'unixepoch','localtime')
            let cutoff = Date().timeIntervalSince1970 - Double(days) * 86400
            let rows = grdbQueue.read { (db: Database) -> [Row] in
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

        var result: [String: Double] = [:]

        dbQueue.read { db in
            do {
                let query = """
                    SELECT date(lastPlaybackInteractionDate, 'unixepoch', 'localtime') as listenDate,
                           SUM(playedUpTo) as totalTime
                    FROM \(DataManager.episodeTableName)
                    WHERE lastPlaybackInteractionDate IS NOT NULL
                      AND lastPlaybackInteractionDate >= strftime('%s', 'now', '-\(days) days')
                    GROUP BY listenDate
                    ORDER BY listenDate ASC
                    """
                let resultSet = try db.executeQuery(query, values: nil)
                defer { resultSet.close() }

                while resultSet.next() {
                    if let day = resultSet.string(forColumn: "listenDate") {
                        result[day] = resultSet.double(forColumn: "totalTime")
                    }
                }
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.dailyListeningTime error: \(error)")
            }
        }

        return result
    }

    func findLatestEpisode(podcast: Podcast, dbQueue: PCDBQueue) -> Episode? {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.fetchOne(latestEpisodesRequest(podcastId: podcast.id).limit(1))
        }

        return loadSingle(query: "SELECT * from \(DataManager.episodeTableName) WHERE podcast_id = ? AND wasDeleted = 0 ORDER BY publishedDate DESC, addedDate DESC LIMIT 1", values: [podcast.id], dbQueue: dbQueue)
    }

    func findLatestEpisodes(podcast: Podcast, limit: Int, dbQueue: PCDBQueue) -> [Episode] {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.fetchAll(latestEpisodesRequest(podcastId: podcast.id).limit(limit))
        }

        return loadMultiple(query: "SELECT * from \(DataManager.episodeTableName) WHERE podcast_id = ? AND wasDeleted = 0 ORDER BY publishedDate DESC, addedDate DESC LIMIT ?", values: [podcast.id, limit], dbQueue: dbQueue)
    }

    private func latestEpisodesRequest(podcastId: Int64) -> QueryInterfaceRequest<Episode> {
        Episode
            .filter(Episode.Columns.podcast_id == podcastId)
            .filter(Episode.Columns.wasDeleted == false)
            .order(Episode.Columns.publishedDate.desc, Episode.Columns.addedDate.desc)
    }

    func allUpNextEpisodes(dbQueue: PCDBQueue) -> [Episode] {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.read { (db: Database) -> [Episode] in
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

        let upNextTableName = DataManager.playlistEpisodeTableName
        let episodeTableName = DataManager.episodeTableName

        return loadMultiple(
            query: """
            SELECT \(episodeTableName).*
            FROM \(upNextTableName)
            JOIN \(episodeTableName)
            ON \(episodeTableName).uuid = \(upNextTableName).episodeUuid
            WHERE \(upNextTableName).playlist_id = ?
            ORDER BY \(upNextTableName).episodePosition ASC
            """,
            values: [UpNextDataManager.upNextPlaylistId],
            dbQueue: dbQueue
        )
    }

    func allUpNextEpisodes(from uuids: [String], dbQueue: PCDBQueue) -> [Episode] {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.read { (db: Database) -> [Episode] in
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

        let placeholders = DBUtils.placeholders(amount: uuids.count)
        let upNextTableName = DataManager.playlistEpisodeTableName
        let episodeTableName = DataManager.episodeTableName
        return loadMultiple(
            query: """
            SELECT DISTINCT \(episodeTableName).*
            FROM \(upNextTableName)
            JOIN \(episodeTableName)
            ON \(episodeTableName).uuid = \(upNextTableName).episodeUuid
            WHERE \(episodeTableName).uuid IN (\(placeholders))
            ORDER BY \(upNextTableName).episodePosition ASC
            """,
            values: uuids,
            dbQueue: dbQueue
        )
    }

    private func loadSingle(query: String, values: [Any]?, dbQueue: PCDBQueue) -> Episode? {
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
        let resultSet = try db.executeQuery(query, values: values)
        defer { resultSet.close() }

        return resultSet.next() ? createEpisodeFrom(resultSet: resultSet) : nil
    }

    private func loadMultiple(query: String, values: [Any]?, dbQueue: PCDBQueue) -> [Episode] {
        var episodes = [Episode]()
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery(query, values: values)
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

    func downloadedEpisodeCount(dbQueue: PCDBQueue) -> Int {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.count(Episode.self, filter: Episode.Columns.episodeStatus == DownloadStatus.downloaded.rawValue)
        }

        var count = 0
        let query = "SELECT COUNT(*) as Count from \(DataManager.episodeTableName) WHERE episodeStatus = \(DownloadStatus.downloaded.rawValue)"
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery(query, values: nil)
                defer { resultSet.close() }

                if resultSet.next() {
                    count = Int(resultSet.int(forColumn: "Count"))
                }
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.downloadedEpisodeCount error: \(error)")
            }
        }

        return count
    }

    func failedDownloadEpisodeCount(dbQueue: PCDBQueue) -> Int {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.count(Episode.self, filter: Episode.Columns.episodeStatus == DownloadStatus.downloadFailed.rawValue)
        }

        var count = 0
        let query = "SELECT COUNT(*) as Count from \(DataManager.episodeTableName) WHERE episodeStatus = \(DownloadStatus.downloadFailed.rawValue)"
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery(query, values: nil)
                defer { resultSet.close() }

                if resultSet.next() {
                    count = Int(resultSet.int(forColumn: "Count"))
                }
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.downloadedEpisodeCount error: \(error)")
            }
        }

        return count
    }

    func failedDownloadFirstDate(dbQueue: PCDBQueue, sortOrder: SortOrder) -> Date? {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            var request = Episode
                .filter(Episode.Columns.episodeStatus == DownloadStatus.downloadFailed.rawValue)
                .filter(Episode.Columns.lastDownloadAttemptDate != nil)
            request = sortOrder == .forward
                ? request.order(Episode.Columns.lastDownloadAttemptDate.desc)
                : request.order(Episode.Columns.lastDownloadAttemptDate.asc)
            return grdbQueue.fetchOne(request)?.lastDownloadAttemptDate
        }

        let orderDirection = sortOrder == .forward ? "DESC" : "ASC"
        var date: Date?
        let query = "SELECT * from \(DataManager.episodeTableName) WHERE episodeStatus = \(DownloadStatus.downloadFailed.rawValue) AND lastDownloadAttemptDate IS NOT NULL ORDER BY lastDownloadAttemptDate \(orderDirection) LIMIT 1"
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery(query, values: nil)
                defer { resultSet.close() }

                if resultSet.next() {
                    date = resultSet.date(forColumn: "lastDownloadAttemptDate")
                }
            } catch {
                logError(error: error)
            }
        }

        return date
    }

    func logError(error: Error, callingFile: String = #file, callingFunction: String = #function) {
        FileLog.shared.addMessage("\((callingFile.components(separatedBy: "/").last ?? "").components(separatedBy: ".").first ?? "").\(callingFunction) error: \(error)")
    }

    // MARK: - Updates

    func saveIfNotModified(starred: Bool, episodeUuid: String, dbQueue: PCDBQueue) -> Bool {
        if !starred {
            saveEpisode(starredModified: 0, episodeUuid: episodeUuid, dbQueue: dbQueue)
        }
        return saveFieldIfNotModified(fieldName: "keepEpisode", modifiedFieldName: "keepEpisodeModified", value: starred, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveIfNotModified(archived: Bool, episodeUuid: String, dbQueue: PCDBQueue) -> Bool {
        saveFieldIfNotModified(fieldName: "archived", modifiedFieldName: "archivedModified", value: archived, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveIfNotModified(playingStatus: PlayingStatus, episodeUuid: String, dbQueue: PCDBQueue) -> Bool {
        saveFieldIfNotModified(fieldName: "playingStatus", modifiedFieldName: "playingStatusModified", value: playingStatus.rawValue, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveIfNotModified(chapters: String, remoteModified: Int64, episodeUuid: String, dbQueue: PCDBQueue) -> Bool {
        saveFieldIfNotModified(fieldName: "deselectedChapters", modifiedFieldName: "deselectedChaptersModified", value: chapters, remoteModified: remoteModified, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func save(episode: Episode, dbQueue: PCDBQueue) {
        let isInsert = episode.id == 0
        if isInsert {
            episode.id = DBUtils.generateUniqueId()
        }

        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            // GRDB path using PersistableRecord
            do {
                try grdbQueue.dbPool.write { db in
                    try episode.save(db)
                }
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.save Episode error: \(error)")
            }
        } else {
            // Legacy path
            dbQueue.write { db in
                do {
                    if isInsert {
                        try db.executeUpdate("INSERT INTO \(DataManager.episodeTableName) (\(self.columnNames.joined(separator: ","))) VALUES \(DBUtils.valuesQuestionMarks(amount: self.columnNames.count))", values: self.createValuesFrom(episode: episode))
                    } else {
                        let setStatement = "\(self.columnNames.joined(separator: " = ?, ")) = ?"
                        try db.executeUpdate("UPDATE \(DataManager.episodeTableName) SET \(setStatement) WHERE id = ?", values: self.createValuesFrom(episode: episode, includeIdForWhere: true))
                    }
                } catch {
                    FileLog.shared.addMessage("EpisodeDataManager.save Episode error: \(error)")
                }
            }
        }
    }

    func bulkSave(episodes: [Episode], dbQueue: PCDBQueue) {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            // GRDB path using PersistableRecord
            do {
                try grdbQueue.dbPool.write { db in
                    for episode in episodes {
                        if episode.id == 0 {
                            episode.id = DBUtils.generateUniqueId()
                        }
                        try episode.save(db)
                    }
                }
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.bulkSave error: \(error)")
            }
        } else {
            // Legacy path
            dbQueue.write { db in
                do {
                    db.beginTransaction()

                    for episode in episodes {
                        let isInsert = episode.id == 0
                        if isInsert {
                            episode.id = DBUtils.generateUniqueId()
                        }

                        if isInsert {
                            try db.executeUpdate("INSERT INTO \(DataManager.episodeTableName) (\(self.columnNames.joined(separator: ","))) VALUES \(DBUtils.valuesQuestionMarks(amount: self.columnNames.count))", values: self.createValuesFrom(episode: episode))
                        } else {
                            let setStatement = "\(self.columnNames.joined(separator: " = ?, ")) = ?"
                            try db.executeUpdate("UPDATE \(DataManager.episodeTableName) SET \(setStatement) WHERE id = ?", values: self.createValuesFrom(episode: episode, includeIdForWhere: true))
                        }
                    }

                    db.commit()
                } catch {
                    FileLog.shared.addMessage("EpisodeDataManager.bulkSave error: \(error)")
                }
            }
        }
    }

    /// Applies one `(fields, values)` update per episode uuid inside a single transaction on
    /// either path — the shared execution for the bulk mutation methods below.
    private func performBulkUpdates(_ updates: [(fields: [String], values: [Any], uuid: String)], methodName: String, dbQueue: PCDBQueue) {
        if updates.isEmpty { return }

        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.write { db in
                for update in updates {
                    let assignments = zip(update.fields, update.values).map { field, value in
                        Column(field).set(to: Self.databaseValue(from: value))
                    }
                    try Episode.filter(Episode.Columns.uuid == update.uuid).updateAll(db, assignments)
                }
            }
            return
        }

        dbQueue.write { db in
            do {
                db.beginTransaction()
                for update in updates {
                    let setStatement = "SET \(update.fields.joined(separator: " = ?, ")) = ?"
                    try db.executeUpdate("UPDATE \(DataManager.episodeTableName) \(setStatement) WHERE uuid = ?", values: update.values + [update.uuid])
                }
                db.commit()
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.\(methodName) error: \(error)")
            }
        }
    }

    func bulkSetStarred(starred: Bool, episodes: [Episode], updateSyncFlag: Bool, dbQueue: PCDBQueue) {
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

    func bulkUserFileDelete(episodes: [Episode], dbQueue: PCDBQueue) {
        if episodes.isEmpty { return }

        let updates = episodes.map { episode -> (fields: [String], values: [Any], uuid: String) in
            (
                fields: ["episodeStatus", "autoDownloadStatus", "cachedFrameCount"],
                values: [DownloadStatus.notDownloaded.rawValue, AutoDownloadStatus.userDeletedFile.rawValue, 0],
                uuid: episode.uuid
            )
        }

        performBulkUpdates(updates, methodName: "bulkUserFileDelete", dbQueue: dbQueue)
    }

    func saveFileType(episode: Episode, fileType: String, dbQueue: PCDBQueue) {
        episode.fileType = fileType
        save(fieldName: "fileType", value: fileType, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveContentType(episode: Episode, contentType: String, dbQueue: PCDBQueue) {
        episode.contentType = contentType
        save(fieldName: "contentType", value: contentType, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveFileSize(episode: Episode, fileSize: Int64, dbQueue: PCDBQueue) {
        episode.sizeInBytes = fileSize
        save(fieldName: "sizeInBytes", value: fileSize, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveBulkEpisodeSyncInfo(episodes: [EpisodeBasicData], dbQueue: PCDBQueue) {
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

    func saveFrameCount(episodeId: Int64, frameCount: Int64, dbQueue: PCDBQueue) {
        save(fieldName: "cachedFrameCount", value: frameCount, episodeId: episodeId, dbQueue: dbQueue)
    }

    func findFrameCount(episodeId: Int64, dbQueue: PCDBQueue) -> Int64 {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.fetchOne(Episode.filter(Episode.Columns.id == episodeId))?.cachedFrameCount ?? 0
        }

        var frameCount = 0 as Int64

        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery("SELECT cachedFrameCount from \(DataManager.episodeTableName) WHERE id = ?", values: [episodeId])
                defer { resultSet.close() }

                if resultSet.next() {
                    frameCount = resultSet.longLongInt(forColumn: "cachedFrameCount")
                }
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.findFrameCount error: \(error)")
            }
        }

        return frameCount
    }

    func saveEpisode(playbackError: String?, episode: Episode, dbQueue: PCDBQueue) {
        episode.playbackErrorDetails = playbackError
        save(fieldName: "playbackErrorDetails", value: DBUtils.replaceNilWithNull(value: episode.playbackErrorDetails), episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveEpisode(playedUpTo: Double, episode: Episode, updateSyncFlag: Bool, dbQueue: PCDBQueue) {
        episode.playedUpTo = playedUpTo
        var fields = ["playedUpTo"]
        var values = [episode.playedUpTo] as [Any]

        if updateSyncFlag {
            episode.playedUpToModified = DBUtils.currentUTCTimeInMillis()
            fields.append("playedUpToModified")
            values.append(episode.playedUpToModified)
        }
        values.append(episode.id)

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func updateEpisodePlaybackInteractionDate(episode: Episode, dbQueue: PCDBQueue) {
        let now = Date()
        let syncStatus = SyncStatus.notSynced.rawValue
        episode.lastPlaybackInteractionDate = now
        episode.lastPlaybackInteractionSyncStatus = syncStatus
        let fields = ["lastPlaybackInteractionDate", "lastPlaybackInteractionSyncStatus"]
        let values = [now, syncStatus, episode.id] as [Any]
        FileLog.shared.console("[Episode Save] Episode id \(episode.id) - title: \(episode.title ?? "no title")")
        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func clearEpisodePlaybackInteractionDate(episodeUuid: String, dbQueue: PCDBQueue) {
        save(fieldName: "lastPlaybackInteractionDate", value: NSNull(), episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func setEpisodePlaybackInteractionDate(interactionDate: Date, episodeUuid: String, dbQueue: PCDBQueue) {
        save(fieldName: "lastPlaybackInteractionDate", value: interactionDate, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func markAllEpisodePlaybackHistorySynced(dbQueue: PCDBQueue) {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            _ = grdbQueue.write { db in
                try Episode.updateAll(db, Episode.Columns.lastPlaybackInteractionSyncStatus.set(to: SyncStatus.synced.rawValue))
            }
            return
        }

        dbQueue.write { db in
            do {
                try db.executeUpdate("UPDATE \(DataManager.episodeTableName) SET lastPlaybackInteractionSyncStatus = ?", values: [SyncStatus.synced.rawValue])
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.markAllEpisodePlaybackHistorySynced error: \(error)")
            }
        }
    }

    func clearEpisodePlaybackInteractionDatesBefore(date: Date, dbQueue: PCDBQueue) {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.updateAll(
                Episode.self,
                filter: Episode.Columns.lastPlaybackInteractionDate <= date.timeIntervalSince1970,
                Episode.Columns.lastPlaybackInteractionDate.set(to: nil as Double?)
            )
            return
        }

        dbQueue.write { db in
            do {
                try db.executeUpdate("UPDATE \(DataManager.episodeTableName) SET lastPlaybackInteractionDate = NULL WHERE lastPlaybackInteractionDate <= ?", values: [date])
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.clearEpisodePlaybackInteractionDatesBefore error: \(error)")
            }
        }
    }

    func clearAllEpisodePlaybackInteractions(dbQueue: PCDBQueue) {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.updateAll(
                Episode.self,
                filter: Episode.Columns.lastPlaybackInteractionDate > 0,
                Episode.Columns.lastPlaybackInteractionDate.set(to: nil as Double?)
            )
            return
        }

        dbQueue.write { db in
            do {
                try db.executeUpdate("UPDATE \(DataManager.episodeTableName) SET lastPlaybackInteractionDate = NULL WHERE lastPlaybackInteractionDate > 0", values: [])
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.clearAllEpisodePlaybackInteractions error: \(error)")
            }
        }
    }

    func saveEpisode(playingStatus: PlayingStatus, episode: Episode, updateSyncFlag: Bool, dbQueue: PCDBQueue) {
        episode.playingStatus = playingStatus.rawValue
        var fields = ["playingStatus"]
        var values = [episode.playingStatus] as [Any]

        if updateSyncFlag {
            episode.playingStatusModified = DBUtils.currentUTCTimeInMillis()
            fields.append("playingStatusModified")
            values.append(episode.playingStatusModified)
        }
        values.append(episode.id)

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(archived: Bool, episode: Episode, updateSyncFlag: Bool, dbQueue: PCDBQueue) {
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

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(excludeFromEpisodeLimit: Bool, episode: Episode, dbQueue: PCDBQueue) {
        episode.excludeFromEpisodeLimit = excludeFromEpisodeLimit
        save(fieldName: "excludeFromEpisodeLimit", value: episode.excludeFromEpisodeLimit, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveEpisode(duration: Double, episode: Episode, updateSyncFlag: Bool, dbQueue: PCDBQueue) {
        episode.duration = duration
        var fields = ["duration"]
        var values = [episode.duration] as [Any]

        if updateSyncFlag {
            episode.durationModified = DBUtils.currentUTCTimeInMillis()
            fields.append("durationModified")
            values.append(episode.durationModified)
        }
        values.append(episode.id)

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(starred: Bool, starredModified: Int64?, episode: Episode, updateSyncFlag: Bool, dbQueue: PCDBQueue) {
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

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, episode: Episode, dbQueue: PCDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        save(fieldName: "episodeStatus", value: episode.episodeStatus, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, lastDownloadAttemptDate: Date, autoDownloadStatus: AutoDownloadStatus, episode: Episode, dbQueue: PCDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        episode.lastDownloadAttemptDate = lastDownloadAttemptDate
        episode.autoDownloadStatus = autoDownloadStatus.rawValue

        let fields = ["episodeStatus", "lastDownloadAttemptDate", "autoDownloadStatus"]
        let values = [episode.episodeStatus, DBUtils.replaceNilWithNull(value: episode.lastDownloadAttemptDate), episode.autoDownloadStatus, episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(autoDownloadStatus: AutoDownloadStatus, episode: Episode, dbQueue: PCDBQueue) {
        episode.autoDownloadStatus = autoDownloadStatus.rawValue
        save(fieldName: "autoDownloadStatus", value: episode.autoDownloadStatus, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, downloadError: String?, downloadTaskId: String?, episode: Episode, dbQueue: PCDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        episode.downloadErrorDetails = downloadError
        episode.downloadTaskId = downloadTaskId

        let fields = ["episodeStatus", "downloadErrorDetails", "downloadTaskId"]
        let values = [episode.episodeStatus, DBUtils.replaceNilWithNull(value: episode.downloadErrorDetails), DBUtils.replaceNilWithNull(value: episode.downloadTaskId), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, downloadTaskId: String?, episode: Episode, dbQueue: PCDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        episode.downloadTaskId = downloadTaskId

        let fields = ["episodeStatus", "downloadTaskId"]
        let values = [episode.episodeStatus, DBUtils.replaceNilWithNull(value: episode.downloadTaskId), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, sizeInBytes: Int64, downloadTaskId: String?, episode: Episode, dbQueue: PCDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        episode.sizeInBytes = sizeInBytes
        episode.downloadTaskId = downloadTaskId

        let fields = ["episodeStatus", "sizeInBytes", "downloadTaskId"]
        let values = [episode.episodeStatus, episode.sizeInBytes, DBUtils.replaceNilWithNull(value: episode.downloadTaskId), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(downloadUrl: String, episodeUuid: String, dbQueue: PCDBQueue) {
        save(fieldName: "downloadUrl", value: downloadUrl, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveEpisode(starredModified: Int64, episodeUuid: String, dbQueue: PCDBQueue) {
        save(fieldName: "starredModified", value: starredModified, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func clearKeepEpisodeModified(episode: Episode, dbQueue: PCDBQueue) {
        let fields = ["keepEpisodeModified"]
        var values = [episode.keepEpisodeModified] as [Any]
        values.append(episode.id)

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func clearDownloadTaskId(episode: Episode, dbQueue: PCDBQueue) {
        save(fieldName: "downloadTaskId", value: NSNull(), episodeId: episode.id, dbQueue: dbQueue)
    }

    func delete(episodeUuid: String, dbQueue: PCDBQueue) {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.deleteAll(Episode.self, filter: Episode.Columns.uuid == episodeUuid)
            return
        }

        dbQueue.write { db in
            do {
                try db.executeUpdate("DELETE FROM \(DataManager.episodeTableName) WHERE uuid = ?", values: [episodeUuid])
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.delete error: \(error)")
            }
        }
    }

    func deleteAllEpisodesInPodcast(podcastId: Int64, dbQueue: PCDBQueue) {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.deleteAll(Episode.self, filter: Episode.Columns.podcast_id == podcastId)
            return
        }

        dbQueue.write { db in
            do {
                try db.executeUpdate("DELETE FROM \(DataManager.episodeTableName) WHERE podcast_id = ?", values: [podcastId])
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.deleteAllEpisodesInPodcast error: \(error)")
            }
        }
    }

    func markAllSynced(episodes: [Episode], dbQueue: PCDBQueue) {
        if episodes.isEmpty {
            return
        }

        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            // Single IN-statement form; equivalent to both legacy sub-branches
            let ids = episodes.map(\.id)
            grdbQueue.updateAll(
                Episode.self,
                filter: ids.contains(Episode.Columns.id),
                Episode.Columns.playingStatusModified.set(to: 0),
                Episode.Columns.playedUpToModified.set(to: 0),
                Episode.Columns.durationModified.set(to: 0),
                Episode.Columns.keepEpisodeModified.set(to: 0),
                Episode.Columns.archivedModified.set(to: 0)
            )
            return
        }

        dbQueue.write { db in
            do {
                db.beginTransaction()
                if FeatureFlag.markAllSyncedInSingleStatement.enabled {
                    let ids = episodes.map(\.id)
                    try db.executeUpdate("UPDATE \(DataManager.episodeTableName) SET playingStatusModified = 0, playedUpToModified = 0, durationModified = 0, keepEpisodeModified = 0, archivedModified = 0 WHERE id IN (\(DBUtils.placeholders(amount: ids.count)))", values: ids)
                } else {
                    for episode in episodes {
                        try db.executeUpdate("UPDATE \(DataManager.episodeTableName) SET playingStatusModified = 0, playedUpToModified = 0, durationModified = 0, keepEpisodeModified = 0, archivedModified = 0 WHERE id = ?", values: [episode.id])
                    }
                }
                db.commit()
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.markAllSynced error: \(error)")
            }
        }
    }

    func markAllSynced(episodeIDs ids: [String], dbQueue: PCDBQueue) {
        if ids.isEmpty {
            return
        }

        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            // Single IN-statement form; equivalent to both legacy sub-branches
            grdbQueue.updateAll(
                Episode.self,
                filter: ids.contains(Episode.Columns.uuid),
                Episode.Columns.playingStatusModified.set(to: 0),
                Episode.Columns.playedUpToModified.set(to: 0),
                Episode.Columns.durationModified.set(to: 0),
                Episode.Columns.keepEpisodeModified.set(to: 0),
                Episode.Columns.archivedModified.set(to: 0)
            )
            return
        }

        dbQueue.write { db in
            do {
                db.beginTransaction()
                if FeatureFlag.markAllSyncedInSingleStatement.enabled {
                    try db.executeUpdate("UPDATE \(DataManager.episodeTableName) SET playingStatusModified = 0, playedUpToModified = 0, durationModified = 0, keepEpisodeModified = 0, archivedModified = 0 WHERE uuid IN (\(DBUtils.placeholders(amount: ids.count)))", values: ids)
                } else {
                    for episodeId in ids {
                        try db.executeUpdate("UPDATE \(DataManager.episodeTableName) SET playingStatusModified = 0, playedUpToModified = 0, durationModified = 0, keepEpisodeModified = 0, archivedModified = 0 WHERE uuid = ?", values: [episodeId])
                    }
                }
                db.commit()
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.markAllSynced error: \(error)")
            }
        }
    }

    func markAllUnarchivedForPodcast(id: Int64, dbQueue: PCDBQueue) {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.updateAll(
                Episode.self,
                filter: Episode.Columns.podcast_id == id,
                Episode.Columns.archived.set(to: false)
            )
            return
        }

        updateAll(fields: ["archived"], values: [false, id], whereClause: "podcast_id = ?", dbQueue: dbQueue)
    }

    func bulkMarkAsPlayed(episodes: [Episode], updateSyncFlag: Bool, dbQueue: PCDBQueue) {
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

    func bulkMarkAsUnPlayed(episodes: [Episode], updateSyncFlag: Bool, dbQueue: PCDBQueue) {
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

    func bulkArchive(episodes: [Episode], markAsNotDownloaded: Bool, markAsPlayed: Bool, updateSyncFlag: Bool, dbQueue: PCDBQueue) {
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

    func bulkUnarchive(episodes: [Episode], updateSyncFlag: Bool, dbQueue: PCDBQueue) {
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

    private func save(fields: [String], values: [Any], useId: Bool = true, dbQueue: PCDBQueue) {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            // The last value is the id/uuid used by the WHERE clause, mirroring the legacy layout
            guard values.count == fields.count + 1, let identifier = values.last else { return }

            grdbQueue.write { db in
                let assignments = zip(fields, values).map { field, value in
                    Column(field).set(to: Self.databaseValue(from: value))
                }
                let filter: SQLSpecificExpressible = useId
                    ? Episode.Columns.id == Self.databaseValue(from: identifier)
                    : Episode.Columns.uuid == Self.databaseValue(from: identifier)

                try Episode.filter(filter).updateAll(db, assignments)
            }
            return
        }

        dbQueue.write { db in
            do {
                let setStatement = "SET \(fields.joined(separator: " = ?, ")) = ?"
                let idColumn = useId ? "id" : "uuid"
                try db.executeUpdate("UPDATE \(DataManager.episodeTableName) \(setStatement) WHERE \(idColumn) = ?", values: values)
                FileLog.shared.console("[Episode Save] \(idColumn) - \(setStatement) with values: \(values)")
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.save fields error: \(error)")
            }
        }
    }

    private func save(fieldName: String, value: Any, episodeId: Int64, dbQueue: PCDBQueue) {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.write { db in
                try Episode
                    .filter(Episode.Columns.id == episodeId)
                    .updateAll(db, Column(fieldName).set(to: Self.databaseValue(from: value)))
            }
            return
        }

        dbQueue.write { db in
            do {
                try db.executeUpdate("UPDATE \(DataManager.episodeTableName) SET \(fieldName) = ? WHERE id = ?", values: [value, episodeId])
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.save field by id error: \(error)")
            }
        }
    }

    private func save(fieldName: String, value: Any, episodeUuid: String, dbQueue: PCDBQueue) {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.write { db in
                try Episode
                    .filter(Episode.Columns.uuid == episodeUuid)
                    .updateAll(db, Column(fieldName).set(to: Self.databaseValue(from: value)))
            }
            return
        }

        dbQueue.write { db in
            do {
                try db.executeUpdate("UPDATE \(DataManager.episodeTableName) SET \(fieldName) = ? WHERE uuid = ?", values: [value, episodeUuid])
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.save field by uuid error: \(error)")
            }
        }
    }

    private func saveFieldIfNotModified(fieldName: String, modifiedFieldName: String, value: Any, episodeUuid: String, dbQueue: PCDBQueue) -> Bool {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            let updated = grdbQueue.write { (db: Database) -> Int in
                try Episode
                    .filter(Episode.Columns.uuid == episodeUuid)
                    .filter(Column(modifiedFieldName) == 0)
                    .updateAll(db, Column(fieldName).set(to: Self.databaseValue(from: value)))
            }
            return (updated ?? 0) > 0
        }

        var saved = false
        dbQueue.write { db in
            do {
                try db.executeUpdate("UPDATE \(DataManager.episodeTableName) SET \(fieldName) = ? WHERE uuid = ? AND \(modifiedFieldName) = 0", values: [value, episodeUuid])
                saved = (db.changes > 0)
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.saveFieldIfNotModified error: \(error)")
            }
        }

        return saved
    }

    private func saveFieldIfNotModified(fieldName: String, modifiedFieldName: String, value: Any, remoteModified: Int64, episodeUuid: String, dbQueue: PCDBQueue) -> Bool {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            let updated = grdbQueue.write { (db: Database) -> Int in
                try Episode
                    .filter(Episode.Columns.uuid == episodeUuid)
                    .filter(Column(modifiedFieldName) < remoteModified)
                    .updateAll(db, Column(fieldName).set(to: Self.databaseValue(from: value)))
            }
            return (updated ?? 0) > 0
        }

        var saved = false
        dbQueue.write { db in
            do {
                try db.executeUpdate("UPDATE \(DataManager.episodeTableName) SET \(fieldName) = ? WHERE uuid = ? AND \(modifiedFieldName) < ?", values: [value, episodeUuid, remoteModified])
                saved = (db.changes > 0)
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.saveFieldIfNotModified error: \(error)")
            }
        }

        return saved
    }

    private func updateAll(fields: [String], values: [Any], whereClause: String?, dbQueue: PCDBQueue) {
        dbQueue.write { db in
            do {
                var query = "UPDATE \(DataManager.episodeTableName) SET \(fields.joined(separator: " = ?, ")) = ?"
                if let whereClause {
                    query += " WHERE \(whereClause)"
                }
                try db.executeUpdate(query, values: values)
            } catch {
                FileLog.shared.addMessage("EpisodeDataManager.updateAll error: \(error)")
            }
        }
    }

    // MARK: - Conversion

    private func createEpisodeFrom(resultSet rs: PCDBResultSet) -> Episode? {
        Episode.from(resultSet: rs)
    }

    private func createValuesFrom(episode: Episode, includeIdForWhere: Bool = false) -> [Any] {
        var values = [Any]()
        values.append(episode.id)
        values.append(DBUtils.nullIfNil(value: episode.addedDate))
        values.append(episode.lastDownloadAttemptDate ?? Date(timeIntervalSince1970: 0))
        values.append(DBUtils.nullIfNil(value: episode.detailedDescription))
        values.append(DBUtils.nullIfNil(value: episode.downloadErrorDetails))
        values.append(DBUtils.nullIfNil(value: episode.downloadTaskId))
        values.append(DBUtils.nullIfNil(value: episode.downloadUrl))
        values.append(DBUtils.nullIfNil(value: episode.episodeDescription))
        values.append(episode.episodeStatus)
        values.append(DBUtils.nullIfNil(value: episode.fileType))
        values.append(DBUtils.nullIfNil(value: episode.contentType))
        values.append(episode.keepEpisode)
        values.append(episode.playedUpTo)
        values.append(episode.duration)
        values.append(episode.playingStatus)
        values.append(episode.autoDownloadStatus)
        values.append(DBUtils.nullIfNil(value: episode.publishedDate))
        values.append(episode.sizeInBytes)
        values.append(episode.playingStatusModified)
        values.append(episode.playedUpToModified)
        values.append(episode.durationModified)
        values.append(episode.keepEpisodeModified)
        values.append(DBUtils.nullIfNil(value: episode.title))
        values.append(episode.uuid)
        values.append(episode.podcastUuid)
        values.append(DBUtils.nullIfNil(value: episode.playbackErrorDetails))
        values.append(episode.cachedFrameCount)
        values.append(DBUtils.nullIfNil(value: episode.lastPlaybackInteractionDate))
        values.append(episode.lastPlaybackInteractionSyncStatus)
        values.append(episode.podcast_id)
        values.append(episode.episodeNumber)
        values.append(episode.seasonNumber)
        values.append(DBUtils.nullIfNil(value: episode.episodeType))
        values.append(episode.archived)
        values.append(episode.archivedModified)
        values.append(episode.lastArchiveInteractionDate ?? Date(timeIntervalSince1970: 0))
        values.append(episode.excludeFromEpisodeLimit)
        values.append(episode.starredModified)
        values.append(DBUtils.nullIfNil(value: episode.deselectedChapters))
        values.append(episode.deselectedChaptersModified)
        values.append(episode.wasDeleted)
        values.append(DBUtils.nullIfNil(value: episode.hasGeneratedTranscript))

        if includeIdForWhere {
            values.append(episode.id)
        }

        return values
    }
}



// MARK: - 👻 Ghost Episodes 👻

extension EpisodeDataManager {
    func findGhostEpisodes(_ dbQueue: PCDBQueue) -> [Episode] {
        if FeatureFlag.grdbQueryInterface.enabled, let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.read { (db: Database) -> [Episode] in
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

        let playlistTable = DataManager.playlistEpisodeTableName
        let query = """
        SELECT SJEpisode.*
        FROM SJEpisode
        LEFT JOIN SJPodcast ON SJEpisode.podcastUuid = SJPodcast.uuid
        LEFT JOIN \(playlistTable) ON \(playlistTable).episodeUuid = SJEpisode.uuid AND \(playlistTable).wasDeleted = 0 AND \(playlistTable).playlist_uuid IS NOT NULL
        WHERE SJPodcast.uuid IS NULL AND \(playlistTable).episodeUuid IS NULL
        """

        return loadMultiple(query: query, values: nil, dbQueue: dbQueue)
    }
}
