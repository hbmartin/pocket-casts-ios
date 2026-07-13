import PocketCastsUtils
import Foundation
import GRDB
import GRDBMacros

/// Row record for the `Bookmark` table. Carries `sync_status`, which the public `Bookmark`
/// model doesn't expose. Date columns are raw `timeIntervalSince1970` Doubles to stay
/// byte-identical with the legacy SQL path, which binds dates the same way.
@GRDBRecord(table: "Bookmark")
struct BookmarkRow: Equatable, Sendable {
    var uuid = ""
    var title = ""

    @GRDBColumn("title_modified_date")
    var titleModifiedDate: Double?

    @GRDBColumn("episode_uuid")
    var episodeUuid = ""

    @GRDBColumn("podcast_uuid")
    var podcastUuid: String?

    var time: Double = 0

    @GRDBColumn("date_added")
    var dateAdded: Double = 0

    var deleted = false

    @GRDBColumn("deleted_modified_date")
    var deletedModifiedDate: Double?

    @GRDBColumn("sync_status")
    var syncStatus: Int32 = 0

    var excerpt: String?

    var endTime: Double?

    var asBookmark: Bookmark {
        Bookmark(
            uuid: uuid,
            title: title,
            time: time,
            created: Date(timeIntervalSince1970: dateAdded),
            episodeUuid: episodeUuid,
            podcastUuid: podcastUuid,
            excerpt: excerpt,
            endTime: endTime,
            titleModified: titleModifiedDate.map { Date(timeIntervalSince1970: $0) },
            deletedModified: deletedModifiedDate.map { Date(timeIntervalSince1970: $0) },
            deleted: deleted
        )
    }
}

public struct BookmarkDataManager: Sendable {
    static let tableName = "Bookmark"
    private let dbQueue: GRDBQueue
    private let fileSyncJournalManager: FileSyncJournalDataManager?

    init(dbQueue: GRDBQueue, fileSyncJournalManager: FileSyncJournalDataManager? = nil) {
        self.dbQueue = dbQueue
        self.fileSyncJournalManager = fileSyncJournalManager
    }

    /// Looks for any existing bookmarks in an episode that have the same start time
    public func existingBookmark(forEpisode episodeUuid: String, time: TimeInterval) -> Bookmark? {
        return grdbSelectBookmarks(
            in: dbQueue,
            filters: [BookmarkRow.Columns.episodeUuid == episodeUuid, BookmarkRow.Columns.time == time],
            limit: 1
        ).first
    }

    // MARK: - Adding

    /// Adds a new bookmark to the database
    /// - Parameters:
    ///   - episodeUuid: The UUID of the episode we're adding to
    ///   - podcastUuid: The UUID of the podcast of the episode, can be nil for user episodes
    ///   - time: The playback time for the bookmark
    ///   - transcription: A transcription of the clip if available
    @discardableResult
    public func add(uuid: String? = nil, episodeUuid: String, podcastUuid: String?, title: String, time: TimeInterval, dateCreated: Date = Date(), excerpt: String? = nil, endTime: TimeInterval? = nil, syncStatus: SyncStatus = .notSynced) -> String? {
        var row = BookmarkRow()
        row.uuid = uuid ?? UUID().uuidString.lowercased()
        row.title = title
        row.time = time
        row.dateAdded = dateCreated.timeIntervalSince1970
        row.titleModifiedDate = dateCreated.timeIntervalSince1970
        row.episodeUuid = episodeUuid
        row.podcastUuid = podcastUuid
        row.excerpt = excerpt
        row.endTime = endTime
        row.syncStatus = syncStatus.rawValue
        let rowToSave = row

        let success = dbQueue.write { db in
            try rowToSave.insert(db)
            try recordFileSyncChange(uuid: rowToSave.uuid, isDelete: false, syncStatus: syncStatus, db: db)
        }
        return success ? rowToSave.uuid : nil
    }

