import PocketCastsUtils
import Foundation
import GRDB

final class UserEpisodeDataManager: Sendable {
    /// Legacy column names for non-GRDB code path.
    let columnNames = [
        "id",
        "addedDate",
        "lastDownloadAttemptDate",
        "downloadErrorDetails",
        "downloadTaskId",
        "downloadUrl",
        "episodeStatus",
        "fileType",
        "playedUpTo",
        "duration",
        "playingStatus",
        "autoDownloadStatus",
        "publishedDate",
        "sizeInBytes",
        "playingStatusModified",
        "playedUpToModified",
        "title",
        "uuid",
        "playbackErrorDetails",
        "cachedFrameCount",
        "uploadStatus",
        "uploadTaskId",
        "imageUrl",
        "imageColor",
        "hasCustomImage",
        "imageColorModified",
        "titleModified",
        "durationModified",
        "imageModified"
    ]

    // MARK: - GRDB Fetching

    /// Materializes a fetched row, backfilling the `@GRDBIgnore`d `contentType`: the record's
    /// coding keys exclude it so full saves match the legacy column set, but reads must still
    /// surface it like the legacy read path does.
    private static func episodeWithContentType(from row: Row) throws -> UserEpisode {
        let episode = try UserEpisode(row: row)
        episode.contentType = row["contentType"]
        return episode
    }

    private func grdbFetchAll(_ request: QueryInterfaceRequest<UserEpisode>, in grdbQueue: GRDBQueue) -> [UserEpisode] {
        grdbQueue.read { db in
            try Row.fetchAll(db, request.asRequest(of: Row.self)).map(Self.episodeWithContentType(from:))
        } ?? []
    }

    private func grdbFetchOne(_ request: QueryInterfaceRequest<UserEpisode>, in grdbQueue: GRDBQueue) -> UserEpisode? {
        // read's result is doubly optional (nil on error, inner nil for no row); flatten both to nil
        grdbQueue.read { db in
            try Row.fetchOne(db, request.asRequest(of: Row.self)).map(Self.episodeWithContentType(from:))
        }.flatMap { $0 }
    }

    // MARK: - Query

    func findBy(uuid: String, dbQueue: PCDBQueue) -> UserEpisode? {
        if let grdbQueue = dbQueue as? GRDBQueue {
            return grdbFetchOne(UserEpisode.filter(UserEpisode.Columns.uuid == uuid), in: grdbQueue)
        }

        return loadSingle(query: "SELECT * from \(DataManager.userEpisodeTableName) WHERE uuid = ?", values: [uuid], dbQueue: dbQueue)
    }

    func findByAsync(uuid: String, dbQueue: PCDBQueue) async -> UserEpisode? {
        if let grdbQueue = dbQueue as? GRDBQueue {
            do {
                return try await grdbQueue.dbPool.read { db in
                    try Row.fetchOne(db, UserEpisode.filter(UserEpisode.Columns.uuid == uuid).asRequest(of: Row.self))
                        .map(Self.episodeWithContentType(from:))
                }
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.findByAsync error: \(error)")
                return nil
            }
        }

        let query = "SELECT * from \(DataManager.userEpisodeTableName) WHERE uuid = ?"
        do {
            return try await dbQueue.read { db in
                try self.loadSingle(query: query, values: [uuid], db: db)
            }
        } catch {
            FileLog.shared.addMessage("UserEpisodeDataManager.findByAsync error: \(error)")
            return nil
        }
    }

    func findBy(downloadTaskId: String, dbQueue: PCDBQueue) -> UserEpisode? {
        if let grdbQueue = dbQueue as? GRDBQueue {
            return grdbFetchOne(UserEpisode.filter(UserEpisode.Columns.downloadTaskId == downloadTaskId), in: grdbQueue)
        }

        return loadSingle(query: "SELECT * from \(DataManager.userEpisodeTableName) WHERE downloadTaskId = ?", values: [downloadTaskId], dbQueue: dbQueue)
    }

    func findBy(uploadTaskId: String, dbQueue: PCDBQueue) -> UserEpisode? {
        if let grdbQueue = dbQueue as? GRDBQueue {
            return grdbFetchOne(UserEpisode.filter(UserEpisode.Columns.uploadTaskId == uploadTaskId), in: grdbQueue)
        }

        return loadSingle(query: "SELECT * from \(DataManager.userEpisodeTableName) WHERE uploadTaskId = ?", values: [uploadTaskId], dbQueue: dbQueue)
    }

