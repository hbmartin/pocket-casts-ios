import Foundation
import GRDB
import GRDBMacros
import PocketCastsUtils

/// One searchable segment of a viewed podcast-provided transcript (an FTS5 row in
/// `TranscriptCueIndex`). Segments are FTS-only: the canonical transcript stays in
/// the URL cache, exactly as before the search index existed.
public struct TranscriptIndexCue: Equatable, Sendable {
    /// Ordinal of the segment within its episode's indexed set.
    public let index: Int
    public let text: String
    public let startTime: Double
    public let endTime: Double

    public init(index: Int, text: String, startTime: Double, endTime: Double) {
        self.index = index
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// A library-wide transcript search hit. `snippet` is the matched excerpt with the
/// matched terms wrapped in ``highlightStart``/``highlightEnd`` markers.
public struct TranscriptSearchHit: Hashable, Sendable {
    public static let highlightStart = "<b>"
    public static let highlightEnd = "</b>"

    public let episodeUuid: String
    public let podcastUuid: String?
    public let cueIndex: Int
    public let startTime: Double
    public let endTime: Double
    public let snippet: String

    public init(episodeUuid: String, podcastUuid: String?, cueIndex: Int, startTime: Double, endTime: Double, snippet: String) {
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.cueIndex = cueIndex
        self.startTime = startTime
        self.endTime = endTime
        self.snippet = snippet
    }
}

/// Bookkeeping row for an indexed episode (`TranscriptIndexMeta` table): powers the
/// dedupe check and the LRU eviction accounting. Device-local only — nothing syncs.
@GRDBRecord(table: "TranscriptIndexMeta")
public struct TranscriptIndexMetaRecord: Equatable, Sendable {
    public var episodeUuid = ""

    public var podcastUuid: String?

    /// When the episode was (re)indexed, as `timeIntervalSince1970`. LRU eviction
    /// removes the oldest values first.
    public var indexedDate: Double = 0

    /// Number of FTS segments written for the episode.
    public var cueCount: Int32 = 0

    /// UTF-8 byte size of all indexed segment text, feeding the total-size cap.
    public var textBytes: Int64 = 0

    public init() {}
}

/// Data access for the library-wide transcript search index: an FTS5 table over the
/// cue text of viewed podcast-provided transcripts (`TranscriptCueIndex`) plus the
/// `TranscriptIndexMeta` bookkeeping table. Locally generated transcripts are a
/// separate corpus with their own index (see `TranscriptionDataManager`).
///
/// FTS5 virtual tables, `snippet()` and `bm25()` have no GRDB query-interface
/// equivalent, so the FTS operations use raw SQL; everything on the meta table goes
/// through the query interface.
///
/// Migration 81 deliberately swallows an FTS5 creation failure (SQLite builds
/// without the FTS5 module), creating neither table. `isAvailable` probes for the
/// meta table — which is only created after the FTS5 table succeeded — and every
/// operation no-ops when the probe fails, so the feature self-disables.
public struct TranscriptIndexDataManager: Sendable {
    static let ftsTableName = "TranscriptCueIndex"
    static let metaTableName = "TranscriptIndexMeta"

    /// Eviction caps: at most this many indexed episodes…
    static let defaultMaxIndexedEpisodes = 500
    /// …and at most this much indexed text (UTF-8 bytes) across all episodes.
    static let defaultMaxTotalTextBytes: Int64 = 50 * 1024 * 1024

    private let dbQueue: GRDBQueue
    private let maxIndexedEpisodes: Int
    private let maxTotalTextBytes: Int64

    /// False when migration 81 could not create the FTS5 index (probed once at
    /// startup, after migrations ran). All operations no-op while false.
    public let isAvailable: Bool

    init(dbQueue: GRDBQueue,
         maxIndexedEpisodes: Int = TranscriptIndexDataManager.defaultMaxIndexedEpisodes,
         maxTotalTextBytes: Int64 = TranscriptIndexDataManager.defaultMaxTotalTextBytes) {
        self.dbQueue = dbQueue
        self.maxIndexedEpisodes = maxIndexedEpisodes
        self.maxTotalTextBytes = maxTotalTextBytes
        isAvailable = dbQueue.read { db in
            try db.tableExists(Self.metaTableName)
        } ?? false
    }

    // MARK: - Indexing

    /// Replaces the episode's searchable segments and its meta row inside a single
    /// write transaction (a re-run or a crash mid-way can never leave duplicated or
    /// partial segment sets), then enforces the LRU caps — evicting oldest-indexed
    /// episodes first, never the episode just indexed.
    @discardableResult
    public func index(episodeUuid: String, podcastUuid: String?, cues: [TranscriptIndexCue], indexedDate: Date = Date()) -> Bool {
        guard isAvailable else { return false }

        let textBytes = cues.reduce(into: Int64(0)) { $0 += Int64($1.text.utf8.count) }
        let success = dbQueue.write { db in
            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 virtual table has no GRDB query-interface equivalent
            try db.execute(sql: "DELETE FROM \(Self.ftsTableName) WHERE episodeUuid = ?", arguments: [episodeUuid])

            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 virtual table has no GRDB query-interface equivalent
            let insert = try db.cachedStatement(sql: """
            INSERT INTO \(Self.ftsTableName) (text, episodeUuid, podcastUuid, cueIndex, startTime, endTime)
            VALUES (?, ?, ?, ?, ?, ?)
            """)
            for cue in cues {
                try insert.execute(arguments: [cue.text, episodeUuid, podcastUuid, cue.index, cue.startTime, cue.endTime])
            }

            var meta = TranscriptIndexMetaRecord()
            meta.episodeUuid = episodeUuid
            meta.podcastUuid = podcastUuid
            meta.indexedDate = indexedDate.timeIntervalSince1970
            meta.cueCount = Int32(cues.count)
            meta.textBytes = textBytes
            try meta.save(db)

            try enforceCaps(db: db, keeping: episodeUuid)
        }
        if !success { FileLog.shared.addMessage("TranscriptIndexDataManager.index failed") }
        return success
    }

    /// True when the episode already has an indexed transcript (the indexer's
    /// dedupe check).
    public func isIndexed(episodeUuid: String) -> Bool {
        guard isAvailable else { return false }
        return dbQueue.fetchOne(TranscriptIndexMetaRecord.self, key: episodeUuid) != nil
    }

    /// Number of episodes currently in the index.
    public func indexedEpisodeCount() -> Int {
        guard isAvailable else { return 0 }
        return dbQueue.count(TranscriptIndexMetaRecord.self)
    }

    /// Drops every indexed segment and all bookkeeping rows.
    @discardableResult
    public func removeAll() -> Bool {
        guard isAvailable else { return false }
        let success = dbQueue.write { db in
            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 virtual table has no GRDB query-interface equivalent
            try db.execute(sql: "DELETE FROM \(Self.ftsTableName)")
            _ = try TranscriptIndexMetaRecord.deleteAll(db)
        }
        if !success { FileLog.shared.addMessage("TranscriptIndexDataManager.removeAll failed") }
        return success
    }

    // MARK: - Search

    /// Full-text search across every indexed transcript, most relevant first
    /// (BM25). The last token matches as a prefix so results appear while typing.
    /// Returns [] for queries with no searchable tokens (and while unavailable).
    public func search(term: String, limit: Int = 50) -> [TranscriptSearchHit] {
        guard isAvailable, let match = TranscriptionDataManager.sanitizeFTSQuery(term) else { return [] }

        // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 MATCH/snippet()/bm25() have no GRDB query-interface equivalent
        let sql = """
        SELECT episodeUuid, podcastUuid, cueIndex, startTime, endTime,
               snippet(\(Self.ftsTableName), 0, '\(TranscriptSearchHit.highlightStart)', '\(TranscriptSearchHit.highlightEnd)', '…', 12) AS snippet
        FROM \(Self.ftsTableName)
        WHERE \(Self.ftsTableName) MATCH ?
        ORDER BY bm25(\(Self.ftsTableName))
        LIMIT ?
        """
        let rows = dbQueue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: [match, limit])
        } ?? []

        return rows.map { row in
            TranscriptSearchHit(
                episodeUuid: row["episodeUuid"] ?? "",
                podcastUuid: row["podcastUuid"],
                cueIndex: row["cueIndex"] ?? 0,
                startTime: row["startTime"] ?? 0,
                endTime: row["endTime"] ?? 0,
                snippet: row["snippet"] ?? ""
            )
        }
    }

