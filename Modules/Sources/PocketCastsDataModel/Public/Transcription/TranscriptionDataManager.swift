import PocketCastsUtils
import Foundation
import GRDB

/// One searchable transcript segment (an FTS5 row in `TranscriptionSegmentFTS`).
/// Segments are FTS-only: the canonical transcript artifact is the VTT file on disk.
public struct TranscriptionSegment: Equatable, Sendable {
    public let index: Int
    public let text: String
    public let startTime: Double
    public let speaker: String?

    public init(index: Int, text: String, startTime: Double, speaker: String? = nil) {
        self.index = index
        self.text = text
        self.startTime = startTime
        self.speaker = speaker
    }
}

/// A cross-episode transcript search hit. `snippet` is the matched excerpt with the
/// matched terms wrapped in ``highlightStart``/``highlightEnd`` markers.
public struct TranscriptionSearchResult: Equatable, Sendable {
    public static let highlightStart = "<b>"
    public static let highlightEnd = "</b>"

    public let episodeUuid: String
    public let podcastUuid: String?
    public let segmentIndex: Int
    public let startTime: Double
    public let speaker: String?
    public let snippet: String

    public init(episodeUuid: String, podcastUuid: String?, segmentIndex: Int, startTime: Double, speaker: String?, snippet: String) {
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.segmentIndex = segmentIndex
        self.startTime = startTime
        self.speaker = speaker
        self.snippet = snippet
    }
}

/// Data access for locally generated diarized transcriptions: the per-episode
/// `EpisodeTranscription` state row plus the `TranscriptionSegmentFTS` FTS5 index that
/// powers cross-episode transcript search. Device-local only — nothing here syncs.
///
/// FTS5 virtual tables, `snippet()` and `bm25()` have no GRDB query-interface
/// equivalent, so the segment operations use raw SQL; everything on the record table
/// goes through the query interface.
public struct TranscriptionDataManager: Sendable {
    static let tableName = "EpisodeTranscription"
    static let ftsTableName = "TranscriptionSegmentFTS"

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

    /// Deletes the episode's record and all of its FTS segment rows in one transaction.
    /// Deleting the VTT artifact on disk is the app layer's job (it owns `filePath`).
    @discardableResult
    public func delete(episodeUuid: String) -> Bool {
        let success = dbQueue.write { db in
            try EpisodeTranscriptionRecord
                .filter(EpisodeTranscriptionRecord.Columns.episodeUuid == episodeUuid)
                .deleteAll(db)
            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 virtual table has no GRDB query-interface equivalent
            try db.execute(sql: "DELETE FROM \(Self.ftsTableName) WHERE episodeUuid = ?", arguments: [episodeUuid])
        }
        if !success { FileLog.shared.addMessage("TranscriptionDataManager.delete failed") }
        return success
    }

    // MARK: - Segments (FTS)

    /// Replaces the episode's searchable segments: deletes any existing FTS rows and
    /// batch-inserts the new ones inside a single write transaction, so a re-run
    /// (or a crash mid-way) can never leave duplicated or partial segment sets.
    @discardableResult
    public func replaceSegments(episodeUuid: String, podcastUuid: String?, segments: [TranscriptionSegment]) -> Bool {
        let success = dbQueue.write { db in
            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 virtual table has no GRDB query-interface equivalent
            try db.execute(sql: "DELETE FROM \(Self.ftsTableName) WHERE episodeUuid = ?", arguments: [episodeUuid])

            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 virtual table has no GRDB query-interface equivalent
            let insert = try db.cachedStatement(sql: """
            INSERT INTO \(Self.ftsTableName) (text, episodeUuid, podcastUuid, segmentIndex, startTime, speaker)
            VALUES (?, ?, ?, ?, ?, ?)
            """)
            for segment in segments {
                try insert.execute(arguments: [segment.text, episodeUuid, podcastUuid, segment.index, segment.startTime, segment.speaker])
            }
        }
        if !success { FileLog.shared.addMessage("TranscriptionDataManager.replaceSegments failed") }
        return success
    }

    /// Full-text search across every transcribed episode, most relevant first
    /// (BM25). The last token matches as a prefix so results appear while typing.
    /// Returns [] for queries with no searchable tokens.
    public func searchSegments(query: String, limit: Int = 50) -> [TranscriptionSearchResult] {
        guard let match = Self.sanitizeFTSQuery(query) else { return [] }

        // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 MATCH/snippet()/bm25() have no GRDB query-interface equivalent
        let sql = """
        SELECT episodeUuid, podcastUuid, segmentIndex, startTime, speaker,
               snippet(\(Self.ftsTableName), 0, '\(TranscriptionSearchResult.highlightStart)', '\(TranscriptionSearchResult.highlightEnd)', '…', 12) AS snippet
        FROM \(Self.ftsTableName)
        WHERE \(Self.ftsTableName) MATCH ?
        ORDER BY bm25(\(Self.ftsTableName))
        LIMIT ?
        """
        let rows = dbQueue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: [match, limit])
        } ?? []

        return rows.map { row in
            TranscriptionSearchResult(
                episodeUuid: row["episodeUuid"] ?? "",
                podcastUuid: row["podcastUuid"],
                segmentIndex: row["segmentIndex"] ?? 0,
                startTime: row["startTime"] ?? 0,
                speaker: row["speaker"],
                snippet: row["snippet"] ?? ""
            )
        }
    }

    /// Turns arbitrary user input into a safe FTS5 MATCH expression: every
    /// whitespace-separated token is double-quoted (neutralizing operators like
    /// AND/OR/NEAR, parentheses and column filters), and the last token gets a `*`
    /// prefix marker. Tokens with no letters or digits are dropped (the unicode61
    /// tokenizer can't match them anyway). Returns nil when nothing searchable remains.
    static func sanitizeFTSQuery(_ query: String) -> String? {
        let tokens = query
            .split(whereSeparator: \.isWhitespace)
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
        guard !tokens.isEmpty else { return nil }

        var quoted = tokens.map { "\"\($0)\"" }
        quoted[quoted.count - 1] += "*"
        return quoted.joined(separator: " ")
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
