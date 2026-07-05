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

    func findReplaceAction(dbQueue: PCDBQueue) -> UpNextChanges? {
        if let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.fetchOne(UpNextChanges.filter(UpNextChanges.Columns.type == UpNextChanges.Actions.replace.rawValue))
        }

        var replaceAction: UpNextChanges?
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery("SELECT * from \(DataManager.upNextChangesTableName) WHERE type = ?", values: [UpNextChanges.Actions.replace.rawValue])
                defer { resultSet.close() }

                if resultSet.next() {
                    replaceAction = self.createFrom(resultSet: resultSet)
                }
            } catch {
                FileLog.shared.addMessage("UpNextChangesDataManager.findReplaceAction error: \(error)")
            }
        }

        return replaceAction
    }

    func findUpdateActions(dbQueue: PCDBQueue) -> [UpNextChanges] {
        if let grdbQueue = dbQueue as? GRDBQueue {
            return grdbQueue.fetchAll(UpNextChanges.filter(UpNextChanges.Columns.type != UpNextChanges.Actions.replace.rawValue))
        }

        var allUpdateActions = [UpNextChanges]()
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery("SELECT * from \(DataManager.upNextChangesTableName) WHERE type != ?", values: [UpNextChanges.Actions.replace.rawValue])
                defer { resultSet.close() }

                while resultSet.next() {
                    let action = self.createFrom(resultSet: resultSet)
                    allUpdateActions.append(action)
                }
            } catch {
                FileLog.shared.addMessage("UpNextChangesDataManager.findUpdateActions error: \(error)")
            }
        }

        return allUpdateActions
    }

    // MARK: - Update

    func saveUpNextRemove(episodeUuid: String, dbQueue: PCDBQueue) {
        saveUpdate(action: UpNextChanges.Actions.remove, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveUpNextAddToTop(episodeUuid: String, dbQueue: PCDBQueue) {
        saveUpdate(action: UpNextChanges.Actions.playNext, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveUpNextAddToBottom(episodeUuid: String, dbQueue: PCDBQueue) {
        saveUpdate(action: UpNextChanges.Actions.playLast, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveUpNextAddNowPlaying(episodeUuid: String, dbQueue: PCDBQueue) {
        saveUpdate(action: UpNextChanges.Actions.playNow, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    func saveReplace(episodeList: [String], dbQueue: PCDBQueue) {
        var replaceChange = UpNextChanges()
        replaceChange.id = DBUtils.generateUniqueId()
        replaceChange.type = UpNextChanges.Actions.replace.rawValue
        replaceChange.uuids = episodeList.joined(separator: ",")
        replaceChange.utcTime = DBUtils.currentUTCTimeInMillis()
        let changeToSave = replaceChange

        if let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.write { db in
                // a replace literally replaces everything that came before it, so empty the table out
                try UpNextChanges.deleteAll(db)
                try changeToSave.insert(db)
            }
            return
        }

        dbQueue.write { db in
            do {
                // a replace literally replaces everything that came before it, so empty the table out
                try db.executeUpdate("DELETE FROM \(DataManager.upNextChangesTableName)", values: nil)
                try db.executeUpdate("INSERT INTO \(DataManager.upNextChangesTableName) (\(self.columnNames.joined(separator: ","))) VALUES \(DBUtils.valuesQuestionMarks(amount: self.columnNames.count))", values: self.createValuesFrom(upNextChanges: changeToSave))
            } catch {
                FileLog.shared.addMessage("UpNextChangesDataManager.saveReplace error: \(error)")
            }
        }
    }

    private func saveUpdate(action: UpNextChanges.Actions, episodeUuid: String, dbQueue: PCDBQueue) {
        var updateChange = UpNextChanges()
        updateChange.id = DBUtils.generateUniqueId()
        updateChange.type = action.rawValue
        updateChange.uuid = episodeUuid
        updateChange.utcTime = DBUtils.currentUTCTimeInMillis()
        let changeToSave = updateChange

        if let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.write { db in
                // an update replaces any other update that is for the same episode, so delete any that might exist
                try UpNextChanges.filter(UpNextChanges.Columns.uuid == episodeUuid).deleteAll(db)
                try changeToSave.insert(db)
            }
            return
        }

        dbQueue.write { db in
            do {
                // an update replaces any other update that is for the same episode, so delete any that might exist
                try db.executeUpdate("DELETE FROM \(DataManager.upNextChangesTableName) WHERE uuid = ?", values: [episodeUuid])
                try db.executeUpdate("INSERT INTO \(DataManager.upNextChangesTableName) (\(self.columnNames.joined(separator: ","))) VALUES \(DBUtils.valuesQuestionMarks(amount: self.columnNames.count))", values: self.createValuesFrom(upNextChanges: changeToSave))
            } catch {
                FileLog.shared.addMessage("UpNextChangesDataManager.saveUpdate error: \(error)")
            }
        }
    }

    // MARK: - Delete

    func deleteChangesOlderThan(utcTime: Int64, dbQueue: PCDBQueue) {
        if let grdbQueue = dbQueue as? GRDBQueue {
            grdbQueue.deleteAll(UpNextChanges.self, filter: UpNextChanges.Columns.utcTime <= utcTime)
            return
        }

        dbQueue.write { db in
            do {
                try db.executeUpdate("DELETE FROM \(DataManager.upNextChangesTableName) where utcTime <= ?", values: [utcTime])
            } catch {
                FileLog.shared.addMessage("UpNextChangesDataManager.deleteChangesOlderThan error: \(error)")
            }
        }
    }

    // MARK: - Conversion

    private func createFrom(resultSet rs: PCDBResultSet) -> UpNextChanges {
        var changes = UpNextChanges()

        changes.id = rs.longLongInt(forColumn: "id")
        changes.type = rs.int(forColumn: "type")
        changes.uuid = rs.string(forColumn: "uuid")
        changes.uuids = rs.string(forColumn: "uuids")
        changes.utcTime = rs.longLongInt(forColumn: "utcTime")

        return changes
    }

    private func createValuesFrom(upNextChanges: UpNextChanges) -> [Any] {
        var values = [Any]()
        values.append(upNextChanges.id)
        values.append(upNextChanges.type)
        values.append(DBUtils.replaceNilWithNull(value: upNextChanges.uuid))
        values.append(DBUtils.replaceNilWithNull(value: upNextChanges.uuids))
        values.append(upNextChanges.utcTime)

        return values
    }
}