    func findAll(sortedBy: UploadedSort, limit: Int? = nil, dbQueue: PCDBQueue) -> [UserEpisode] {
        if let grdbQueue = dbQueue as? GRDBQueue {
            var request = UserEpisode
                .filter(UserEpisode.Columns.uploadStatus != UploadStatus.deleteFromCloudPending.rawValue)
                .filter(UserEpisode.Columns.uploadStatus != UploadStatus.deleteFromCloudAndLocalPending.rawValue)
                .order(Self.ordering(for: sortedBy))
            if let limit {
                request = request.limit(limit)
            }
            return grdbFetchAll(request, in: grdbQueue)
        }

        let whereClause = "WHERE uploadStatus != \(UploadStatus.deleteFromCloudPending.rawValue) AND uploadStatus != \(UploadStatus.deleteFromCloudAndLocalPending.rawValue)"
        var limitClause = ""
        if let limit {
            limitClause = " LIMIT \(limit)"
        }
        switch sortedBy {
        case .newestToOldest:
            return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) \(whereClause) ORDER BY addedDate DESC\(limitClause)", values: nil, dbQueue: dbQueue)
        case .oldestToNewest:
            return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) \(whereClause) ORDER BY addedDate ASC\(limitClause)", values: nil, dbQueue: dbQueue)
        case .titleAtoZ:
            return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) \(whereClause) ORDER BY LOWER(title) ASC\(limitClause)", values: nil, dbQueue: dbQueue)
        case .titleZtoA:
            return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) \(whereClause) ORDER BY LOWER(title) DESC\(limitClause)", values: nil, dbQueue: dbQueue)
        case .shortestToLongest:
            return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) \(whereClause) ORDER BY duration ASC\(limitClause)", values: nil, dbQueue: dbQueue)
        case .longestToShortest:
            return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) \(whereClause) ORDER BY duration DESC\(limitClause)", values: nil, dbQueue: dbQueue)
        }
    }

    /// The query-interface ordering matching the legacy ORDER BY clauses
    /// (`LOWER(title)` for the title sorts, matching SQLite's ASCII case folding).
    private static func ordering(for sortedBy: UploadedSort) -> [any SQLOrderingTerm] {
        switch sortedBy {
        case .newestToOldest:
            return [UserEpisode.Columns.addedDate.desc]
        case .oldestToNewest:
            return [UserEpisode.Columns.addedDate.asc]
        case .titleAtoZ:
            return [UserEpisode.Columns.title.lowercased.asc]
        case .titleZtoA:
            return [UserEpisode.Columns.title.lowercased.desc]
        case .shortestToLongest:
            return [UserEpisode.Columns.duration.asc]
        case .longestToShortest:
            return [UserEpisode.Columns.duration.desc]
        }
    }

    func findAllDownloaded(sortedBy: UploadedSort, limit: Int? = nil, dbQueue: PCDBQueue) -> [UserEpisode] {
        if let grdbQueue = dbQueue as? GRDBQueue {
            var request = UserEpisode
                .filter(UserEpisode.Columns.episodeStatus == DownloadStatus.downloaded.rawValue)
                .order(Self.ordering(for: sortedBy))
            if let limit {
                request = request.limit(limit)
            }
            return grdbFetchAll(request, in: grdbQueue)
        }

        var limitClause = ""
        if let limit {
            limitClause = " LIMIT \(limit)"
        }

        switch sortedBy {
        case .newestToOldest:
            return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) WHERE episodeStatus = ? ORDER BY addedDate DESC\(limitClause)", values: [DownloadStatus.downloaded.rawValue], dbQueue: dbQueue)
        case .oldestToNewest:
            return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) WHERE episodeStatus = ? ORDER BY addedDate ASC\(limitClause)", values: [DownloadStatus.downloaded.rawValue], dbQueue: dbQueue)
        case .titleAtoZ:
            return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) WHERE episodeStatus = ? ORDER BY LOWER(title) ASC\(limitClause)", values: [DownloadStatus.downloaded.rawValue], dbQueue: dbQueue)
        case .titleZtoA:
            return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) WHERE episodeStatus = ? ORDER BY LOWER(title) DESC\(limitClause)", values: [DownloadStatus.downloaded.rawValue], dbQueue: dbQueue)
        case .shortestToLongest:
            return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) WHERE episodeStatus = ? ORDER BY duration ASC\(limitClause)", values: [DownloadStatus.downloaded.rawValue], dbQueue: dbQueue)
        case .longestToShortest:
            return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) WHERE episodeStatus = ? ORDER BY duration DESC\(limitClause)", values: [DownloadStatus.downloaded.rawValue], dbQueue: dbQueue)
        }
    }

    func findAllWithUploadStatus(_ status: UploadStatus, dbQueue: PCDBQueue) -> [UserEpisode] {
        if let grdbQueue = dbQueue as? GRDBQueue {
            return grdbFetchAll(UserEpisode.filter(UserEpisode.Columns.uploadStatus == status.rawValue), in: grdbQueue)
        }

        return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) WHERE uploadStatus = ?", values: [status.rawValue], dbQueue: dbQueue)
    }

    func removeOrphaned(dbQueue: PCDBQueue) {
        if let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.deleteAll(
                UserEpisode.self,
                filter: UserEpisode.Columns.uploadStatus == UploadStatus.notUploaded.rawValue
                    && (UserEpisode.Columns.episodeStatus == DownloadStatus.notDownloaded.rawValue || UserEpisode.Columns.episodeStatus == DownloadStatus.downloadFailed.rawValue)
            )
            return
        }

        dbQueue.write { db in
            do {
                try db.executeUpdate("DELETE FROM \(DataManager.userEpisodeTableName) WHERE uploadStatus = ? AND  ( episodeStatus = ? OR episodeStatus = ? ) ", values: [UploadStatus.notUploaded.rawValue, DownloadStatus.notDownloaded.rawValue, DownloadStatus.downloadFailed.rawValue])
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.removeOrphaned fieldname error: \(error)")
            }
        }
    }

    func unsyncedEpisodes(dbQueue: PCDBQueue) -> [UserEpisode] {
        if let grdbQueue = dbQueue as? GRDBQueue {
            return grdbFetchAll(
                UserEpisode.filter(
                    UserEpisode.Columns.titleModified > 0
                        || UserEpisode.Columns.imageColorModified > 0
                        || UserEpisode.Columns.playingStatusModified > 0
                        || UserEpisode.Columns.playedUpToModified > 0
                        || UserEpisode.Columns.durationModified > 0
                ),
                in: grdbQueue
            )
        }

        return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) WHERE titleModified > 0 OR imageColorModified > 0 OR playingStatusModified > 0 OR playedUpToModified > 0 OR durationModified > 0", values: nil, dbQueue: dbQueue)
    }

    func findWhereNotNull(columnName: String, dbQueue: PCDBQueue) -> [UserEpisode] {
        if let grdbQueue = dbQueue as? GRDBQueue {
            return grdbFetchAll(UserEpisode.filter(Column(columnName) != nil), in: grdbQueue)
        }

        return loadMultiple(query: "SELECT * from \(DataManager.userEpisodeTableName) WHERE \(columnName) IS NOT NULL", values: nil, dbQueue: dbQueue)
    }

    func allUpNextEpisodes(dbQueue: PCDBQueue) -> [UserEpisode] {
        if let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.read { db in
                // Two-step equivalent of the legacy INNER JOIN, ordered by queue position;
                // duplicates and missing episodes behave the same via the dictionary lookup
                let queueRows = try Table(DataManager.playlistEpisodeTableName)
                    .filter(Column("playlist_id") == UpNextDataManager.upNextPlaylistId)
                    .order(Column("episodePosition").asc)
                    .fetchAll(db)
                let uuids = queueRows.map { $0["episodeUuid"] as String }

                let episodes = try Row
                    .fetchAll(db, UserEpisode.filter(uuids.contains(UserEpisode.Columns.uuid)).asRequest(of: Row.self))
                    .map(Self.episodeWithContentType(from:))
                let episodesByUuid = Dictionary(episodes.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })

                return uuids.compactMap { episodesByUuid[$0] }
            } ?? []
        }

        let upNextTableName = DataManager.playlistEpisodeTableName
        let userEpisodeTableName = DataManager.userEpisodeTableName
        return loadMultiple(
            query: """
            SELECT \(userEpisodeTableName).*
            FROM \(upNextTableName)
            JOIN \(userEpisodeTableName)
            ON \(userEpisodeTableName).uuid = \(upNextTableName).episodeUuid
            WHERE \(upNextTableName).playlist_id = ?
            ORDER BY \(upNextTableName).episodePosition ASC
            """,
            values: [UpNextDataManager.upNextPlaylistId],
            dbQueue: dbQueue
        )
    }

    private func loadSingle(query: String, values: [Any]?, dbQueue: PCDBQueue) -> UserEpisode? {
        var episode: UserEpisode?
        dbQueue.read { db in
            do {
                episode = try self.loadSingle(query: query, values: values, db: db)
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.loadSingle error: \(error)")
            }
        }

        return episode
    }

    private func loadSingle(query: String, values: [Any]?, db: PCDatabase) throws -> UserEpisode? {
        let resultSet = try db.executeQuery(query, values: values)
        defer { resultSet.close() }

        return resultSet.next() ? createEpisodeFrom(resultSet: resultSet) : nil
    }

    func findFrameCount(episodeId: Int64, dbQueue: PCDBQueue) -> Int64 {
        if let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.fetchOne(UserEpisode.filter(UserEpisode.Columns.id == episodeId))?.cachedFrameCount ?? 0
        }

        var frameCount = 0 as Int64

        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery("SELECT cachedFrameCount from \(DataManager.userEpisodeTableName) WHERE id = ?", values: [episodeId])
                defer { resultSet.close() }

                if resultSet.next() {
                    frameCount = resultSet.longLongInt(forColumn: "cachedFrameCount")
                }
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.findFrameCount error: \(error)")
            }
        }

        return frameCount
    }

    private func loadMultiple(query: String, values: [Any]?, dbQueue: PCDBQueue) -> [UserEpisode] {
        var episodes = [UserEpisode]()
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery(query, values: values)
                defer { resultSet.close() }

                while resultSet.next() {
                    let episode = self.createEpisodeFrom(resultSet: resultSet)
                    episodes.append(episode)
                }
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.loadMultiple error: \(error)")
            }
        }

        return episodes
    }

    func downloadedEpisodeCount(dbQueue: PCDBQueue) -> Int {
        if let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.count(UserEpisode.self, filter: UserEpisode.Columns.episodeStatus == DownloadStatus.downloaded.rawValue)
        }

        var count = 0
        let query = "SELECT COUNT(*) as Count from \(DataManager.userEpisodeTableName) WHERE episodeStatus = \(DownloadStatus.downloaded.rawValue)"
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery(query, values: nil)
                defer { resultSet.close() }

                if resultSet.next() {
                    count = Int(resultSet.int(forColumn: "Count"))
                }
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.downloadedEpisodeCount error: \(error)")
            }
        }
        return count
    }

    // MARK: - Updates

    func save(episode: UserEpisode, dbQueue: PCDBQueue) {
        let isInsert = episode.id == 0
        if isInsert {
            episode.id = DBUtils.generateUniqueId()
        }

        if let grdbQueue = dbQueue as? GRDBQueue {
            // GRDB path using PersistableRecord
            do {
                try grdbQueue.dbPool.write { db in
                    try episode.save(db)
                }
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.save error: \(error)")
            }
        } else {
            // Legacy path
            dbQueue.write { db in
                do {
                    if isInsert {
                        try db.executeUpdate("INSERT INTO \(DataManager.userEpisodeTableName) (\(self.columnNames.joined(separator: ","))) VALUES \(DBUtils.valuesQuestionMarks(amount: self.columnNames.count))", values: self.createValuesFrom(episode: episode))
                    } else {
                        let setStatement = "\(self.columnNames.joined(separator: " = ?, ")) = ?"
                        try db.executeUpdate("UPDATE \(DataManager.userEpisodeTableName) SET \(setStatement) WHERE id = ?", values: self.createValuesFrom(episode: episode, includeIdForWhere: true))
                    }
                } catch {
                    FileLog.shared.addMessage("UserEpisodeDataManager.save error: \(error)")
                }
            }
        }
    }

    func saveEpisodeSyncInfo(uuid: String, duration: Int?, playingStatus: Int?, playedUpTo: Int?, dbQueue: PCDBQueue) {
        var fields = [String]()
        var values = [Any]()

        if let duration, duration > 0 {
            fields.append("duration")
            values.append(duration)
        }

        // this field defaults to non-null 0, which is not a valid playing status so we need to handle this
        if let playingStatus {
            let status = PlayingStatus(rawValue: Int32(playingStatus)) ?? .notPlayed
            let actualStatus = Int(status.rawValue)
            fields.append("playingStatus")
            values.append(actualStatus)
        } else {
            fields.append("playingStatus")
            values.append(PlayingStatus.notPlayed.rawValue)
        }

        if let playedUpTo, playedUpTo > 0 {
            fields.append("playedUpTo")
            values.append(playedUpTo)
        }

        values.append(uuid)

        save(fields: fields, values: values, useId: false, dbQueue: dbQueue)
    }

    func saveEpisode(playingStatus: PlayingStatus, episode: UserEpisode, updateSyncFlag: Bool, dbQueue: PCDBQueue) {
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

    func saveEpisode(downloadStatus: DownloadStatus, sizeInBytes: Int64, downloadTaskId: String?, episode: UserEpisode, dbQueue: PCDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        episode.sizeInBytes = sizeInBytes
        episode.downloadTaskId = downloadTaskId

        let fields = ["episodeStatus", "sizeInBytes", "downloadTaskId"]
        let values = [episode.episodeStatus, episode.sizeInBytes, DBUtils.replaceNilWithNull(value: episode.downloadTaskId), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, downloadError: String?, downloadTaskId: String?, episode: UserEpisode, dbQueue: PCDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        episode.downloadErrorDetails = downloadError
        episode.downloadTaskId = downloadTaskId

        let fields = ["episodeStatus", "downloadErrorDetails", "downloadTaskId"]
        let values = [episode.episodeStatus, DBUtils.replaceNilWithNull(value: episode.downloadErrorDetails), DBUtils.replaceNilWithNull(value: episode.downloadTaskId), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(autoDownloadStatus: AutoDownloadStatus, episode: UserEpisode, dbQueue: PCDBQueue) {
        episode.autoDownloadStatus = autoDownloadStatus.rawValue
        save(fieldName: "autoDownloadStatus", value: episode.autoDownloadStatus, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, downloadTaskId: String?, episode: UserEpisode, dbQueue: PCDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        episode.downloadTaskId = downloadTaskId

        let fields = ["episodeStatus", "downloadTaskId"]
        let values = [episode.episodeStatus, DBUtils.replaceNilWithNull(value: episode.downloadTaskId), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(uploadStatus: UploadStatus, episode: UserEpisode, dbQueue: PCDBQueue) {
        episode.uploadStatus = uploadStatus.rawValue

        let fields = ["uploadStatus"]
        let values = [episode.uploadStatus, episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(uploadStatus: UploadStatus, uploadTaskId: String?, episode: UserEpisode, dbQueue: PCDBQueue) {
        episode.uploadStatus = uploadStatus.rawValue
        episode.downloadTaskId = uploadTaskId

        let fields = ["uploadStatus", "uploadTaskId"]
        let values = [episode.uploadStatus, DBUtils.replaceNilWithNull(value: episode.uploadTaskId), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(uploadStatus: UploadStatus, uploadError: String?, uploadTaskId: String?, episode: UserEpisode, dbQueue: PCDBQueue) {
        episode.uploadStatus = uploadStatus.rawValue
        episode.uploadTaskId = uploadTaskId

        let fields = ["uploadStatus", "uploadTaskId"]
        let values = [episode.uploadStatus, DBUtils.replaceNilWithNull(value: episode.uploadTaskId), episode.id] as [Any]
        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(duration: Double, episode: UserEpisode, dbQueue: PCDBQueue) {
        episode.duration = duration

        save(fieldName: "duration", value: episode.duration, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveEpisode(playbackError: String?, episode: UserEpisode, dbQueue: PCDBQueue) {
        episode.playbackErrorDetails = playbackError
        save(fieldName: "playbackErrorDetails", value: DBUtils.replaceNilWithNull(value: episode.playbackErrorDetails), episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, sizeInBytes: Int64, episode: UserEpisode, dbQueue: PCDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        episode.sizeInBytes = sizeInBytes

        let fields = ["episodeStatus", "sizeInBytes"]
        let values = [episode.episodeStatus, episode.sizeInBytes, episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, lastDownloadAttemptDate: Date, autoDownloadStatus: AutoDownloadStatus, episode: UserEpisode, dbQueue: PCDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        episode.lastDownloadAttemptDate = lastDownloadAttemptDate
        episode.autoDownloadStatus = autoDownloadStatus.rawValue

        let fields = ["episodeStatus", "lastDownloadAttemptDate", "autoDownloadStatus"]
        let values = [episode.episodeStatus, DBUtils.replaceNilWithNull(value: episode.lastDownloadAttemptDate), episode.autoDownloadStatus, episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveContentType(contentType: String, episode: UserEpisode, dbQueue: PCDBQueue) {
        episode.contentType = contentType
        save(fieldName: "contentType", value: contentType, episodeId: episode.id, dbQueue: dbQueue)
    }

    func bulkSave(episodes: [UserEpisode], dbQueue: PCDBQueue) {
        if let grdbQueue = dbQueue as? GRDBQueue {
            // GRDB path using PersistableRecord
            do {
                try grdbQueue.dbPool.write { db in
                    for episode in episodes {
                        let isInsert = episode.id == 0
                        if isInsert {
                            episode.id = DBUtils.generateUniqueId()
                        }

                        try episode.save(db)
                    }
                }
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.bulkSave error: \(error)")
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
                            try db.executeUpdate("INSERT INTO \(DataManager.userEpisodeTableName) (\(self.columnNames.joined(separator: ","))) VALUES \(DBUtils.valuesQuestionMarks(amount: self.columnNames.count))", values: self.createValuesFrom(episode: episode))
                        } else {
                            let setStatement = "\(self.columnNames.joined(separator: " = ?, ")) = ?"
                            try db.executeUpdate("UPDATE \(DataManager.userEpisodeTableName) SET \(setStatement) WHERE id = ?", values: self.createValuesFrom(episode: episode, includeIdForWhere: true))
                        }
                    }

                    db.commit()
                } catch {
                    FileLog.shared.addMessage("UserEpisodeDataManager.bulkSave error: \(error)")
                }
            }
        }
    }

    func bulkMarkAsPlayed(episodes: [UserEpisode], updateSyncFlag: Bool, dbQueue: PCDBQueue) {
        if episodes.isEmpty { return }

        if let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.write { db in
                for episode in episodes {
                    if episode.playingStatus == PlayingStatus.completed.rawValue { continue }

                    var assignments = [UserEpisode.Columns.playingStatus.set(to: PlayingStatus.completed.rawValue)]
                    if updateSyncFlag {
                        assignments.append(UserEpisode.Columns.playingStatusModified.set(to: DBUtils.currentUTCTimeInMillis()))
                    }

                    try UserEpisode.filter(UserEpisode.Columns.uuid == episode.uuid).updateAll(db, assignments)
                }
            }
            return
        }

        dbQueue.write { db in
            do {
                db.beginTransaction()

                for episode in episodes {
                    if episode.playingStatus == PlayingStatus.completed.rawValue { continue }

                    var fields = [String]()
                    var values = [Any]()

                    fields.append("playingStatus")
                    values.append(PlayingStatus.completed.rawValue)

                    if updateSyncFlag {
                        fields.append("playingStatusModified")
                        values.append(DBUtils.currentUTCTimeInMillis())
                    }

                    values.append(episode.uuid)
                    let setStatement = "SET \(fields.joined(separator: " = ?, ")) = ?"
                    try db.executeUpdate("UPDATE \(DataManager.userEpisodeTableName) \(setStatement) WHERE uuid = ?", values: values)
                }
                db.commit()
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.bulkMarkAsPlayed error: \(error)")
            }
        }
    }

    func bulkMarkAsUnPlayed(episodes: [UserEpisode], updateSyncFlag: Bool, dbQueue: PCDBQueue) {
        if episodes.isEmpty { return }

        if let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.write { db in
                for episode in episodes {
                    if episode.playingStatus == PlayingStatus.notPlayed.rawValue { continue }

                    var assignments = [
                        UserEpisode.Columns.playingStatus.set(to: PlayingStatus.notPlayed.rawValue),
                        UserEpisode.Columns.playedUpTo.set(to: 0)
                    ]
                    if updateSyncFlag {
                        assignments.append(UserEpisode.Columns.playingStatusModified.set(to: DBUtils.currentUTCTimeInMillis()))
                    }

                    try UserEpisode.filter(UserEpisode.Columns.uuid == episode.uuid).updateAll(db, assignments)
                }
            }
            return
        }

        dbQueue.write { db in
            do {
                db.beginTransaction()

                for episode in episodes {
                    if episode.playingStatus == PlayingStatus.notPlayed.rawValue { continue }

                    var fields = [String]()
                    var values = [Any]()

                    fields.append("playingStatus")
                    values.append(PlayingStatus.notPlayed.rawValue)
                    fields.append("playedUpTo")
                    values.append(0)
                    if updateSyncFlag {
                        fields.append("playingStatusModified")
                        values.append(DBUtils.currentUTCTimeInMillis())
                    }

                    values.append(episode.uuid)
                    let setStatement = "SET \(fields.joined(separator: " = ?, ")) = ?"
                    try db.executeUpdate("UPDATE \(DataManager.userEpisodeTableName) \(setStatement) WHERE uuid = ?", values: values)
                }
                db.commit()
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.bulkMarkAsUnPlayed error: \(error)")
            }
        }
    }

    func bulkUserFileDelete(episodes: [UserEpisode], dbQueue: PCDBQueue) {
        if episodes.isEmpty { return }

        if let grdbQueue = dbQueue as? GRDBQueue {
            let uuids = episodes.map(\.uuid)
            grdbQueue.write { db in
                try UserEpisode.filter(uuids.contains(UserEpisode.Columns.uuid)).updateAll(
                    db,
                    UserEpisode.Columns.episodeStatus.set(to: DownloadStatus.notDownloaded.rawValue),
                    UserEpisode.Columns.autoDownloadStatus.set(to: AutoDownloadStatus.userDeletedFile.rawValue),
                    UserEpisode.Columns.cachedFrameCount.set(to: 0)
                )
            }
            return
        }

        dbQueue.write { db in
            do {
                db.beginTransaction()

                for episode in episodes {
                    var fields = [String]()
                    var values = [Any]()

                    fields.append("episodeStatus")
                    values.append(DownloadStatus.notDownloaded.rawValue)
                    fields.append("autoDownloadStatus")
                    values.append(AutoDownloadStatus.userDeletedFile.rawValue)
                    fields.append("cachedFrameCount")
                    values.append(0)
                    values.append(episode.uuid)

                    let setStatement = "SET \(fields.joined(separator: " = ?, ")) = ?"
                    try db.executeUpdate("UPDATE \(DataManager.userEpisodeTableName) \(setStatement) WHERE uuid = ?", values: values)
                }
                db.commit()
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.bulkUserFileDelete error: \(error)")
            }
        }
    }

    func clearDownloadTaskId(episode: UserEpisode, dbQueue: PCDBQueue) {
        save(fieldName: "downloadTaskId", value: NSNull(), episodeId: episode.id, dbQueue: dbQueue)
    }

    func clearUploadTaskId(episode: UserEpisode, dbQueue: PCDBQueue) {
        save(fieldName: "uploadTaskId", value: NSNull(), episodeId: episode.id, dbQueue: dbQueue)
    }

    func delete(userEpisodeUuid: String, dbQueue: PCDBQueue) {
        if let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.deleteAll(UserEpisode.self, filter: UserEpisode.Columns.uuid == userEpisodeUuid)
            return
        }

        dbQueue.write { db in
            do {
                try db.executeUpdate("DELETE FROM \(DataManager.userEpisodeTableName) WHERE uuid = ?", values: [userEpisodeUuid])
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.delete error: \(error)")
            }
        }
    }

    func delete(userEpisodeUuids: [String], dbQueue: PCDBQueue) {
        guard !userEpisodeUuids.isEmpty else { return }

        if let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.deleteAll(UserEpisode.self, filter: userEpisodeUuids.contains(UserEpisode.Columns.uuid))
            return
        }

        dbQueue.write { db in
            do {
                try db.executeUpdate("DELETE FROM \(DataManager.userEpisodeTableName) WHERE uuid IN (\(DBUtils.placeholders(amount: userEpisodeUuids.count)))", values: userEpisodeUuids)
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.delete many error: \(error)")
            }
        }
    }

    func saveFrameCount(episodeId: Int64, frameCount: Int64, dbQueue: PCDBQueue) {
        save(fieldName: "cachedFrameCount", value: frameCount, episodeId: episodeId, dbQueue: dbQueue)
    }

    func saveEpisode(playedUpTo: Double, episode: UserEpisode, updateSyncFlag: Bool, dbQueue: PCDBQueue) {
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

    func markEpisodeImageUploaded(episode: UserEpisode, dbQueue: PCDBQueue) {
        episode.imageModified = 0
        episode.imageUrl = nil

        let fields = ["imageModified", "imageUrl"]
        let values = [episode.imageModified, DBUtils.replaceNilWithNull(value: episode.imageUrl), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    private func save(fieldName: String, value: Any, episodeId: Int64, dbQueue: PCDBQueue) {
        if let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.write { db in
                try UserEpisode
                    .filter(UserEpisode.Columns.id == episodeId)
                    .updateAll(db, Column(fieldName).set(to: Self.databaseValue(from: value)))
            }
            return
        }

        dbQueue.write { db in
            do {
                try db.executeUpdate("UPDATE \(DataManager.userEpisodeTableName) SET \(fieldName) = ? WHERE id = ?", values: [value, episodeId])
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.save fieldname error: \(error)")
            }
        }
    }

    private func save(fields: [String], values: [Any], useId: Bool = true, dbQueue: PCDBQueue) {
        if let grdbQueue = dbQueue as? GRDBQueue {
            // The last value is the id/uuid used by the WHERE clause, mirroring the legacy layout
            guard values.count == fields.count + 1, let identifier = values.last else { return }

            grdbQueue.write { db in
                let assignments = zip(fields, values).map { field, value in
                    Column(field).set(to: Self.databaseValue(from: value))
                }
                let filter: SQLSpecificExpressible = useId
                    ? UserEpisode.Columns.id == Self.databaseValue(from: identifier)
                    : UserEpisode.Columns.uuid == Self.databaseValue(from: identifier)

                try UserEpisode.filter(filter).updateAll(db, assignments)
            }
            return
        }

        dbQueue.write { db in
            do {
                let setStatement = "SET \(fields.joined(separator: " = ?, ")) = ?"
                let idColumn = useId ? "id" : "uuid"
                try db.executeUpdate("UPDATE \(DataManager.userEpisodeTableName) \(setStatement) WHERE \(idColumn) = ?", values: values)
            } catch {
                FileLog.shared.addMessage("UserEpisodeDataManager.save fieldnames error: \(error)")
            }
        }
    }

    /// Converts the legacy `[Any]` binding values for the GRDB path, matching the legacy shim's
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

    // MARK: - Conversion

    private func createEpisodeFrom(resultSet rs: PCDBResultSet) -> UserEpisode {
        let episode = UserEpisode()
        episode.id = rs.longLongInt(forColumn: "id")
        episode.addedDate = DBUtils.convertDate(value: rs.double(forColumn: "addedDate"))
        episode.lastDownloadAttemptDate = DBUtils.convertDate(value: rs.double(forColumn: "lastDownloadAttemptDate"))
        episode.downloadErrorDetails = rs.string(forColumn: "downloadErrorDetails")
        episode.downloadTaskId = rs.string(forColumn: "downloadTaskId")
        episode.downloadUrl = rs.string(forColumn: "downloadUrl")
        episode.episodeStatus = rs.int(forColumn: "episodeStatus")
        episode.fileType = rs.string(forColumn: "fileType")
        episode.contentType = rs.string(forColumn: "contentType")
        episode.playedUpTo = rs.double(forColumn: "playedUpTo")
        episode.duration = rs.double(forColumn: "duration")
        episode.durationModified = rs.longLongInt(forColumn: "durationModified")
        episode.playingStatus = rs.int(forColumn: "playingStatus")
        episode.autoDownloadStatus = rs.int(forColumn: "autoDownloadStatus")
        episode.publishedDate = DBUtils.convertDate(value: rs.double(forColumn: "publishedDate"))
        episode.sizeInBytes = rs.longLongInt(forColumn: "sizeInBytes")
        episode.playingStatusModified = rs.longLongInt(forColumn: "playingStatusModified")
        episode.playedUpToModified = rs.longLongInt(forColumn: "playedUpToModified")
        episode.title = rs.string(forColumn: "title")
        episode.titleModified = rs.longLongInt(forColumn: "titleModified")
        episode.uuid = DBUtils.nonNilStringFromColumn(resultSet: rs, columnName: "uuid")
        episode.playbackErrorDetails = rs.string(forColumn: "playbackErrorDetails")
        episode.cachedFrameCount = rs.longLongInt(forColumn: "cachedFrameCount")
        episode.uploadStatus = rs.int(forColumn: "uploadStatus")
        episode.uploadTaskId = rs.string(forColumn: "uploadTaskId")
        episode.imageUrl = rs.string(forColumn: "imageUrl")
        episode.imageModified = rs.longLongInt(forColumn: "imageModified")
        episode.imageColor = rs.int(forColumn: "imageColor")
        episode.imageColorModified = rs.longLongInt(forColumn: "imageColorModified")
        episode.hasCustomImage = rs.bool(forColumn: "hasCustomImage")
        return episode
    }

    private func createValuesFrom(episode: UserEpisode, includeIdForWhere: Bool = false) -> [Any] {
        var values = [Any]()
        values.append(episode.id)
        values.append(DBUtils.nullIfNil(value: episode.addedDate))
        values.append(episode.lastDownloadAttemptDate ?? Date(timeIntervalSince1970: 0))
        values.append(DBUtils.nullIfNil(value: episode.downloadErrorDetails))
        values.append(DBUtils.nullIfNil(value: episode.downloadTaskId))
        values.append(DBUtils.nullIfNil(value: episode.downloadUrl))
        values.append(episode.episodeStatus)
        values.append(DBUtils.nullIfNil(value: episode.fileType))
        values.append(episode.playedUpTo)
        values.append(episode.duration)
        values.append(episode.playingStatus)
        values.append(episode.autoDownloadStatus)
        values.append(DBUtils.nullIfNil(value: episode.publishedDate))
        values.append(episode.sizeInBytes)
        values.append(episode.playingStatusModified)
        values.append(episode.playedUpToModified)
        values.append(DBUtils.nullIfNil(value: episode.title))
        values.append(episode.uuid)
        values.append(DBUtils.nullIfNil(value: episode.playbackErrorDetails))
        values.append(episode.cachedFrameCount)
        values.append(episode.uploadStatus)
        values.append(DBUtils.nullIfNil(value: episode.uploadTaskId))
        values.append(DBUtils.nullIfNil(value: episode.imageUrl))
        values.append(episode.imageColor)
        values.append(episode.hasCustomImage)
        values.append(episode.imageColorModified)
        values.append(episode.titleModified)
        values.append(episode.durationModified)
        values.append(episode.imageModified)

        if includeIdForWhere {
            values.append(episode.id)
        }

        return values
    }
}
