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

    func saveUpNextAddToTop(episodeUuid: String, dbQueue: GRDBQueue) {
        saveUpdate(action: UpNextChanges.Actions.playNext, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveUpNextAddToBottom(episodeUuid: String, dbQueue: GRDBQueue) {
        saveUpdate(action: UpNextChanges.Actions.playLast, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveUpNextAddNowPlaying(episodeUuid: String, dbQueue: GRDBQueue) {
        saveUpdate(action: UpNextChanges.Actions.playNow, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveReplace(episodeList: [String], dbQueue: GRDBQueue) {
        var replaceChange = UpNextChanges()
        replaceChange.id = DBUtils.generateUniqueId()
        replaceChange.type = UpNextChanges.Actions.replace.rawValue
        replaceChange.uuids = episodeList.joined(separator: ",")
        replaceChange.utcTime = DBUtils.currentUTCTimeInMillis()
        let changeToSave = replaceChange

        dbQueue.write { db in
            // a replace literally replaces everything that came before it, so empty the table out
            try UpNextChanges.deleteAll(db)
            try changeToSave.insert(db)
        }
    }

    private func saveUpdate(action: UpNextChanges.Actions, episodeUuid: String, dbQueue: GRDBQueue) {
        var updateChange = UpNextChanges()
        updateChange.id = DBUtils.generateUniqueId()
        updateChange.type = action.rawValue
        updateChange.uuid = episodeUuid
        updateChange.utcTime = DBUtils.currentUTCTimeInMillis()
        let changeToSave = updateChange

        dbQueue.write { db in
            // an update replaces any other update that is for the same episode, so delete any that might exist
            try UpNextChanges.filter(UpNextChanges.Columns.uuid == episodeUuid).deleteAll(db)
            try changeToSave.insert(db)
        }
    }

    // MARK: - Delete

    func deleteChangesOlderThan(utcTime: Int64, dbQueue: GRDBQueue) {
        dbQueue.deleteAll(UpNextChanges.self, filter: UpNextChanges.Columns.utcTime <= utcTime)
    }

    // MARK: - Conversion



}
