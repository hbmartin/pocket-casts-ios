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

    private func grdbFetchAll(_ request: QueryInterfaceRequest<UserEpisode>, in dbQueue: GRDBQueue) -> [UserEpisode] {
        dbQueue.read { db in
            try Row.fetchAll(db, request.asRequest(of: Row.self)).map(Self.episodeWithContentType(from:))
        } ?? []
    }

    private func grdbFetchOne(_ request: QueryInterfaceRequest<UserEpisode>, in dbQueue: GRDBQueue) -> UserEpisode? {
        // read's result is doubly optional (nil on error, inner nil for no row); flatten both to nil
        dbQueue.read { db in
            try Row.fetchOne(db, request.asRequest(of: Row.self)).map(Self.episodeWithContentType(from:))
        }.flatMap { $0 }
    }

    // MARK: - Query

    func findBy(uuid: String, dbQueue: GRDBQueue) -> UserEpisode? {
        return grdbFetchOne(UserEpisode.filter(UserEpisode.Columns.uuid == uuid), in: dbQueue)
    }

    func findByAsync(uuid: String, dbQueue: GRDBQueue) async -> UserEpisode? {
        do {
            return try await dbQueue.dbPool.read { db in
                try Row.fetchOne(db, UserEpisode.filter(UserEpisode.Columns.uuid == uuid).asRequest(of: Row.self))
                    .map(Self.episodeWithContentType(from:))
            }
        } catch {
            FileLog.shared.addMessage("UserEpisodeDataManager.findByAsync error: \(error)")
            return nil
        }
    }

    func findBy(downloadTaskId: String, dbQueue: GRDBQueue) -> UserEpisode? {
        return grdbFetchOne(UserEpisode.filter(UserEpisode.Columns.downloadTaskId == downloadTaskId), in: dbQueue)
    }

    func findBy(uploadTaskId: String, dbQueue: GRDBQueue) -> UserEpisode? {
        return grdbFetchOne(UserEpisode.filter(UserEpisode.Columns.uploadTaskId == uploadTaskId), in: dbQueue)
    }

    func findAll(sortedBy: UploadedSort, limit: Int? = nil, dbQueue: GRDBQueue) -> [UserEpisode] {
        var request = UserEpisode
            .filter(UserEpisode.Columns.uploadStatus != UploadStatus.deleteFromCloudPending.rawValue)
            .filter(UserEpisode.Columns.uploadStatus != UploadStatus.deleteFromCloudAndLocalPending.rawValue)
            .order(Self.ordering(for: sortedBy))
        if let limit {
            request = request.limit(limit)
        }
        return grdbFetchAll(request, in: dbQueue)
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

    func findAllDownloaded(sortedBy: UploadedSort, limit: Int? = nil, dbQueue: GRDBQueue) -> [UserEpisode] {
        var request = UserEpisode
            .filter(UserEpisode.Columns.episodeStatus == DownloadStatus.downloaded.rawValue)
            .order(Self.ordering(for: sortedBy))
        if let limit {
            request = request.limit(limit)
        }
        return grdbFetchAll(request, in: dbQueue)
    }

    func findAllWithUploadStatus(_ status: UploadStatus, dbQueue: GRDBQueue) -> [UserEpisode] {
        return grdbFetchAll(UserEpisode.filter(UserEpisode.Columns.uploadStatus == status.rawValue), in: dbQueue)
    }

    func removeOrphaned(dbQueue: GRDBQueue) {
        dbQueue.deleteAll(
            UserEpisode.self,
            filter: UserEpisode.Columns.uploadStatus == UploadStatus.notUploaded.rawValue
                && (UserEpisode.Columns.episodeStatus == DownloadStatus.notDownloaded.rawValue || UserEpisode.Columns.episodeStatus == DownloadStatus.downloadFailed.rawValue)
        )
    }

    func unsyncedEpisodes(dbQueue: GRDBQueue) -> [UserEpisode] {
        return grdbFetchAll(
            UserEpisode.filter(
                UserEpisode.Columns.titleModified > 0
                    || UserEpisode.Columns.imageColorModified > 0
                    || UserEpisode.Columns.playingStatusModified > 0
                    || UserEpisode.Columns.playedUpToModified > 0
                    || UserEpisode.Columns.durationModified > 0
            ),
            in: dbQueue
        )
    }

    func findWhereNotNull(columnName: String, dbQueue: GRDBQueue) -> [UserEpisode] {
        return grdbFetchAll(UserEpisode.filter(Column(columnName) != nil), in: dbQueue)
    }

    func allUpNextEpisodes(dbQueue: GRDBQueue) -> [UserEpisode] {
        return dbQueue.read { db in
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

    private func loadSingle(query: String, values: [Any]?, dbQueue: GRDBQueue) -> UserEpisode? {
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
        let resultSet = try db.executeQuery(query, values: values) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - caller-supplied-SQL API plumbing (findWhere)
        defer { resultSet.close() }

        return resultSet.next() ? createEpisodeFrom(resultSet: resultSet) : nil
    }

    func findFrameCount(episodeId: Int64, dbQueue: GRDBQueue) -> Int64 {
        return dbQueue.fetchOne(UserEpisode.filter(UserEpisode.Columns.id == episodeId))?.cachedFrameCount ?? 0
    }

    private func loadMultiple(query: String, values: [Any]?, dbQueue: GRDBQueue) -> [UserEpisode] {
        var episodes = [UserEpisode]()
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery(query, values: values) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - caller-supplied-SQL API plumbing (findWhere)
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

    func downloadedEpisodeCount(dbQueue: GRDBQueue) -> Int {
        return dbQueue.count(UserEpisode.self, filter: UserEpisode.Columns.episodeStatus == DownloadStatus.downloaded.rawValue)
    }

    // MARK: - Updates

    func save(episode: UserEpisode, dbQueue: GRDBQueue) {
        let isInsert = episode.id == 0
        if isInsert {
            episode.id = DBUtils.generateUniqueId()
        }

        do {
            try dbQueue.dbPool.write { db in
                try episode.save(db)
            }
        } catch {
            FileLog.shared.addMessage("UserEpisodeDataManager.save error: \(error)")
        }
    }


    func saveEpisode(playingStatus: PlayingStatus, episode: UserEpisode, updateSyncFlag: Bool, dbQueue: GRDBQueue) {
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

    func saveEpisode(downloadStatus: DownloadStatus, sizeInBytes: Int64, downloadTaskId: String?, episode: UserEpisode, dbQueue: GRDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        episode.sizeInBytes = sizeInBytes
        episode.downloadTaskId = downloadTaskId

        let fields = ["episodeStatus", "sizeInBytes", "downloadTaskId"]
        let values = [episode.episodeStatus, episode.sizeInBytes, DBUtils.replaceNilWithNull(value: episode.downloadTaskId), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, downloadError: String?, downloadTaskId: String?, episode: UserEpisode, dbQueue: GRDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        episode.downloadErrorDetails = downloadError
        episode.downloadTaskId = downloadTaskId

        let fields = ["episodeStatus", "downloadErrorDetails", "downloadTaskId"]
        let values = [episode.episodeStatus, DBUtils.replaceNilWithNull(value: episode.downloadErrorDetails), DBUtils.replaceNilWithNull(value: episode.downloadTaskId), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(autoDownloadStatus: AutoDownloadStatus, episode: UserEpisode, dbQueue: GRDBQueue) {
        episode.autoDownloadStatus = autoDownloadStatus.rawValue
        save(fieldName: "autoDownloadStatus", value: episode.autoDownloadStatus, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, downloadTaskId: String?, episode: UserEpisode, dbQueue: GRDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        episode.downloadTaskId = downloadTaskId

        let fields = ["episodeStatus", "downloadTaskId"]
        let values = [episode.episodeStatus, DBUtils.replaceNilWithNull(value: episode.downloadTaskId), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(uploadStatus: UploadStatus, episode: UserEpisode, dbQueue: GRDBQueue) {
        episode.uploadStatus = uploadStatus.rawValue

        let fields = ["uploadStatus"]
        let values = [episode.uploadStatus, episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(uploadStatus: UploadStatus, uploadTaskId: String?, episode: UserEpisode, dbQueue: GRDBQueue) {
        episode.uploadStatus = uploadStatus.rawValue
        episode.downloadTaskId = uploadTaskId

        let fields = ["uploadStatus", "uploadTaskId"]
        let values = [episode.uploadStatus, DBUtils.replaceNilWithNull(value: episode.uploadTaskId), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(uploadStatus: UploadStatus, uploadError: String?, uploadTaskId: String?, episode: UserEpisode, dbQueue: GRDBQueue) {
        episode.uploadStatus = uploadStatus.rawValue
        episode.uploadTaskId = uploadTaskId

        let fields = ["uploadStatus", "uploadTaskId"]
        let values = [episode.uploadStatus, DBUtils.replaceNilWithNull(value: episode.uploadTaskId), episode.id] as [Any]
        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(duration: Double, episode: UserEpisode, dbQueue: GRDBQueue) {
        episode.duration = duration

        save(fieldName: "duration", value: episode.duration, episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveEpisode(playbackError: String?, episode: UserEpisode, dbQueue: GRDBQueue) {
        episode.playbackErrorDetails = playbackError
        save(fieldName: "playbackErrorDetails", value: DBUtils.replaceNilWithNull(value: episode.playbackErrorDetails), episodeId: episode.id, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, sizeInBytes: Int64, episode: UserEpisode, dbQueue: GRDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        episode.sizeInBytes = sizeInBytes

        let fields = ["episodeStatus", "sizeInBytes"]
        let values = [episode.episodeStatus, episode.sizeInBytes, episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveEpisode(downloadStatus: DownloadStatus, lastDownloadAttemptDate: Date, autoDownloadStatus: AutoDownloadStatus, episode: UserEpisode, dbQueue: GRDBQueue) {
        episode.episodeStatus = downloadStatus.rawValue
        episode.lastDownloadAttemptDate = lastDownloadAttemptDate
        episode.autoDownloadStatus = autoDownloadStatus.rawValue

        let fields = ["episodeStatus", "lastDownloadAttemptDate", "autoDownloadStatus"]
        let values = [episode.episodeStatus, DBUtils.replaceNilWithNull(value: episode.lastDownloadAttemptDate), episode.autoDownloadStatus, episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    func saveContentType(contentType: String, episode: UserEpisode, dbQueue: GRDBQueue) {
        episode.contentType = contentType
        save(fieldName: "contentType", value: contentType, episodeId: episode.id, dbQueue: dbQueue)
    }

    func bulkSave(episodes: [UserEpisode], dbQueue: GRDBQueue) {
        do {
            try dbQueue.dbPool.write { db in
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
    }

    func bulkMarkAsPlayed(episodes: [UserEpisode], updateSyncFlag: Bool, dbQueue: GRDBQueue) {
        if episodes.isEmpty { return }

        dbQueue.write { db in
            for episode in episodes {
                if episode.playingStatus == PlayingStatus.completed.rawValue { continue }

                var assignments = [UserEpisode.Columns.playingStatus.set(to: PlayingStatus.completed.rawValue)]
                if updateSyncFlag {
                    assignments.append(UserEpisode.Columns.playingStatusModified.set(to: DBUtils.currentUTCTimeInMillis()))
                }

                try UserEpisode.filter(UserEpisode.Columns.uuid == episode.uuid).updateAll(db, assignments)
            }
        }
    }

    func bulkMarkAsUnPlayed(episodes: [UserEpisode], updateSyncFlag: Bool, dbQueue: GRDBQueue) {
        if episodes.isEmpty { return }

        dbQueue.write { db in
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
    }

    func bulkUserFileDelete(episodes: [UserEpisode], dbQueue: GRDBQueue) {
        if episodes.isEmpty { return }

        let uuids = episodes.map(\.uuid)
        dbQueue.write { db in
            try UserEpisode.filter(uuids.contains(UserEpisode.Columns.uuid)).updateAll(
                db,
                UserEpisode.Columns.episodeStatus.set(to: DownloadStatus.notDownloaded.rawValue),
                UserEpisode.Columns.autoDownloadStatus.set(to: AutoDownloadStatus.userDeletedFile.rawValue),
                UserEpisode.Columns.cachedFrameCount.set(to: 0)
            )
        }
    }

    func clearDownloadTaskId(episode: UserEpisode, dbQueue: GRDBQueue) {
        save(fieldName: "downloadTaskId", value: NSNull(), episodeId: episode.id, dbQueue: dbQueue)
    }

    func clearUploadTaskId(episode: UserEpisode, dbQueue: GRDBQueue) {
        save(fieldName: "uploadTaskId", value: NSNull(), episodeId: episode.id, dbQueue: dbQueue)
    }

    func delete(userEpisodeUuid: String, dbQueue: GRDBQueue) {
        dbQueue.deleteAll(UserEpisode.self, filter: UserEpisode.Columns.uuid == userEpisodeUuid)
    }

    func delete(userEpisodeUuids: [String], dbQueue: GRDBQueue) {
        guard !userEpisodeUuids.isEmpty else { return }

        dbQueue.deleteAll(UserEpisode.self, filter: userEpisodeUuids.contains(UserEpisode.Columns.uuid))
    }

    func saveFrameCount(episodeId: Int64, frameCount: Int64, dbQueue: GRDBQueue) {
        save(fieldName: "cachedFrameCount", value: frameCount, episodeId: episodeId, dbQueue: dbQueue)
    }

    func saveEpisode(playedUpTo: Double, episode: UserEpisode, updateSyncFlag: Bool, dbQueue: GRDBQueue) {
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

    func markEpisodeImageUploaded(episode: UserEpisode, dbQueue: GRDBQueue) {
        episode.imageModified = 0
        episode.imageUrl = nil

        let fields = ["imageModified", "imageUrl"]
        let values = [episode.imageModified, DBUtils.replaceNilWithNull(value: episode.imageUrl), episode.id] as [Any]

        save(fields: fields, values: values, dbQueue: dbQueue)
    }

    private func save(fieldName: String, value: Any, episodeId: Int64, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try UserEpisode
                .filter(UserEpisode.Columns.id == episodeId)
                .updateAll(db, Column(fieldName).set(to: Self.databaseValue(from: value)))
        }
    }

    private func save(fields: [String], values: [Any], useId: Bool = true, dbQueue: GRDBQueue) {
        // The last value is the id/uuid used by the WHERE clause, mirroring the legacy layout
        guard values.count == fields.count + 1, let identifier = values.last else { return }

        dbQueue.write { db in
            let assignments = zip(fields, values).map { field, value in
                Column(field).set(to: Self.databaseValue(from: value))
            }
            let filter: SQLSpecificExpressible = useId
                ? UserEpisode.Columns.id == Self.databaseValue(from: identifier)
                : UserEpisode.Columns.uuid == Self.databaseValue(from: identifier)

            try UserEpisode.filter(filter).updateAll(db, assignments)
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
}
