import Foundation
import GRDB
import GRDBMacros
import PocketCastsUtils

/// What a `PendingTranscriptUpload` row uploads when its turn comes
/// (docs/TranscriptContributions.md §1). Stored in the `kind` column.
public enum PendingTranscriptUploadKind: Int32, Sendable, CaseIterable {
    /// A locally Generated transcript: gzipped VTT + audio fingerprint + metadata.
    case contribution = 0
    /// A report that a publisher-Provided transcript exists at a URL.
    case sighting = 1
    /// A transcript accepted by the corpus but still waiting for on-device
    /// summary/chapter generation and one-time token attachment.
    case metadata = 2
}

/// Row record for the `PendingTranscriptUpload` table: one pending
/// contribution or sighting upload, drained serially by the app layer's
/// `TranscriptContributionManager`. Device-local only — nothing here syncs.
/// Date columns are raw `timeIntervalSince1970` Doubles, matching the other
/// row records.
@GRDBRecord(table: "PendingTranscriptUpload")
public struct PendingTranscriptUploadRecord: Equatable, Sendable {
    /// `nil` encodes as NULL on insert so SQLite assigns the AUTOINCREMENT primary key.
    public var id: Int64?

    public var episodeUuid = ""

    public var podcastUuid = ""

    /// Raw `PendingTranscriptUploadKind` value; prefer the typed `uploadKind` accessor.
    public var kind: Int32 = 0

    /// Kind-specific fields captured at enqueue time, as a JSON object:
    /// sighting `{url, format, language}`; contribution
    /// `{engine, modelId, language, diarized, durationSeconds, createdAt}`.
    public var payloadJson = ""

    /// Send attempts made so far; drives the exponential backoff.
    public var attempts: Int32 = 0

    /// Earliest time the next attempt may run; nil = due immediately.
    public var nextAttemptAt: Double?

    public var addedDate: Double = 0

    public init() {}
}

public extension PendingTranscriptUploadRecord {
    /// Typed view over the raw `kind` column. Unknown raw values read as
    /// `.contribution`; in practice the column only ever holds known cases.
    var uploadKind: PendingTranscriptUploadKind {
        get { PendingTranscriptUploadKind(rawValue: kind) ?? .contribution }
        set { kind = newValue.rawValue }
    }
}

/// Data access for the pending transcript-upload queue
/// (docs/TranscriptContributions.md §2): insert on enqueue, `nextDue` +
/// retry-state updates from the drain loop, deletes on success/tombstone.
public struct PendingTranscriptUploadDataManager: Sendable {
    static let tableName = "PendingTranscriptUpload"

    private let dbQueue: GRDBQueue

