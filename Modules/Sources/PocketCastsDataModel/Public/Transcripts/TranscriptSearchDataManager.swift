import Foundation
import GRDB
import GRDBMacros
import PocketCastsUtils

/// Which corpus a transcript segment came from. The unified index carries both;
/// eviction policy and a few UI affordances differ by source.
public enum TranscriptSource: String, Sendable, CaseIterable {
    /// A podcast-provided transcript fetched from the feed (re-fetchable, so
    /// evictable under the byte cap).
    case provided
    /// A locally generated (diarized) transcription. Expensive to recreate and
    /// backed by a VTT artifact the user owns — never evicted.
    case generated
}

/// One searchable transcript segment (an FTS5 row in `TranscriptSegmentIndex`).
/// Segments are FTS-only: the canonical transcript is the feed's document (URL
/// cache) for `provided`, or the VTT artifact on disk for `generated`.
public struct TranscriptSearchSegment: Equatable, Sendable {
    /// Ordinal of the segment within its episode's indexed set.
    public let index: Int
    public let text: String
    public let startTime: Double
    public let endTime: Double?
    public let speaker: String?

    public init(index: Int, text: String, startTime: Double, endTime: Double? = nil, speaker: String? = nil) {
        self.index = index
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.speaker = speaker
    }
}

/// A library-wide transcript search hit. `snippet` is the matched excerpt with the
/// matched terms wrapped in ``highlightStart``/``highlightEnd`` markers.
public struct TranscriptSearchHit: Hashable, Sendable {
    public static let highlightStart = "<b>"
    public static let highlightEnd = "</b>"

    public let episodeUuid: String
    public let podcastUuid: String?
    public let segmentIndex: Int
    public let startTime: Double
    public let endTime: Double?
    public let speaker: String?
    public let source: TranscriptSource
    public let snippet: String

    public init(episodeUuid: String, podcastUuid: String?, segmentIndex: Int, startTime: Double, endTime: Double?, speaker: String?, source: TranscriptSource, snippet: String) {
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.segmentIndex = segmentIndex
        self.startTime = startTime
        self.endTime = endTime
        self.speaker = speaker
        self.source = source
        self.snippet = snippet
    }
}

/// Bookkeeping row for an indexed (episode, source) pair (`TranscriptSearchIndexMeta`
/// table): powers the dedupe check and the byte-cap eviction accounting. Device-local
/// only — nothing syncs.
@GRDBRecord(table: "TranscriptSearchIndexMeta")
public struct TranscriptSearchIndexMetaRecord: Equatable, Sendable {
    public var episodeUuid = ""

    /// `TranscriptSource` raw value; part of the primary key.
    public var source = ""

    public var podcastUuid: String?

    /// When the pair was (re)indexed, as `timeIntervalSince1970`. Eviction removes
    /// the oldest `provided` values first.
    public var indexedDate: Double = 0

    /// Number of FTS segments written for the pair.
    public var segmentCount: Int32 = 0

    /// UTF-8 byte size of all indexed segment text, feeding the total-size cap.
    public var textBytes: Int64 = 0

    public init() {}
}

/// Data access for the unified library-wide transcript search index: one FTS5 table
/// (`TranscriptSegmentIndex`) over both corpora — podcast-provided transcript cues
/// and locally generated transcription segments — plus the `TranscriptSearchIndexMeta`
/// bookkeeping table. Migration 82 merged the two former indexes
/// (`TranscriptCueIndex`, migration 81 and `TranscriptionSegmentFTS`, migration 78)
/// into this one.
///
/// FTS5 virtual tables, `snippet()` and `bm25()` have no GRDB query-interface
/// equivalent, so the FTS operations use raw SQL; everything on the meta table goes
/// through the query interface.
///
/// Migration 82 deliberately swallows an FTS5 creation failure (SQLite builds
/// without the FTS5 module), creating neither table. `isAvailable` probes for the
/// meta table — which is only created after the FTS5 table succeeded — and every
/// operation no-ops when the probe fails, so the feature self-disables.
public struct TranscriptSearchDataManager: Sendable {
    static let ftsTableName = "TranscriptSegmentIndex"
    static let metaTableName = "TranscriptSearchIndexMeta"

    /// Safety cap on total indexed text (UTF-8 bytes) across both corpora. There is
    /// deliberately no episode-count cap: transcripts are small and eviction would
    /// silently un-index downloaded episodes. Only `provided` rows are ever evicted,
    /// so a generated corpus larger than the cap is tolerated.
    static let defaultMaxTotalTextBytes: Int64 = 200 * 1024 * 1024

    private let dbQueue: GRDBQueue
    private let maxTotalTextBytes: Int64

    /// False when migration 82 could not create the FTS5 index (probed once at
    /// startup, after migrations ran). All operations no-op while false.
    public let isAvailable: Bool