    // MARK: - Updating
    @discardableResult
    public func update(bookmark: Bookmark, title: String, time: TimeInterval? = nil, created: Date? = nil, modified: Date? = Date(), syncStatus: SyncStatus = .notSynced) async -> Bool {
        let uuid = bookmark.uuid
        let timeValue = time
        let createdInterval = created?.timeIntervalSince1970
        let modifiedInterval = (modified ?? Date()).timeIntervalSince1970
        let syncStatusValue = syncStatus.rawValue

        let success = dbQueue.write { db in
            var assignments: [ColumnAssignment] = [BookmarkRow.Columns.title.set(to: title)]
            if let timeValue {
                assignments.append(BookmarkRow.Columns.time.set(to: timeValue))
            }
            if let createdInterval {
                assignments.append(BookmarkRow.Columns.dateAdded.set(to: createdInterval))
            }
            assignments.append(BookmarkRow.Columns.titleModifiedDate.set(to: modifiedInterval))
            assignments.append(BookmarkRow.Columns.syncStatus.set(to: syncStatusValue))

            try BookmarkRow.filter(BookmarkRow.Columns.uuid == uuid).updateAll(db, assignments)
            try recordFileSyncChange(uuid: uuid, isDelete: false, syncStatus: syncStatus, db: db)
        }
        if !success { FileLog.shared.addMessage("BookmarkManager.update failed") }
        return success
    }

    /// Writes the smart-highlight enrichment (transcript excerpt + window end) for a
    /// bookmark. Unlike `update`, this doesn't touch the title or its modified date,
    /// so a concurrent rename can't be clobbered.
    @discardableResult
    public func updateEnrichment(uuid: String, excerpt: String?, endTime: TimeInterval?, syncStatus: SyncStatus = .notSynced) async -> Bool {
        let syncStatusValue = syncStatus.rawValue

        let success = dbQueue.write { db in
            try BookmarkRow
                .filter(BookmarkRow.Columns.uuid == uuid)
                .updateAll(db,
                           BookmarkRow.Columns.excerpt.set(to: excerpt),
                           BookmarkRow.Columns.endTime.set(to: endTime),
                           BookmarkRow.Columns.syncStatus.set(to: syncStatusValue))
            try recordFileSyncChange(uuid: uuid, isDelete: false, syncStatus: syncStatus, db: db)
        }
        if !success { FileLog.shared.addMessage("BookmarkDataManager.updateEnrichment failed") }
        return success
    }

    // MARK: - Retrieving

    /// Retrieves a single Bookmark for the given UUID
    public func bookmark(for uuid: String, allowDeleted: Bool = false) -> Bookmark? {
        return grdbSelectBookmarks(in: dbQueue,
                                   filters: [BookmarkRow.Columns.uuid == uuid],
                                   limit: 1,
                                   allowDeleted: allowDeleted).first
    }

    /// Retrieves all the Bookmarks for an episode
    public func bookmarks(forEpisode episodeUuid: String, sorted: SortOption = .newestToOldest) -> [Bookmark] {
        return grdbSelectBookmarks(in: dbQueue,
                                   filters: [BookmarkRow.Columns.episodeUuid == episodeUuid],
                                   sorted: sorted)
    }

    /// Retrieves all the bookmarks for a podcast, and optionally a specific episode of that podcast
    public func bookmarks(forPodcast podcastUuid: String, episodeUuid: String? = nil, sorted: SortOption = .newestToOldest) -> [Bookmark] {
        var filters: [any SQLSpecificExpressible] = [BookmarkRow.Columns.podcastUuid == podcastUuid]
        if let episodeUuid {
            filters.append(BookmarkRow.Columns.episodeUuid == episodeUuid)
        }
        return grdbSelectBookmarks(in: dbQueue, filters: filters, sorted: sorted)
    }

    /// Returns all the bookmarks in the database and optionally can also return deleted items
    public func allBookmarks(includeDeleted: Bool = false, sorted: SortOption = .newestToOldest) -> [Bookmark] {
        return grdbSelectBookmarks(in: dbQueue, sorted: sorted, allowDeleted: includeDeleted)
    }

    /// Returns the number of bookmarks for the given episode and can optionally include deleted items in the count
    public func bookmarkCount(forEpisode episodeUuid: String, includeDeleted: Bool = false) -> Int {
        var request = BookmarkRow.filter(BookmarkRow.Columns.episodeUuid == episodeUuid)
        if !includeDeleted {
            request = request.filter(BookmarkRow.Columns.deleted == false)
        }
        let bookmarkRequest = request
        return dbQueue.read { db in
            try bookmarkRequest.fetchCount(db)
        } ?? 0
    }

