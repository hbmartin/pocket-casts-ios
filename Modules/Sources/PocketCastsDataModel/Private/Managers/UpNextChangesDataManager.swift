import GRDB
import PocketCastsUtils

class UpNextChangesDataManager {
    /// Legacy column names for non-GRDB code path.
    private let columnNames = [
        "id",
        "type",
        "uuid",
        "uuids",
        "utcTime"
    ]

    // MARK: - Query

    func findReplaceAction(dbQueue: GRDBQueue) -> UpNextChanges? {
        return dbQueue.fetchOne(UpNextChanges.filter(UpNextChanges.Columns.type == UpNextChanges.Actions.replace.rawValue))
    }

    func findUpdateActions(dbQueue: GRDBQueue) -> [UpNextChanges] {
        return dbQueue.fetchAll(UpNextChanges.filter(UpNextChanges.Columns.type != UpNextChanges.Actions.replace.rawValue))
    }

    // MARK: - Update

    func saveUpNextRemove(episodeUuid: String, dbQueue: GRDBQueue) {
        saveUpdate(action: UpNextChanges.Actions.remove, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveUpNextRemove(episodeUuid: String, db: Database) throws {
        try saveUpdate(action: UpNextChanges.Actions.remove, episodeUuid: episodeUuid, db: db)
    }

    func saveUpNextAddToTop(episodeUuid: String, dbQueue: GRDBQueue) {
        saveUpdate(action: UpNextChanges.Actions.playNext, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveUpNextAddToTop(episodeUuid: String, db: Database) throws {
        try saveUpdate(action: UpNextChanges.Actions.playNext, episodeUuid: episodeUuid, db: db)
    }

    func saveUpNextAddToBottom(episodeUuid: String, dbQueue: GRDBQueue) {
        saveUpdate(action: UpNextChanges.Actions.playLast, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveUpNextAddToBottom(episodeUuid: String, db: Database) throws {
        try saveUpdate(action: UpNextChanges.Actions.playLast, episodeUuid: episodeUuid, db: db)
    }

    func saveUpNextAddNowPlaying(episodeUuid: String, dbQueue: GRDBQueue) {
        saveUpdate(action: UpNextChanges.Actions.playNow, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveUpNextAddNowPlaying(episodeUuid: String, db: Database) throws {
        try saveUpdate(action: UpNextChanges.Actions.playNow, episodeUuid: episodeUuid, db: db)
    }

    func saveReplace(episodeList: [String], dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try saveReplace(episodeList: episodeList, db: db)
        }
    }

    func saveReplace(episodeList: [String], db: Database) throws {
        var replaceChange = UpNextChanges()
        replaceChange.id = DBUtils.generateUniqueId()
        replaceChange.type = UpNextChanges.Actions.replace.rawValue
        replaceChange.uuids = episodeList.joined(separator: ",")
        replaceChange.utcTime = DBUtils.currentUTCTimeInMillis()
        let changeToSave = replaceChange

        // a replace literally replaces everything that came before it, so empty the table out
        try UpNextChanges.deleteAll(db)
        try changeToSave.insert(db)
    }

    private func saveUpdate(action: UpNextChanges.Actions, episodeUuid: String, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try saveUpdate(action: action, episodeUuid: episodeUuid, db: db)
        }
    }

    private func saveUpdate(action: UpNextChanges.Actions, episodeUuid: String, db: Database) throws {
        var updateChange = UpNextChanges()
        updateChange.id = DBUtils.generateUniqueId()
        updateChange.type = action.rawValue
        updateChange.uuid = episodeUuid
        updateChange.utcTime = DBUtils.currentUTCTimeInMillis()
        let changeToSave = updateChange

        // an update replaces any other update that is for the same episode, so delete any that might exist
        try UpNextChanges.filter(UpNextChanges.Columns.uuid == episodeUuid).deleteAll(db)
        try changeToSave.insert(db)
    }

    // MARK: - Delete

    func deleteChangesOlderThan(utcTime: Int64, dbQueue: GRDBQueue) {
        dbQueue.deleteAll(UpNextChanges.self, filter: UpNextChanges.Columns.utcTime <= utcTime)
    }

    // MARK: - Conversion



}
