import Foundation
import GRDB
import PocketCastsUtils

/// Data access for Read Aloud (migration 91, ADR-0019, ADR-0020).
///
/// Documents and their narrations are one aggregate, so they share a manager:
/// almost every read wants both halves, and the cascade on delete has to be one
/// transaction.
///
/// Narration mutations are single-row updates keyed by uuid, because a narration
/// is only ever touched by the one queue slot rendering it. The exceptions key
/// on other columns because they are driven from outside the queue: episode
/// deletion, and cascading a document away.
public struct ReadAloudDataManager: Sendable {
    private let dbQueue: GRDBQueue

    init(dbQueue: GRDBQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Document reads

    public func document(uuid: String) -> ReadAloudDocumentRecord? {
        dbQueue.read { db in
            try ReadAloudDocumentRecord.filter(ReadAloudDocumentRecord.Columns.uuid == uuid).fetchOne(db)
        } ?? nil
    }

    /// The library screen's list: newest first.
    public func allDocuments(limit: Int? = nil) -> [ReadAloudDocumentRecord] {
        dbQueue.read { db in
            var request = ReadAloudDocumentRecord
                .order(ReadAloudDocumentRecord.Columns.addedDate.desc)
            if let limit { request = request.limit(limit) }
            return try request.fetchAll(db)
        } ?? []
    }

    /// Every document with its narrations, newest document first and newest
    /// narration first within each. One read transaction, so the library screen
    /// cannot render a document beside a narration that has since moved on.
    public func library() -> [(document: ReadAloudDocumentRecord, narrations: [NarrationRecord])] {
        let pairs: [(ReadAloudDocumentRecord, [NarrationRecord])]? = dbQueue.read { db in
            let documents = try ReadAloudDocumentRecord
                .order(ReadAloudDocumentRecord.Columns.addedDate.desc)
                .fetchAll(db)
            let narrations = try NarrationRecord
                .order(NarrationRecord.Columns.createdDate.desc)
                .fetchAll(db)
            let grouped = Dictionary(grouping: narrations, by: \.documentUuid)
            return documents.map { ($0, grouped[$0.uuid] ?? []) }
        }
        return pairs ?? []
    }

    // MARK: - Narration reads

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

    /// A document's narrations, newest first.
    public func narrations(documentUuid: String) -> [NarrationRecord] {
        dbQueue.read { db in
            try NarrationRecord
                .filter(NarrationRecord.Columns.documentUuid == documentUuid)
                .order(NarrationRecord.Columns.createdDate.desc)
                .fetchAll(db)
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
    public func add(_ document: ReadAloudDocumentRecord) -> Bool {
        let record = document
        let saved = dbQueue.write { db in
            try record.insert(db)
        }
        if !saved { FileLog.shared.addMessage("ReadAloudDataManager.add(document:) failed for \(record.uuid)") }
        return saved
    }

    @discardableResult
    public func add(_ narration: NarrationRecord) -> Bool {
        let record = narration
        let saved = dbQueue.write { db in
            try record.insert(db)
        }
        if !saved { FileLog.shared.addMessage("ReadAloudDataManager.add(narration:) failed for \(record.uuid)") }
        return saved
    }

    /// Creates a document and its first narration together, so a failure between
    /// the two inserts can't leave a document nobody asked for.
    @discardableResult
    public func add(document: ReadAloudDocumentRecord, narration: NarrationRecord) -> Bool {
        let documentRecord = document
        let narrationRecord = narration
        let saved = dbQueue.write { db in
            try documentRecord.insert(db)
            try narrationRecord.insert(db)
        }
        if !saved {
            FileLog.shared.addMessage("ReadAloudDataManager.add(document:narration:) failed for \(documentRecord.uuid)")
        }
        return saved
    }

    @discardableResult
    public func renameDocument(uuid: String, title: String) -> Bool {
        updateDocument(uuid: uuid, [ReadAloudDocumentRecord.Columns.title.set(to: title)])
    }

    /// Moves a queued narration into rendering once its chunk count is known.
    @discardableResult
    public func markRendering(uuid: String, chunkCount: Int) -> Bool {
        updateNarration(uuid: uuid, [
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
        updateNarration(uuid: uuid, [NarrationRecord.Columns.completedChunkCount.set(to: completedChunkCount)])
    }

    @discardableResult
    public func markCompleted(uuid: String, episodeUuid: String, duration: TimeInterval, sizeInBytes: Int64) -> Bool {
        updateNarration(uuid: uuid, [
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
        updateNarration(uuid: uuid, [
            NarrationRecord.Columns.state.set(to: NarrationState.failed.rawValue),
            NarrationRecord.Columns.errorCode.set(to: errorCode),
            NarrationRecord.Columns.errorDetails.set(to: errorDetails),
        ])
    }

    @discardableResult
    public func markCancelled(uuid: String) -> Bool {
        updateNarration(uuid: uuid, [NarrationRecord.Columns.state.set(to: NarrationState.cancelled.rawValue)])
    }

    /// Resets a failed or cancelled narration for another attempt. The
    /// checkpoint is deliberately left alone: already-rendered chunks are still
    /// valid, because the settings that produced them are frozen on this row.
    @discardableResult
    public func markQueued(uuid: String) -> Bool {
        updateNarration(uuid: uuid, [
            NarrationRecord.Columns.state.set(to: NarrationState.queued.rawValue),
            NarrationRecord.Columns.errorCode.set(to: nil),
            NarrationRecord.Columns.errorDetails.set(to: nil),
        ])
    }

    // MARK: - Deletion

    /// The user deleted a generated episode, so the narration that produced it
    /// goes too — but the document survives (ADR-0019). Returns the deleted
    /// narration so the caller can clean up its workspace, or nil when the
    /// episode was an ordinary uploaded file.
    @discardableResult
    public func deleteNarration(episodeUuid: String) -> NarrationRecord? {
        let deleted: NarrationRecord?? = dbQueue.write { db in
            guard let narration = try NarrationRecord
                .filter(NarrationRecord.Columns.episodeUuid == episodeUuid)
                .fetchOne(db) else { return nil }
            _ = try NarrationRecord.filter(NarrationRecord.Columns.uuid == narration.uuid).deleteAll(db)
            return narration
        }
        return deleted ?? nil
    }

    @discardableResult
    public func deleteNarration(uuid: String) -> Bool {
        dbQueue.write { db in
            _ = try NarrationRecord.filter(NarrationRecord.Columns.uuid == uuid).deleteAll(db)
        }
    }

    /// Removes a document and every narration against it, in one transaction.
    /// Deleting the source file and the generated episodes is the caller's job —
    /// this manager owns no filesystem and no episodes — so it returns the
    /// narrations it removed.
    @discardableResult
    public func deleteDocument(uuid: String) -> [NarrationRecord] {
        let removed: [NarrationRecord]? = dbQueue.write { db in
            let narrations = try NarrationRecord
                .filter(NarrationRecord.Columns.documentUuid == uuid)
                .fetchAll(db)
            _ = try NarrationRecord.filter(NarrationRecord.Columns.documentUuid == uuid).deleteAll(db)
            _ = try ReadAloudDocumentRecord.filter(ReadAloudDocumentRecord.Columns.uuid == uuid).deleteAll(db)
            return narrations
        }
        return removed ?? []
    }

    // MARK: - Helpers

    private func updateNarration(uuid: String, _ assignments: [ColumnAssignment]) -> Bool {
        var updatedRows = 0
        let success = dbQueue.write { db in
            updatedRows = try NarrationRecord
                .filter(NarrationRecord.Columns.uuid == uuid)
                .updateAll(db, assignments)
        }
        return success && updatedRows > 0
    }

    private func updateDocument(uuid: String, _ assignments: [ColumnAssignment]) -> Bool {
        var updatedRows = 0
        let success = dbQueue.write { db in
            updatedRows = try ReadAloudDocumentRecord
                .filter(ReadAloudDocumentRecord.Columns.uuid == uuid)
                .updateAll(db, assignments)
        }
        return success && updatedRows > 0
    }
}