    // MARK: - Syncing

    /// Returns all the bookmarks in the database that have the syncStatus of `notSynced`
    public func bookmarksToSync() -> [Bookmark] {
        return grdbSelectBookmarks(in: dbQueue,
                                   filters: [BookmarkRow.Columns.syncStatus == SyncStatus.notSynced.rawValue],
                                   allowDeleted: true)
    }

    @discardableResult
    public func markAllBookmarksAsSynced() async -> Bool {
        let success = dbQueue.write { db in
            _ = try BookmarkRow.updateAll(db, BookmarkRow.Columns.syncStatus.set(to: SyncStatus.synced.rawValue))
        }
        if !success { FileLog.shared.addMessage("BookmarkManager.markAllBookmarksAsSynced failed") }
        return success
    }

    // MARK: - Deleting

    /// Marks the bookmarks as deleted, but doesn't actually remove them from the database
    @discardableResult
    public func remove(bookmarks: [Bookmark], syncStatus: SyncStatus = .notSynced) async -> Bool {
        let uuids = bookmarks.map { $0.uuid }
        let deletedModifiedInterval = Date().timeIntervalSince1970
        let syncStatusValue = syncStatus.rawValue

        let success = dbQueue.write { db in
            try BookmarkRow
                .filter(uuids.contains(BookmarkRow.Columns.uuid))
                .updateAll(db,
                           BookmarkRow.Columns.deleted.set(to: true),
                           BookmarkRow.Columns.deletedModifiedDate.set(to: deletedModifiedInterval),
                           BookmarkRow.Columns.syncStatus.set(to: syncStatusValue))
            for uuid in uuids {
                try recordFileSyncChange(uuid: uuid, isDelete: true, syncStatus: syncStatus, db: db)
            }
        }
        if !success { FileLog.shared.addMessage("BookmarkManager.remove failed") }
        return success
    }

    /// Permanently removes the bookmarks from the database
    @discardableResult
    public func permanentlyDelete(bookmarks: [Bookmark]) async -> Bool {
        let uuids = bookmarks.map { $0.uuid }

        let success = dbQueue.write { db in
            _ = try BookmarkRow.filter(uuids.contains(BookmarkRow.Columns.uuid)).deleteAll(db)
        }
        if !success { FileLog.shared.addMessage("BookmarkManager.remove failed") }
        return success
    }

    // MARK: - Sortings

    public enum SortOption {
        case newestToOldest, oldestToNewest, timestamp, episode

        var queryString: String {
            switch self {
            case .newestToOldest:
                return "ORDER BY \(Column.createdDate) DESC"
            case .oldestToNewest:
                return "ORDER BY \(Column.createdDate) ASC"
            case .timestamp, .episode:
                return "ORDER BY \(Column.time) ASC"
            }
        }
    }

    // MARK: - Columns

    enum Column: String, CaseIterable, CustomStringConvertible {
        case uuid
        case title
        case createdDate = "date_added"
        case episode = "episode_uuid"
        case podcast = "podcast_uuid"
        case time
        case deleted

        // For Syncing
        case titleModifiedDate = "title_modified_date"
        case deletedModifiedDate = "deleted_modified_date"
        case syncStatus = "sync_status"

        var description: String { rawValue }
    }
}

// MARK: - Private

private extension BookmarkDataManager {
    func recordFileSyncChange(uuid: String, isDelete: Bool, syncStatus: SyncStatus, db: Database) throws {
        guard syncStatus == .notSynced,
              !DataManager.isApplyingRemoteFileSyncOps,
              let fileSyncJournalManager else { return }

        let entry = FileSyncJournalEntry(
            entityType: FileSyncJournalEntry.EntityType.bookmark.rawValue,
            entityUuid: uuid,
            opType: isDelete
                ? FileSyncJournalEntry.OpType.delete.rawValue
                : FileSyncJournalEntry.OpType.upsert.rawValue,
            fields: isDelete ? nil : "[]")
        if isDelete {
            try fileSyncJournalManager.record(entry, db: db)
        } else {
            try fileSyncJournalManager.recordCoalescing(entry, db: db)
        }
    }