    init(dbQueue: GRDBQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Insert

    /// Inserts the row unconditionally (contributions: every completed
    /// transcription is its own contribution). A zero `addedDate` is stamped
    /// with the current time.
    @discardableResult
    public func insert(_ record: PendingTranscriptUploadRecord) -> Bool {
        let toSave = recordWithDefaults(record)
        let success = dbQueue.write { db in
            try toSave.insert(db)
        }
        if !success { FileLog.shared.addMessage("PendingTranscriptUploadDataManager.insert failed") }
        return success
    }

    /// Inserts the row unless one with the same `(episodeUuid, kind)` already
    /// exists — the local per-episode dedup for sightings. Returns true only
    /// when a new row was written.
    @discardableResult
    public func insertIfAbsent(_ record: PendingTranscriptUploadRecord) -> Bool {
        let toSave = recordWithDefaults(record)
        let inserted: Bool? = dbQueue.write { db in
            let existing = try PendingTranscriptUploadRecord
                .filter(PendingTranscriptUploadRecord.Columns.episodeUuid == toSave.episodeUuid)
                .filter(PendingTranscriptUploadRecord.Columns.kind == toSave.kind)
                .fetchCount(db)
            guard existing == 0 else { return false }
            try toSave.insert(db)
            return true
        }
        if inserted == nil { FileLog.shared.addMessage("PendingTranscriptUploadDataManager.insertIfAbsent failed") }
        return inserted ?? false
    }

    // MARK: - Drain support

    /// The oldest row that is due at `now` (`nextAttemptAt` unset or in the
    /// past), optionally restricted to one upload kind, or nil when nothing is
    /// ready to send.
    public func nextDue(at now: Date = Date(), kind: PendingTranscriptUploadKind? = nil) -> PendingTranscriptUploadRecord? {
        let dueFilter = PendingTranscriptUploadRecord.Columns.nextAttemptAt == nil
            || PendingTranscriptUploadRecord.Columns.nextAttemptAt <= now.timeIntervalSince1970
        var request = PendingTranscriptUploadRecord
            .filter(dueFilter)
            .order(PendingTranscriptUploadRecord.Columns.addedDate.asc)
        if let kind {
            request = request.filter(PendingTranscriptUploadRecord.Columns.kind == kind.rawValue)
        }
        return dbQueue.fetchOne(request)
    }

    /// The earliest retry deadline after `now`, optionally restricted to one
    /// upload kind. Used to restore the queue's wake-up timer after relaunch.
    public func nextScheduledAttempt(after now: Date = Date(), kind: PendingTranscriptUploadKind? = nil) -> Date? {
        var request = PendingTranscriptUploadRecord
            .filter(PendingTranscriptUploadRecord.Columns.nextAttemptAt > now.timeIntervalSince1970)
            .order(PendingTranscriptUploadRecord.Columns.nextAttemptAt.asc)
        if let kind {
            request = request.filter(PendingTranscriptUploadRecord.Columns.kind == kind.rawValue)
        }
        guard let timestamp = dbQueue.fetchOne(request)?.nextAttemptAt else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    /// Records a failed attempt: the new attempt count and when the row may
    /// next be tried (nil = due immediately).
    @discardableResult
    public func setRetryState(id: Int64, attempts: Int32, nextAttemptAt: Date?) -> Bool {
        let success = dbQueue.write { db in
            _ = try PendingTranscriptUploadRecord
                .filter(PendingTranscriptUploadRecord.Columns.id == id)
                .updateAll(db,
                           PendingTranscriptUploadRecord.Columns.attempts.set(to: attempts),
                           PendingTranscriptUploadRecord.Columns.nextAttemptAt.set(to: nextAttemptAt?.timeIntervalSince1970))
        }
        if !success { FileLog.shared.addMessage("PendingTranscriptUploadDataManager.setRetryState failed") }
        return success
    }

    /// Atomically advances an accepted transcript contribution into its compact
    /// blocked metadata-generation job without exposing the attachment token to
    /// logs or a second table. Returns true only when exactly one contribution
    /// row was transitioned — a missing row or a non-contribution kind reports
    /// failure so the caller never assumes a metadata job was retained.
    @discardableResult
    public func transitionToMetadata(id: Int64, payloadJson: String) -> Bool {
        let updatedCount: Int? = dbQueue.write { db in
            try PendingTranscriptUploadRecord
                .filter(PendingTranscriptUploadRecord.Columns.id == id)
                .filter(PendingTranscriptUploadRecord.Columns.kind == PendingTranscriptUploadKind.contribution.rawValue)
                .updateAll(
                    db,
                    PendingTranscriptUploadRecord.Columns.kind.set(to: PendingTranscriptUploadKind.metadata.rawValue),
                    PendingTranscriptUploadRecord.Columns.payloadJson.set(to: payloadJson),
                    PendingTranscriptUploadRecord.Columns.attempts.set(to: 0),
                    PendingTranscriptUploadRecord.Columns.nextAttemptAt.set(to: nil)
                )
        }
        let success = updatedCount == 1
        if !success { FileLog.shared.addMessage("PendingTranscriptUploadDataManager.transitionToMetadata failed") }
        return success
    }

    // MARK: - Deletes

    /// Removes a single row (sent successfully, or its tombstone check failed).
    @discardableResult
    public func delete(id: Int64) -> Bool {
        let success = dbQueue.write { db in
            _ = try PendingTranscriptUploadRecord
                .filter(PendingTranscriptUploadRecord.Columns.id == id)
                .deleteAll(db)
        }
        if !success { FileLog.shared.addMessage("PendingTranscriptUploadDataManager.delete failed") }
        return success
    }

    /// Removes every pending contribution or metadata row for the episode —
    /// deleting a local transcription cancels both its unsent artifact and any
    /// on-device generation that still needs that artifact. Sighting rows are
    /// untouched because the publisher transcript still exists remotely.
    @discardableResult
    public func deleteContributions(episodeUuid: String) -> Bool {
        let success = dbQueue.write { db in
            _ = try PendingTranscriptUploadRecord
                .filter(PendingTranscriptUploadRecord.Columns.episodeUuid == episodeUuid)
                .filter([
                    PendingTranscriptUploadKind.contribution.rawValue,
                    PendingTranscriptUploadKind.metadata.rawValue,
                ].contains(PendingTranscriptUploadRecord.Columns.kind))
                .deleteAll(db)
        }
        if !success { FileLog.shared.addMessage("PendingTranscriptUploadDataManager.deleteContributions failed") }
        return success
    }

    /// Removes every pending corpus export after contribution consent is
    /// absent or revoked. Accepted server artifacts are handled by the backend
    /// erasure workflow, not this local queue.
    @discardableResult
    public func deleteAll() -> Bool {
        let success = dbQueue.write { db in
            _ = try PendingTranscriptUploadRecord.deleteAll(db)
        }
        if !success { FileLog.shared.addMessage("PendingTranscriptUploadDataManager.deleteAll failed") }
        return success
    }

    // MARK: - Introspection

    /// Number of rows still queued, regardless of due time.
    public func count() -> Int {
        dbQueue.count(PendingTranscriptUploadRecord.self)
    }

    /// Every queued row, oldest first. Powers tests and debug accounting.
    public func allRecords() -> [PendingTranscriptUploadRecord] {
        dbQueue.fetchAll(PendingTranscriptUploadRecord.order(PendingTranscriptUploadRecord.Columns.addedDate.asc))
    }

    // MARK: - Private

    private func recordWithDefaults(_ record: PendingTranscriptUploadRecord) -> PendingTranscriptUploadRecord {
        var toSave = record
        if toSave.addedDate == 0 {
            toSave.addedDate = Date().timeIntervalSince1970
        }
        return toSave
    }
}
