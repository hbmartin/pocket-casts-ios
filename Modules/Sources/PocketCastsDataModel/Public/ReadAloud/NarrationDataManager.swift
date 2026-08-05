import Foundation
import GRDB
import PocketCastsUtils

/// Data access for Read Aloud narrations (migration 91, ADR-0019).
///
/// Every mutation here is a single-row update keyed by uuid, because a narration
/// is only ever touched by the one queue slot rendering it. The exception is
/// `detach`, which is driven by episode deletion and so keys on `episodeUuid`.
public struct NarrationDataManager: Sendable {
    private let dbQueue: GRDBQueue

    init(dbQueue: GRDBQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Reads

    public func narration(uuid: String) -> NarrationRecord? {
        dbQueue.read { db in
            try NarrationRecord.filter(NarrationRecord.Columns.uuid == uuid).fetchOne(db)
        } ?? nil
    }

    public func narration(episodeUuid: String) -> NarrationRecord? {
        dbQueue.read { db in
            try NarrationRecord.filter(NarrationRecord.Columns.episodeUuid == episodeUuid).fetchOne(db)
        } ?? nil
    }

    /// The library screen's list: newest first.
    public func allNarrations(limit: Int? = nil) -> [NarrationRecord] {
        dbQueue.read { db in
            var request = NarrationRecord
                .order(NarrationRecord.Columns.createdDate.desc)
            if let limit { request = request.limit(limit) }
            return try request.fetchAll(db)
        } ?? []
    }

    /// Narrations a launch-time resume should pick up, oldest first so the queue
    /// finishes what the user asked for earliest.
    public func narrationsPendingResume() -> [NarrationRecord] {
        let states = NarrationState.resumable.map(\.rawValue)
        return dbQueue.read { db in
            try NarrationRecord
                .filter(states.contains(NarrationRecord.Columns.state))
                .order(NarrationRecord.Columns.createdDate.asc)
                .fetchAll(db)
        } ?? []
    }

    // MARK: - Writes

    @discardableResult
    public func add(_ narration: NarrationRecord) -> Bool {
        let record = narration
        let saved = dbQueue.write { db in
            try record.insert(db)
        }
        if !saved { FileLog.shared.addMessage("NarrationDataManager.add failed for \(record.uuid)") }
        return saved
    }

    /// Moves a queued narration into rendering once its chunk count is known.
    @discardableResult
    public func markRendering(uuid: String, chunkCount: Int) -> Bool {
        update(uuid: uuid, [
            NarrationRecord.Columns.state.set(to: NarrationState.rendering.rawValue),
            NarrationRecord.Columns.chunkCount.set(to: chunkCount),
            NarrationRecord.Columns.errorCode.set(to: nil),
            NarrationRecord.Columns.errorDetails.set(to: nil),
        ])
    }

    /// Advances the checkpoint. Called once per rendered chunk, immediately
    /// after that chunk's file lands, so a kill between the two loses at most
    /// the one chunk (which the resume path then re-renders).
    @discardableResult
    public func updateProgress(uuid: String, completedChunkCount: Int) -> Bool {
        update(uuid: uuid, [NarrationRecord.Columns.completedChunkCount.set(to: completedChunkCount)])
    }

    @discardableResult
    public func markCompleted(uuid: String, episodeUuid: String, duration: TimeInterval, sizeInBytes: Int64) -> Bool {
        update(uuid: uuid, [
            NarrationRecord.Columns.state.set(to: NarrationState.completed.rawValue),
            NarrationRecord.Columns.episodeUuid.set(to: episodeUuid),
            NarrationRecord.Columns.outputDuration.set(to: duration),
            NarrationRecord.Columns.outputSizeInBytes.set(to: sizeInBytes),
            NarrationRecord.Columns.completedDate.set(to: Date().timeIntervalSince1970),
            NarrationRecord.Columns.errorCode.set(to: nil),
            NarrationRecord.Columns.errorDetails.set(to: nil),
        ])
    }

    /// - Parameter errorDetails: developer-authored only. Provider-generated
    ///   text can echo the user's document and must not be persisted.
    @discardableResult
    public func markFailed(uuid: String, errorCode: String, errorDetails: String?) -> Bool {
        update(uuid: uuid, [
            NarrationRecord.Columns.state.set(to: NarrationState.failed.rawValue),
            NarrationRecord.Columns.errorCode.set(to: errorCode),
            NarrationRecord.Columns.errorDetails.set(to: errorDetails),
        ])
    }

    @discardableResult
    public func markCancelled(uuid: String) -> Bool {
        update(uuid: uuid, [NarrationRecord.Columns.state.set(to: NarrationState.cancelled.rawValue)])
    }

    /// Resets a failed or cancelled narration for another attempt. The
    /// checkpoint is deliberately left alone: already-rendered chunks are still
    /// valid, because the settings that produced them are frozen on this row.
    @discardableResult
    public func markQueued(uuid: String) -> Bool {
        update(uuid: uuid, [
            NarrationRecord.Columns.state.set(to: NarrationState.queued.rawValue),
            NarrationRecord.Columns.errorCode.set(to: nil),
            NarrationRecord.Columns.errorDetails.set(to: nil),
        ])
    }

    /// The user deleted the generated episode. The audio is gone; the document
    /// is not. Returns whether a narration was actually detached, so callers can
    /// skip work for ordinary uploaded files.
    @discardableResult
    public func detachEpisode(episodeUuid: String) -> Bool {
        var updatedRows = 0
        let success = dbQueue.write { db in
            updatedRows = try NarrationRecord
                .filter(NarrationRecord.Columns.episodeUuid == episodeUuid)
                .updateAll(db,
                           NarrationRecord.Columns.episodeUuid.set(to: nil),
                           NarrationRecord.Columns.state.set(to: NarrationState.detached.rawValue),
                           NarrationRecord.Columns.outputDuration.set(to: nil),
                           NarrationRecord.Columns.outputSizeInBytes.set(to: nil))
        }
        return success && updatedRows > 0
    }

    /// Removes the row only. Deleting the source file and the linked episode is
    /// the caller's job — this manager owns no filesystem and no episodes.
    @discardableResult
    public func delete(uuid: String) -> Bool {
        dbQueue.write { db in
            _ = try NarrationRecord.filter(NarrationRecord.Columns.uuid == uuid).deleteAll(db)
        }
    }

    // MARK: - Helpers

    private func update(uuid: String, _ assignments: [ColumnAssignment]) -> Bool {
        var updatedRows = 0
        let success = dbQueue.write { db in
            updatedRows = try NarrationRecord
                .filter(NarrationRecord.Columns.uuid == uuid)
                .updateAll(db, assignments)
        }
        return success && updatedRows > 0
    }
}
