import Foundation
import GRDB
import PocketCastsUtils

/// File-sync change journal surface.
///
/// File sync tracks local changes in its own journal instead of reusing the
/// server-sync bookkeeping: `SyncTask.markAllSynced` zeroes the episode
/// `*Modified` stamps and flips `syncStatus` after a server push, so any
/// engine sharing those flags would silently lose changes whenever both
/// sync engines run (a logged-in user with file sync enabled).
///
/// Write path: the save methods below journal transactionally with the data
/// change, but only for user-intent saves (`updateSyncFlag: true` — the
/// same signal that drives server sync) and never while remote file-sync
/// ops are being applied (see `withFileSyncApplySuppression`), which is
/// what prevents echo loops.
public extension DataManager {
    /// True while `RemoteOpApplier` is writing folder-derived state into
    /// the database on the current task. Suppresses journaling so applied
    /// remote ops don't get re-journaled and echo back to the folder.
    @TaskLocal static var isApplyingRemoteFileSyncOps = false

    static func withFileSyncApplySuppression<T>(_ body: () throws -> T) rethrows -> T {
        try $isApplyingRemoteFileSyncOps.withValue(true, operation: body)
    }

    // MARK: - Journal writes (called from save paths + app-side observers)

    /// Records a journal entry unless remote ops are being applied.
    func recordFileSyncJournal(_ entry: FileSyncJournalEntry) {
        guard !Self.isApplyingRemoteFileSyncOps else { return }
        fileSyncJournalManager.recordCoalescing(entry, dbQueue: dbQueue)
    }

    /// Journals a per-field episode change (Episode or UserEpisode).
    func journalFileSyncEpisodeChange(episode: BaseEpisode, changedFields: [String]) {
        guard !Self.isApplyingRemoteFileSyncOps else { return }
        let entityType: FileSyncJournalEntry.EntityType = episode is UserEpisode ? .userEpisode : .episode
        journalFileSyncUpsert(entityType: entityType, uuid: episode.uuid, changedFields: changedFields)
    }

    func journalFileSyncUpsert(entityType: FileSyncJournalEntry.EntityType, uuid: String, changedFields: [String]) {
        guard !Self.isApplyingRemoteFileSyncOps else { return }
        let fieldsJSON = (try? JSONEncoder().encode(changedFields)).flatMap { String(data: $0, encoding: .utf8) }
        fileSyncJournalManager.recordCoalescing(
            FileSyncJournalEntry(
                entityType: entityType.rawValue,
                entityUuid: uuid,
                opType: FileSyncJournalEntry.OpType.upsert.rawValue,
                fields: fieldsJSON),
            dbQueue: dbQueue)
    }

    func journalFileSyncDelete(entityType: FileSyncJournalEntry.EntityType, uuid: String) {
        guard !Self.isApplyingRemoteFileSyncOps else { return }
        fileSyncJournalManager.record(
            FileSyncJournalEntry(
                entityType: entityType.rawValue,
                entityUuid: uuid,
                opType: FileSyncJournalEntry.OpType.delete.rawValue),
            dbQueue: dbQueue)
    }

    func journalFileSyncUpNext(op: FileSyncJournalEntry.OpType, episodeUuid: String?, episodeUuids: [String]? = nil) {
        guard !Self.isApplyingRemoteFileSyncOps else { return }
        let fieldsJSON = episodeUuids.flatMap { uuids in
            (try? JSONEncoder().encode(uuids)).flatMap { String(data: $0, encoding: .utf8) }
        }
        fileSyncJournalManager.record(
            FileSyncJournalEntry(
                entityType: FileSyncJournalEntry.EntityType.upNext.rawValue,
                entityUuid: episodeUuid,
                opType: op.rawValue,
                fields: fieldsJSON),
            dbQueue: dbQueue)
    }