    /// GRDB query-interface twin of `selectBookmarks(where:values:limit:sorted:allowDeleted:)`
    func grdbSelectBookmarks(in dbQueue: GRDBQueue, filters: [any SQLSpecificExpressible] = [], sorted: SortOption = .newestToOldest, limit: Int = 0, allowDeleted: Bool = false) -> [Bookmark] {
        var request = BookmarkRow.all()

        for filter in filters {
            request = request.filter(filter)
        }

        // If the deleted column isn't specified, then by default exclude deleted items
        if !allowDeleted {
            request = request.filter(BookmarkRow.Columns.deleted == false)
        }

        switch sorted {
        case .newestToOldest:
            request = request.order(BookmarkRow.Columns.dateAdded.desc)
        case .oldestToNewest:
            request = request.order(BookmarkRow.Columns.dateAdded.asc)
        case .timestamp, .episode:
            request = request.order(BookmarkRow.Columns.time.asc)
        }

        if limit != 0 {
            request = request.limit(limit)
        }

        return dbQueue.fetchAll(request).map(\.asBookmark)
    }
}

// MARK: - Schema Creation
extension BookmarkDataManager {
    static func createTable(in db: PCDatabase) throws {
        // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - schema DDL (createTable)
        try db.executeUpdate("""
            CREATE TABLE IF NOT EXISTS \(Self.tableName) (
                \(Column.uuid) varchar(40) NOT NULL,
                \(Column.title) varchar(100) NOT NULL,
                \(Column.titleModifiedDate) INTEGER,
                \(Column.episode) varchar(40) NOT NULL,
                \(Column.podcast) varchar(40),
                \(Column.time) real NOT NULL,
                \(Column.createdDate) INTEGER NOT NULL,
                \(Column.deleted) int NOT NULL DEFAULT 0,
                \(Column.deletedModifiedDate) INTEGER,
                \(Column.syncStatus) int NOT NULL DEFAULT 0,
                PRIMARY KEY (\(Column.uuid))
            );
        """, values: nil)

        try db.executeUpdate("CREATE INDEX IF NOT EXISTS bookmark_uuid ON \(Self.tableName) (\(Column.uuid));", values: nil) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - schema DDL (index creation)
        try db.executeUpdate("CREATE INDEX IF NOT EXISTS bookmark_episode ON \(Self.tableName) (\(Column.episode));", values: nil) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - schema DDL (index creation)
        try db.executeUpdate("CREATE INDEX IF NOT EXISTS bookmark_podcast ON \(Self.tableName) (\(Column.podcast));", values: nil) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - schema DDL (index creation)
        try db.executeUpdate("CREATE INDEX IF NOT EXISTS bookmark_deleted ON \(Self.tableName) (\(Column.deleted));", values: nil) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - schema DDL (index creation)
    }
}

// MARK: - Bookmark from PCDBResultSet
private extension Bookmark {
    init?(from resultSet: PCDBResultSet) {
        guard
            let uuid = resultSet.string(for: .uuid),
            let title = resultSet.string(for: .title),
            let createdDate = resultSet.date(for: .createdDate),
            let episode = resultSet.string(for: .episode),
            let time = resultSet.double(for: .time)
        else {
            return nil
        }

        let podcast = resultSet.string(for: .podcast)
        let titleModified = resultSet.date(for: .titleModifiedDate)
        let deletedModified = resultSet.date(for: .deletedModifiedDate)
        let deleted = resultSet.bool(for: .deleted) ?? false

        self.init(uuid: uuid,
                  title: title,
                  time: time,
                  created: createdDate,
                  episodeUuid: episode,
                  podcastUuid: podcast,
                  titleModified: titleModified,
                  deletedModified: deletedModified,
                  deleted: deleted)
    }
}

// MARK: - BookmarkDataManager.Column: PCDBResultSet Extension

private extension PCDBResultSet {
    func string(for column: BookmarkDataManager.Column) -> String? {
        string(forColumn: column.rawValue)
    }

    func date(for column: BookmarkDataManager.Column) -> Date? {
        date(forColumn: column.rawValue)
    }

    func double(for column: BookmarkDataManager.Column) -> Double? {
        double(forColumn: column.rawValue)
    }

    func bool(for column: BookmarkDataManager.Column) -> Bool? {
        bool(forColumn: column.rawValue)
    }
}