    init(dbQueue: GRDBQueue, maxTotalTextBytes: Int64 = TranscriptSearchDataManager.defaultMaxTotalTextBytes) {
        self.dbQueue = dbQueue
        self.maxTotalTextBytes = maxTotalTextBytes
        isAvailable = dbQueue.read { db in
            try db.tableExists(Self.metaTableName)
        } ?? false
    }

    // MARK: - Indexing

    /// Replaces the (episode, source) pair's searchable segments and its meta row
    /// inside a single write transaction (a re-run or a crash mid-way can never
    /// leave duplicated or partial segment sets), then enforces the byte cap —
    /// evicting oldest-indexed `provided` pairs first, never the pair just indexed
    /// and never `generated` rows.
    @discardableResult
    public func replaceSegments(episodeUuid: String, podcastUuid: String?, source: TranscriptSource, segments: [TranscriptSearchSegment], indexedDate: Date = Date()) -> Bool {
        guard isAvailable else { return false }

        let textBytes = segments.reduce(into: Int64(0)) { $0 += Int64($1.text.utf8.count) }
        let success = dbQueue.write { db in
            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 virtual table has no GRDB query-interface equivalent
            try db.execute(sql: "DELETE FROM \(Self.ftsTableName) WHERE episodeUuid = ? AND source = ?", arguments: [episodeUuid, source.rawValue])

            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 virtual table has no GRDB query-interface equivalent
            let insert = try db.cachedStatement(sql: """
            INSERT INTO \(Self.ftsTableName) (text, episodeUuid, podcastUuid, segmentIndex, startTime, endTime, speaker, source)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """)
            for segment in segments {
                try insert.execute(arguments: [segment.text, episodeUuid, podcastUuid, segment.index, segment.startTime, segment.endTime, segment.speaker, source.rawValue])
            }

            var meta = TranscriptSearchIndexMetaRecord()
            meta.episodeUuid = episodeUuid
            meta.source = source.rawValue
            meta.podcastUuid = podcastUuid
            meta.indexedDate = indexedDate.timeIntervalSince1970
            meta.segmentCount = Int32(segments.count)
            meta.textBytes = textBytes
            try meta.save(db)

            try enforceCaps(db: db, keeping: episodeUuid)
        }
        if !success { FileLog.shared.addMessage("TranscriptSearchDataManager.replaceSegments failed") }
        return success
    }

    /// True when the (episode, source) pair already has indexed segments (the
    /// indexer's dedupe check).
    public func isIndexed(episodeUuid: String, source: TranscriptSource) -> Bool {
        guard isAvailable else { return false }
        // fetchCount keeps the read's return type non-optional: dbQueue.read wraps
        // the result in its own optional, and Record?? would make "no row" != nil.
        let found = dbQueue.read { db in
            try TranscriptSearchIndexMetaRecord
                .filter(TranscriptSearchIndexMetaRecord.Columns.episodeUuid == episodeUuid)
                .filter(TranscriptSearchIndexMetaRecord.Columns.source == source.rawValue)
                .fetchCount(db) > 0
        }
        return found ?? false
    }

    /// Number of indexed (episode, source) pairs, optionally for one source only.
    public func indexedEpisodeCount(source: TranscriptSource? = nil) -> Int {
        guard isAvailable else { return 0 }
        if let source {
            return dbQueue.count(TranscriptSearchIndexMetaRecord.self,
                                 filter: TranscriptSearchIndexMetaRecord.Columns.source == source.rawValue)
        }
        return dbQueue.count(TranscriptSearchIndexMetaRecord.self)
    }

    /// Drops the (episode, source) pair's segments and bookkeeping row.
    @discardableResult
    public func delete(episodeUuid: String, source: TranscriptSource) -> Bool {
        guard isAvailable else { return false }
        let success = dbQueue.write { db in
            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 virtual table has no GRDB query-interface equivalent
            try db.execute(sql: "DELETE FROM \(Self.ftsTableName) WHERE episodeUuid = ? AND source = ?", arguments: [episodeUuid, source.rawValue])
            _ = try TranscriptSearchIndexMetaRecord
                .filter(TranscriptSearchIndexMetaRecord.Columns.episodeUuid == episodeUuid)
                .filter(TranscriptSearchIndexMetaRecord.Columns.source == source.rawValue)
                .deleteAll(db)
        }
        if !success { FileLog.shared.addMessage("TranscriptSearchDataManager.delete failed") }
        return success
    }

    /// Drops every indexed segment and bookkeeping row, optionally for one source only.
    @discardableResult
    public func removeAll(source: TranscriptSource? = nil) -> Bool {
        guard isAvailable else { return false }
        let success = dbQueue.write { db in
            if let source {
                // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 virtual table has no GRDB query-interface equivalent
                try db.execute(sql: "DELETE FROM \(Self.ftsTableName) WHERE source = ?", arguments: [source.rawValue])
                _ = try TranscriptSearchIndexMetaRecord
                    .filter(TranscriptSearchIndexMetaRecord.Columns.source == source.rawValue)
                    .deleteAll(db)
            } else {
                // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 virtual table has no GRDB query-interface equivalent
                try db.execute(sql: "DELETE FROM \(Self.ftsTableName)")
                _ = try TranscriptSearchIndexMetaRecord.deleteAll(db)
            }
        }
        if !success { FileLog.shared.addMessage("TranscriptSearchDataManager.removeAll failed") }
        return success
    }