    // MARK: - Eviction

    /// Evicts least-recently-indexed episodes until both caps hold. The episode
    /// just indexed is never a victim: when it alone exceeds the byte cap it gets
    /// a grace pass (it will be the first evicted by the next episode's indexing).
    private func enforceCaps(db: Database, keeping keptEpisodeUuid: String) throws {
        while true {
            let count = try TranscriptIndexMetaRecord.fetchCount(db)
            let totalBytes = try TranscriptIndexMetaRecord
                .select(sum(TranscriptIndexMetaRecord.Columns.textBytes), as: Int64.self)
                .fetchOne(db) ?? 0
            guard count > maxIndexedEpisodes || totalBytes > maxTotalTextBytes else { return }

            guard let victim = try TranscriptIndexMetaRecord
                .filter(TranscriptIndexMetaRecord.Columns.episodeUuid != keptEpisodeUuid)
                .order(TranscriptIndexMetaRecord.Columns.indexedDate.asc, TranscriptIndexMetaRecord.Columns.episodeUuid.asc)
                .fetchOne(db) else { return }

            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - FTS5 virtual table has no GRDB query-interface equivalent
            try db.execute(sql: "DELETE FROM \(Self.ftsTableName) WHERE episodeUuid = ?", arguments: [victim.episodeUuid])
            _ = try victim.delete(db)
        }
    }
}
