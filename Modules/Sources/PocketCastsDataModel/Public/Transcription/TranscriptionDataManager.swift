import PocketCastsUtils
import Foundation
import GRDB

/// Data access for locally generated diarized transcriptions: the per-episode
/// `EpisodeTranscription` state row. Device-local only — nothing here syncs.
///
/// The searchable segments live in the unified transcript search index (see
/// `TranscriptSearchDataManager`, `source: .generated`); callers deleting a
/// transcription are responsible for removing its index rows there too.
public struct TranscriptionDataManager: Sendable {
    static let tableName = "EpisodeTranscription"

    private let dbQueue: GRDBQueue

    init(dbQueue: GRDBQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Records

    /// Returns the transcription record for an episode, or nil when none exists.
    public func find(episodeUuid: String) -> EpisodeTranscriptionRecord? {
        dbQueue.fetchOne(EpisodeTranscriptionRecord.self, key: episodeUuid)
    }

    /// Inserts the record, or replaces the existing row for the same `episodeUuid`.
    @discardableResult
    public func upsert(_ record: EpisodeTranscriptionRecord) -> Bool {
        let success = dbQueue.write { db in
            try record.save(db)
        }
        if !success { FileLog.shared.addMessage("TranscriptionDataManager.upsert failed") }
        return success
    }

    /// Moves the episode's record to `status`, storing (or clearing) `errorMessage`
    /// and bumping `updatedAt`.
    @discardableResult
    public func setStatus(episodeUuid: String, status: TranscriptionStatus, errorMessage: String? = nil) -> Bool {
        update(episodeUuid: episodeUuid,
               operation: "setStatus",
               EpisodeTranscriptionRecord.Columns.status.set(to: status.rawValue),
               EpisodeTranscriptionRecord.Columns.errorMessage.set(to: errorMessage))
    }

    /// Stores the provider-side job id so polling can resume across launches.
    @discardableResult
    public func setRemoteJobId(episodeUuid: String, jobId: String?) -> Bool {
        update(episodeUuid: episodeUuid,
               operation: "setRemoteJobId",
               EpisodeTranscriptionRecord.Columns.remoteJobId.set(to: jobId))
    }

    /// Stores the user's speaker renames as a JSON object, e.g. `{"Speaker 1":"Alice"}`.
    @discardableResult
    public func setSpeakerNames(episodeUuid: String, namesJSON: String?) -> Bool {
        update(episodeUuid: episodeUuid,
               operation: "setSpeakerNames",
               EpisodeTranscriptionRecord.Columns.speakerNames.set(to: namesJSON))
    }

    /// Records that still need work — `queued` or `processing` — oldest first.
    public func pendingRecords() -> [EpisodeTranscriptionRecord] {
        let pendingStatuses = [TranscriptionStatus.queued.rawValue, TranscriptionStatus.processing.rawValue]
        let request = EpisodeTranscriptionRecord
            .filter(pendingStatuses.contains(EpisodeTranscriptionRecord.Columns.status))
            .order(EpisodeTranscriptionRecord.Columns.createdAt.asc)
        return dbQueue.fetchAll(request)
    }

    /// Every transcription record regardless of status, newest first. Powers the
    /// settings storage accounting and its "Clear All" action.
    public func allRecords() -> [EpisodeTranscriptionRecord] {
        let request = EpisodeTranscriptionRecord
            .order(EpisodeTranscriptionRecord.Columns.createdAt.desc)
        return dbQueue.fetchAll(request)
    }

    /// Number of episodes with a completed transcription.
    public func completedCount() -> Int {
        dbQueue.count(EpisodeTranscriptionRecord.self,
                      filter: EpisodeTranscriptionRecord.Columns.status == TranscriptionStatus.completed.rawValue)
    }

    /// Deletes the episode's record. Deleting the VTT artifact on disk and the
    /// unified search-index rows (`TranscriptSearchDataManager`, `.generated`) is
    /// the app layer's job.
    @discardableResult
    public func delete(episodeUuid: String) -> Bool {
        let success = dbQueue.write { db in
            _ = try EpisodeTranscriptionRecord
                .filter(EpisodeTranscriptionRecord.Columns.episodeUuid == episodeUuid)
                .deleteAll(db)
        }
        if !success { FileLog.shared.addMessage("TranscriptionDataManager.delete failed") }
        return success
    }
}

// MARK: - Private

private extension TranscriptionDataManager {
    /// Applies `assignments` (plus an `updatedAt` bump) to the episode's record.
    func update(episodeUuid: String, operation: String, _ assignments: ColumnAssignment...) -> Bool {
        let allAssignments = assignments + [EpisodeTranscriptionRecord.Columns.updatedAt.set(to: Date().timeIntervalSince1970)]
        let success = dbQueue.write { db in
            _ = try EpisodeTranscriptionRecord
                .filter(EpisodeTranscriptionRecord.Columns.episodeUuid == episodeUuid)
                .updateAll(db, allAssignments)
        }
        if !success { FileLog.shared.addMessage("TranscriptionDataManager.\(operation) failed") }
        return success
    }
}
