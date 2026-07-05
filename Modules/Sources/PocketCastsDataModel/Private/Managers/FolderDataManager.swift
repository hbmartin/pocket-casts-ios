import PocketCastsUtils
import Foundation
import GRDB

class FolderDataManager {
    /// Legacy column names for non-GRDB code path.
    let columnNames = [
        "uuid",
        "name",
        "color",
        "addedDate",
        "sortOrder",
        "sortType",
        "wasDeleted",
        "syncModified"
    ]

    private var cachedFolders = [Folder]()
    private lazy var cachedFolderQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "au.com.pocketcasts.FolderDataQueue")

        return queue
    }()

    func setup(dbQueue: GRDBQueue) {
        cacheFolders(dbQueue: dbQueue)
    }

    func findFolder(uuid: String, dbQueue: GRDBQueue) -> Folder? {
        cachedFolderQueue.sync {
            cachedFolders.first { $0.uuid == uuid }
        }
    }

    func allFolders(includeDeleted: Bool, dbQueue: GRDBQueue) -> [Folder] {
        if includeDeleted { return cachedFolders }

        return cachedFolders.filter { $0.wasDeleted == false }
    }

    /// Persists the folder, assigning a `uuid` if it has none, and returns the saved value.
    /// Returns rather than mutating in place because `Folder` is a value type — callers that
    /// need the generated `uuid` must use the returned folder.
    @discardableResult
    func save(folder: Folder, dbQueue: GRDBQueue) -> Folder {
        var folder = folder
        if folder.uuid.isEmpty {
            folder.uuid = UUID().uuidString.lowercased()
        }
        let folderToSave = folder

        do {
            try dbQueue.dbPool.write { db in
                try folderToSave.save(db)
            }
        } catch {
            FileLog.shared.addMessage("FolderDataManager.save error: \(error)")
        }
        cacheFolders(dbQueue: dbQueue)
        return folder
    }

    func delete(folderUuid: String, dbQueue: GRDBQueue) {
        dbQueue.deleteAll(Folder.self, filter: Folder.Columns.uuid == folderUuid)
        cacheFolders(dbQueue: dbQueue)
    }

    func deleteAllFolders(dbQueue: GRDBQueue) {
        _ = dbQueue.write { db in
            try Folder.deleteAll(db)
        }
        cacheFolders(dbQueue: dbQueue)
    }

    func saveSortOrders(folders: [Folder], syncModified: Int64, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            for folder in folders {
                try Folder
                    .filter(Folder.Columns.uuid == folder.uuid)
                    .updateAll(db, Folder.Columns.sortOrder.set(to: folder.sortOrder), Folder.Columns.syncModified.set(to: syncModified))
            }
        }
        cacheFolders(dbQueue: dbQueue)
    }

    func updateFolderColor(folderUuid: String, color: Int32, syncModified: Int64, dbQueue: GRDBQueue) {
        dbQueue.updateAll(Folder.self, filter: Folder.Columns.uuid == folderUuid, Folder.Columns.color.set(to: color), Folder.Columns.syncModified.set(to: syncModified))
        cacheFolders(dbQueue: dbQueue)
    }

    func updateFolderSyncModified(folderUuid: String, syncModified: Int64, dbQueue: GRDBQueue) {
        dbQueue.updateAll(Folder.self, filter: Folder.Columns.uuid == folderUuid, Folder.Columns.syncModified.set(to: syncModified))
        cacheFolders(dbQueue: dbQueue)
    }

    func bulkSetSyncModified(_ syncModified: Int64, onFolders folderUuids: [String], dbQueue: GRDBQueue) {
        dbQueue.updateAll(Folder.self, filter: folderUuids.contains(Folder.Columns.uuid), Folder.Columns.syncModified.set(to: syncModified))
        cacheFolders(dbQueue: dbQueue)
    }

    func allUnsyncedFolders(dbQueue: GRDBQueue) -> [Folder] {
        var unsyncedFolders = [Folder]()
        cachedFolderQueue.sync {
            unsyncedFolders = cachedFolders.filter { $0.syncModified > 0 }
        }

        return unsyncedFolders
    }

    func markAllFoldersSynced(dbQueue: GRDBQueue) {
        _ = dbQueue.write { db in
            try Folder.updateAll(db, Folder.Columns.syncModified.set(to: 0))
        }
        cacheFolders(dbQueue: dbQueue)
    }

    func markFolderAsDeleted(folderUuid: String, syncModified: Int64, dbQueue: GRDBQueue) {
        dbQueue.updateAll(Folder.self, filter: Folder.Columns.uuid == folderUuid, Folder.Columns.syncModified.set(to: syncModified), Folder.Columns.wasDeleted.set(to: true))
        cacheFolders(dbQueue: dbQueue)
    }

    func markAllFolderAsDeleted(syncModified: Int64, dbQueue: GRDBQueue) {
        _ = dbQueue.write { db in
            try Folder.updateAll(db, Folder.Columns.syncModified.set(to: syncModified), Folder.Columns.wasDeleted.set(to: true))
        }
        cacheFolders(dbQueue: dbQueue)
    }

    private func cacheFolders(dbQueue: GRDBQueue) {
        guard let newFolders = dbQueue.read({ db in
            do {
                return try Folder.fetchAll(db)
            } catch {
                FileLog.shared.addMessage("FolderDataManager.cacheFolders error: \(error)")
                throw error
            }
        }) else { return }

        cachedFolderQueue.sync {
            cachedFolders = newFolders
        }
    }

    // MARK: - Conversion



}