    /// Journals an app-level setting change (called by the app-side
    /// settings observer; `jsonValue` uses the CodableStore encoding).
    func journalFileSyncSettingChange(name: String, jsonValue: String, modifiedAtMs: Int64) {
        guard !Self.isApplyingRemoteFileSyncOps else { return }
        let payload = ["name": name, "jsonValue": jsonValue]
        let fieldsJSON = (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
        fileSyncJournalManager.recordCoalescing(
            FileSyncJournalEntry(
                entityType: FileSyncJournalEntry.EntityType.setting.rawValue,
                entityUuid: name,
                opType: FileSyncJournalEntry.OpType.settingChange.rawValue,
                fields: fieldsJSON,
                wallClockMs: modifiedAtMs),
            dbQueue: dbQueue)
    }

    // MARK: - Flusher/inspector surface

    func unflushedFileSyncEntries(limit: Int) -> [FileSyncJournalEntry] {
        fileSyncJournalManager.unflushedEntries(limit: limit, dbQueue: dbQueue)
    }

    func unflushedFileSyncCount() -> Int {
        fileSyncJournalManager.unflushedCount(dbQueue: dbQueue)
    }

    func markFileSyncEntriesFlushed(entryIDs: [Int64], startingSeq: Int64) {
        fileSyncJournalManager.markFlushed(entryIDs: entryIDs, startingSeq: startingSeq, dbQueue: dbQueue)
    }

    func purgeFlushedFileSyncEntries(olderThanMs: Int64) {
        fileSyncJournalManager.purgeFlushed(olderThanMs: olderThanMs, dbQueue: dbQueue)
    }

    func deleteAllFileSyncJournalEntries() {
        fileSyncJournalManager.deleteAll(dbQueue: dbQueue)
    }

    // MARK: - Cursors

    func fileSyncCursor(peerDeviceId: String) -> FileSyncCursor? {
        fileSyncJournalManager.cursor(peerDeviceId: peerDeviceId, dbQueue: dbQueue)
    }

    func allFileSyncCursors() -> [FileSyncCursor] {
        fileSyncJournalManager.allCursors(dbQueue: dbQueue)
    }

    func save(fileSyncCursor: FileSyncCursor) {
        fileSyncJournalManager.save(cursor: fileSyncCursor, dbQueue: dbQueue)
    }

    func deleteFileSyncCursor(peerDeviceId: String) {
        fileSyncJournalManager.deleteCursor(peerDeviceId: peerDeviceId, dbQueue: dbQueue)
    }

    /// Root-folder switch or disable: all read progress is folder-specific.
    func deleteAllFileSyncCursors() {
        fileSyncJournalManager.deleteAllCursors(dbQueue: dbQueue)
    }
}

extension DataManager {
    func recordFileSyncJournal(_ entry: FileSyncJournalEntry, db: Database) throws {
        guard !Self.isApplyingRemoteFileSyncOps else { return }
        try fileSyncJournalManager.record(entry, db: db)
    }

    func journalFileSyncEpisodeChange(episode: BaseEpisode, changedFields: [String], db: Database) throws {
        guard !Self.isApplyingRemoteFileSyncOps else { return }
        let entityType: FileSyncJournalEntry.EntityType = episode is UserEpisode ? .userEpisode : .episode
        try journalFileSyncUpsert(entityType: entityType, uuid: episode.uuid, changedFields: changedFields, db: db)
    }

    func journalFileSyncUpsert(
        entityType: FileSyncJournalEntry.EntityType,
        uuid: String,
        changedFields: [String],
        db: Database
    ) throws {
        guard !Self.isApplyingRemoteFileSyncOps else { return }
        let fieldsJSON = (try? JSONEncoder().encode(changedFields)).flatMap { String(data: $0, encoding: .utf8) }
        try fileSyncJournalManager.recordCoalescing(
            FileSyncJournalEntry(
                entityType: entityType.rawValue,
                entityUuid: uuid,
                opType: FileSyncJournalEntry.OpType.upsert.rawValue,
                fields: fieldsJSON),
            db: db)
    }

    func journalFileSyncDelete(
        entityType: FileSyncJournalEntry.EntityType,
        uuid: String,
        db: Database
    ) throws {
        guard !Self.isApplyingRemoteFileSyncOps else { return }
        try fileSyncJournalManager.record(
            FileSyncJournalEntry(
                entityType: entityType.rawValue,
                entityUuid: uuid,
                opType: FileSyncJournalEntry.OpType.delete.rawValue),
            db: db)
    }

    func journalFileSyncUpNext(
        op: FileSyncJournalEntry.OpType,
        episodeUuid: String?,
        episodeUuids: [String]? = nil,
        db: Database
    ) throws {
        guard !Self.isApplyingRemoteFileSyncOps else { return }
        let fieldsJSON = episodeUuids.flatMap { uuids in
            (try? JSONEncoder().encode(uuids)).flatMap { String(data: $0, encoding: .utf8) }
        }
        try fileSyncJournalManager.record(
            FileSyncJournalEntry(
                entityType: FileSyncJournalEntry.EntityType.upNext.rawValue,
                entityUuid: episodeUuid,
                opType: op.rawValue,
                fields: fieldsJSON),
            db: db)
    }
}
