import Foundation
import GRDB
import PocketCastsUtils

class FileSyncJournalDataManager {

    // MARK: - Journal

    func record(_ entry: FileSyncJournalEntry, dbQueue: GRDBQueue) {
        var toSave = entry
        if toSave.id == 0 {
            toSave.id = DBUtils.generateUniqueId()
        }
        if toSave.wallClockMs == 0 {
            toSave.wallClockMs = DBUtils.currentUTCTimeInMillis()
        }
        let entryToSave = toSave
        dbQueue.write { db in
            try entryToSave.insert(db)
        }
    }

    /// Coalesces consecutive upserts for the same entity+fields: position
    /// heartbeats would otherwise pile up a row a minute. The newest row's
    /// timestamp wins; the older duplicate is removed.
    func recordCoalescing(_ entry: FileSyncJournalEntry, dbQueue: GRDBQueue) {
        var toSave = entry
        if toSave.id == 0 {
            toSave.id = DBUtils.generateUniqueId()
        }
        if toSave.wallClockMs == 0 {
            toSave.wallClockMs = DBUtils.currentUTCTimeInMillis()
        }
        let entryToSave = toSave
        dbQueue.write { db in
            if entryToSave.opType == FileSyncJournalEntry.OpType.upsert.rawValue,
               let uuid = entryToSave.entityUuid {
                try FileSyncJournalEntry
                    .filter(FileSyncJournalEntry.Columns.entityType == entryToSave.entityType)
                    .filter(FileSyncJournalEntry.Columns.entityUuid == uuid)
                    .filter(FileSyncJournalEntry.Columns.opType == entryToSave.opType)
                    .filter(FileSyncJournalEntry.Columns.fields == entryToSave.fields)
                    .filter(FileSyncJournalEntry.Columns.flushedSeq == nil)
                    .deleteAll(db)
            }
            try entryToSave.insert(db)
        }
    }

    func unflushedEntries(limit: Int, dbQueue: GRDBQueue) -> [FileSyncJournalEntry] {
        dbQueue.fetchAll(
            FileSyncJournalEntry
                .filter(FileSyncJournalEntry.Columns.flushedSeq == nil)
                .order(FileSyncJournalEntry.Columns.wallClockMs.asc, FileSyncJournalEntry.Columns.id.asc)
                .limit(limit)
        )
    }

    func unflushedCount(dbQueue: GRDBQueue) -> Int {
        dbQueue.read { db in
            (try? FileSyncJournalEntry
                .filter(FileSyncJournalEntry.Columns.flushedSeq == nil)
                .fetchCount(db)) ?? 0
        }
    }

    /// Marks entries as durably written to the device log, recording the
    /// per-device seq each op was assigned.
    func markFlushed(entryIDs: [Int64], startingSeq: Int64, dbQueue: GRDBQueue) {
        guard !entryIDs.isEmpty else { return }
        dbQueue.write { db in
            for (index, id) in entryIDs.enumerated() {
                try FileSyncJournalEntry
                    .filter(FileSyncJournalEntry.Columns.id == id)
                    .updateAll(db, [FileSyncJournalEntry.Columns.flushedSeq.set(to: startingSeq + Int64(index))])
            }
        }
    }

    /// Flushed rows are kept briefly for the inspector's op browser, then
    /// purged.
    func purgeFlushed(olderThanMs: Int64, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try FileSyncJournalEntry
                .filter(FileSyncJournalEntry.Columns.flushedSeq != nil)
                .filter(FileSyncJournalEntry.Columns.wallClockMs < olderThanMs)
                .deleteAll(db)
        }
    }

    func deleteAll(dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try FileSyncJournalEntry.deleteAll(db)
        }
    }

    // MARK: - Cursors

    func cursor(peerDeviceId: String, dbQueue: GRDBQueue) -> FileSyncCursor? {
        dbQueue.fetchOne(FileSyncCursor.filter(FileSyncCursor.Columns.peerDeviceId == peerDeviceId))
    }

    func allCursors(dbQueue: GRDBQueue) -> [FileSyncCursor] {
        dbQueue.fetchAll(FileSyncCursor.all())
    }

    func save(cursor: FileSyncCursor, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try cursor.save(db)
        }
    }

    func deleteCursor(peerDeviceId: String, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try FileSyncCursor
                .filter(FileSyncCursor.Columns.peerDeviceId == peerDeviceId)
                .deleteAll(db)
        }
    }

    func deleteAllCursors(dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try FileSyncCursor.deleteAll(db)
        }
    }
}