    // MARK: - Search

    /// Full-text search across every indexed transcript, most relevant first
    /// (BM25), optionally restricted to one source. The last token matches as a
    /// prefix so results appear while typing. Returns [] for queries with no
    /// searchable tokens (and while unavailable).
    public func search(term: String, limit: Int = 50, source: TranscriptSource? = nil) -> [TranscriptSearchHit] {
        guard isAvailable, let match = Self.sanitizeFTSQuery(term) else { return [] }

        let sourceFilter = source != nil ? "AND source = ?" : ""
        // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 MATCH/snippet()/bm25() have no GRDB query-interface equivalent
        let sql = """
        SELECT episodeUuid, podcastUuid, segmentIndex, startTime, endTime, speaker, source,
               snippet(\(Self.ftsTableName), 0, '\(TranscriptSearchHit.highlightStart)', '\(TranscriptSearchHit.highlightEnd)', '…', 12) AS snippet
        FROM \(Self.ftsTableName)
        WHERE \(Self.ftsTableName) MATCH ? \(sourceFilter)
        ORDER BY bm25(\(Self.ftsTableName))
        LIMIT ?
        """
        var arguments: [(any DatabaseValueConvertible)?] = [match]
        if let source { arguments.append(source.rawValue) }
        arguments.append(limit)

        let rows = dbQueue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        } ?? []

        return rows.map { row in
            TranscriptSearchHit(
                episodeUuid: row["episodeUuid"] ?? "",
                podcastUuid: row["podcastUuid"],
                segmentIndex: row["segmentIndex"] ?? 0,
                startTime: row["startTime"] ?? 0,
                endTime: row["endTime"],
                speaker: row["speaker"],
                source: TranscriptSource(rawValue: row["source"] ?? "") ?? .provided,
                snippet: row["snippet"] ?? ""
            )
        }
    }

    /// Turns arbitrary user input into a safe FTS5 MATCH expression: every
    /// whitespace-separated token is double-quoted (neutralizing operators like
    /// AND/OR/NEAR, parentheses and column filters), and the last token gets a `*`
    /// prefix marker. Tokens with no letters or digits are dropped (the unicode61
    /// tokenizer can't match them anyway). Returns nil when nothing searchable remains.
    public static func sanitizeFTSQuery(_ query: String) -> String? {
        let tokens = query
            .split(whereSeparator: \.isWhitespace)
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
        guard !tokens.isEmpty else { return nil }

        var quoted = tokens.map { "\"\($0)\"" }
        quoted[quoted.count - 1] += "*"
        return quoted.joined(separator: " ")
    }

    // MARK: - Eviction

    /// Evicts `provided` pairs until the byte cap holds, preferring episodes that
    /// no longer have a library row (their transcript is re-fetchable and nothing
    /// can play the hit anyway), then least-recently-indexed. `generated` rows are
    /// never victims — they are expensive to recreate — so the loop terminates,
    /// over cap, once only generated rows (and the just-indexed pair) remain.
    private func enforceCaps(db: Database, keeping keptEpisodeUuid: String) throws {
        while true {
            let totalBytes = try TranscriptSearchIndexMetaRecord
                .select(sum(TranscriptSearchIndexMetaRecord.Columns.textBytes), as: Int64.self)
                .fetchOne(db) ?? 0
            guard totalBytes > maxTotalTextBytes else { return }

            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - the departed-episode preference needs an EXISTS subquery with no query-interface equivalent
            let victimUuid = try String.fetchOne(db, sql: """
            SELECT episodeUuid FROM \(Self.metaTableName) m
            WHERE m.source = ? AND m.episodeUuid != ?
            ORDER BY EXISTS (SELECT 1 FROM SJEpisode e WHERE e.uuid = m.episodeUuid) ASC,
                     m.indexedDate ASC, m.episodeUuid ASC
            LIMIT 1
            """, arguments: [TranscriptSource.provided.rawValue, keptEpisodeUuid])
            guard let victimUuid else { return }

            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 virtual table has no GRDB query-interface equivalent
            try db.execute(sql: "DELETE FROM \(Self.ftsTableName) WHERE episodeUuid = ? AND source = ?", arguments: [victimUuid, TranscriptSource.provided.rawValue])
            _ = try TranscriptSearchIndexMetaRecord
                .filter(TranscriptSearchIndexMetaRecord.Columns.episodeUuid == victimUuid)
                .filter(TranscriptSearchIndexMetaRecord.Columns.source == TranscriptSource.provided.rawValue)
                .deleteAll(db)
        }
    }
}
