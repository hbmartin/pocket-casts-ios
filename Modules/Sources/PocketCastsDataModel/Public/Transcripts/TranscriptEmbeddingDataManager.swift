import Foundation
import GRDB
import GRDBMacros
import PocketCastsUtils

/// Identity of the embedding model a vector was produced with. Rows whose model
/// info doesn't match the current model are invisible to `candidates` and
/// re-listed by `pendingPairs` — an OS model-revision bump re-embeds lazily.
public struct TranscriptEmbeddingModelInfo: Equatable, Sendable {
    public let identifier: String
    public let revision: Int
    public let dimension: Int
    /// Vector encoding, e.g. "float16" (little-endian, L2-normalized).
    public let quantization: String

    public init(identifier: String, revision: Int, dimension: Int, quantization: String) {
        self.identifier = identifier
        self.revision = revision
        self.dimension = dimension
        self.quantization = quantization
    }
}

/// One embedding window to store: a run of consecutive corpus segments embedded
/// as a single vector. `vector` is the encoded (quantized, L2-normalized) blob.
public struct TranscriptEmbeddingWindow: Equatable, Sendable {
    public let windowIndex: Int
    public let startSegmentIndex: Int
    public let endSegmentIndex: Int
    public let startTime: Double
    public let endTime: Double?
    /// Head of the window's text (~280 chars), the semantic hit's snippet
    /// substitute — FTS `snippet()` doesn't exist for vector matches.
    public let textPreview: String
    public let vector: Data

    public init(windowIndex: Int, startSegmentIndex: Int, endSegmentIndex: Int, startTime: Double, endTime: Double? = nil, textPreview: String, vector: Data) {
        self.windowIndex = windowIndex
        self.startSegmentIndex = startSegmentIndex
        self.endSegmentIndex = endSegmentIndex
        self.startTime = startTime
        self.endTime = endTime
        self.textPreview = textPreview
        self.vector = vector
    }
}

/// One stored window during a brute-force scan.
public struct TranscriptEmbeddingCandidate: Equatable, Sendable {
    public let episodeUuid: String
    public let podcastUuid: String?
    public let source: TranscriptSource
    public let windowIndex: Int
    public let startSegmentIndex: Int
    public let endSegmentIndex: Int
    public let startTime: Double
    public let endTime: Double?
    public let textPreview: String
    public let vector: Data
}

/// Optional narrowing of a candidate scan. `podcastUuid` + `publishedBefore` +
/// `excludeEpisodeUuid` together answer "earlier episodes of this podcast" —
/// the callback-detection shape — via the (podcastUuid, episodeUuid) index and
/// an SJEpisode join.
public struct TranscriptEmbeddingCandidateFilter: Sendable {
    public var source: TranscriptSource?
    public var podcastUuid: String?
    public var publishedBefore: Date?
    public var excludeEpisodeUuid: String?

    public init(source: TranscriptSource? = nil, podcastUuid: String? = nil, publishedBefore: Date? = nil, excludeEpisodeUuid: String? = nil) {
        self.source = source
        self.podcastUuid = podcastUuid
        self.publishedBefore = publishedBefore
        self.excludeEpisodeUuid = excludeEpisodeUuid
    }
}

@GRDBRecord(table: "TranscriptEmbeddingMeta")
public struct TranscriptEmbeddingMetaRecord: Equatable, Sendable {
    public var episodeUuid = ""
    public var source = ""
    public var podcastUuid: String?
    public var modelIdentifier = ""
    public var modelRevision: Int32 = 0
    public var dimension: Int32 = 0
    public var quantization = ""
    public var windowCount: Int32 = 0
    public var vectorBytes: Int64 = 0
    public var embeddedDate: Double = 0
}

/// The semantic-search sidecar: per-window embedding vectors keyed to the same
/// (episodeUuid, source) identity as the FTS corpus. Device-local, never syncs.
///
/// Lifecycle mirrors the FTS corpus exactly: `TranscriptSearchDataManager`
/// cascades deletions (re-index, explicit delete, eviction) into these tables
/// inside its own write transactions, and `replaceWindows` refuses to write for
/// a pair the corpus no longer contains — so an embed task finishing after its
/// FTS rows were evicted can't leave orphans. See
/// docs/adr/0004-windowed-embedding-sidecar.md.
public struct TranscriptEmbeddingDataManager: Sendable {
    static let embeddingTableName = "TranscriptEmbedding"
    static let metaTableName = "TranscriptEmbeddingMeta"

    private let dbQueue: GRDBQueue

    /// Mirrors the FTS corpus's availability: the sidecar is meaningless without
    /// it (migration 82 self-disabled on an FTS5-less SQLite build).
    public let isAvailable: Bool

    init(dbQueue: GRDBQueue, isAvailable: Bool) {
        self.dbQueue = dbQueue
        self.isAvailable = isAvailable
    }

    // MARK: - Writes

    /// Replaces the (episode, source) pair's windows and meta row in one write
    /// transaction. Refuses (returning false) when the corpus has no meta row
    /// for the pair — the eviction-race guard.
    @discardableResult
    public func replaceWindows(episodeUuid: String, podcastUuid: String?, source: TranscriptSource,
                               model: TranscriptEmbeddingModelInfo, windows: [TranscriptEmbeddingWindow],
                               embeddedDate: Date = Date()) -> Bool {
        guard isAvailable else { return false }

        var corpusRowExists = true
        let success = dbQueue.write { db in
            let corpusRow = try TranscriptSearchIndexMetaRecord
                .filter(TranscriptSearchIndexMetaRecord.Columns.episodeUuid == episodeUuid)
                .filter(TranscriptSearchIndexMetaRecord.Columns.source == source.rawValue)
                .fetchOne(db)
            guard corpusRow != nil else {
                corpusRowExists = false
                return
            }

            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - the GRDBRecord macro has no BLOB column support
            try db.execute(sql: "DELETE FROM \(Self.embeddingTableName) WHERE episodeUuid = ? AND source = ?",
                           arguments: [episodeUuid, source.rawValue])

            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - the GRDBRecord macro has no BLOB column support
            let insert = try db.cachedStatement(sql: """
            INSERT INTO \(Self.embeddingTableName)
                (episodeUuid, source, windowIndex, podcastUuid, startSegmentIndex, endSegmentIndex, startTime, endTime, textPreview, vector)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
            for window in windows {
                try insert.execute(arguments: [
                    episodeUuid, source.rawValue, window.windowIndex, podcastUuid,
                    window.startSegmentIndex, window.endSegmentIndex,
                    window.startTime, window.endTime, window.textPreview, window.vector
                ])
            }

            var meta = TranscriptEmbeddingMetaRecord()
            meta.episodeUuid = episodeUuid
            meta.source = source.rawValue
            meta.podcastUuid = podcastUuid
            meta.modelIdentifier = model.identifier
            meta.modelRevision = Int32(model.revision)
            meta.dimension = Int32(model.dimension)
            meta.quantization = model.quantization
            meta.windowCount = Int32(windows.count)
            meta.vectorBytes = windows.reduce(into: Int64(0)) { $0 += Int64($1.vector.count) }
            meta.embeddedDate = embeddedDate.timeIntervalSince1970
            try meta.save(db)
        }
        if !success { FileLog.shared.addMessage("TranscriptEmbeddingDataManager.replaceWindows failed") }
        return success && corpusRowExists
    }

    /// True when the pair already has windows produced by exactly `model`.
    public func isEmbedded(episodeUuid: String, source: TranscriptSource, model: TranscriptEmbeddingModelInfo) -> Bool {
        guard isAvailable else { return false }
        let meta = dbQueue.read { db in
            try TranscriptEmbeddingMetaRecord
                .filter(TranscriptEmbeddingMetaRecord.Columns.episodeUuid == episodeUuid)
                .filter(TranscriptEmbeddingMetaRecord.Columns.source == source.rawValue)
                .fetchOne(db)
        } ?? nil
        guard let meta else { return false }
        return meta.modelIdentifier == model.identifier
            && meta.modelRevision == Int32(model.revision)
            && meta.dimension == Int32(model.dimension)
            && meta.quantization == model.quantization
    }

    @discardableResult
    public func delete(episodeUuid: String, source: TranscriptSource) -> Bool {
        guard isAvailable else { return false }
        let success = dbQueue.write { db in
            try Self.deleteRows(db: db, episodeUuid: episodeUuid, source: source)
        }
        if !success { FileLog.shared.addMessage("TranscriptEmbeddingDataManager.delete failed") }
        return success
    }

    @discardableResult
    public func removeAll(source: TranscriptSource? = nil) -> Bool {
        guard isAvailable else { return false }
        let success = dbQueue.write { db in
            try Self.deleteRows(db: db, source: source)
        }
        if !success { FileLog.shared.addMessage("TranscriptEmbeddingDataManager.removeAll failed") }
        return success
    }

    /// In-transaction cascade used by `TranscriptSearchDataManager` so corpus and
    /// sidecar always change atomically.
    static func deleteRows(db: Database, episodeUuid: String? = nil, source: TranscriptSource? = nil) throws {
        var conditions: [String] = []
        var arguments: [(any DatabaseValueConvertible)?] = []
        if let episodeUuid {
            conditions.append("episodeUuid = ?")
            arguments.append(episodeUuid)
        }
        if let source {
            conditions.append("source = ?")
            arguments.append(source.rawValue)
        }
        let whereClause = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")

        // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - the GRDBRecord macro has no BLOB column support
        try db.execute(sql: "DELETE FROM \(embeddingTableName)\(whereClause)", arguments: StatementArguments(arguments))
        // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - shares the WHERE clause with the BLOB table's delete
        try db.execute(sql: "DELETE FROM \(metaTableName)\(whereClause)", arguments: StatementArguments(arguments))
    }

    // MARK: - Reads

    /// Streams every stored window produced by `model` (mismatched rows are
    /// invisible), in stable order, in batches — the brute-force scoring scan
    /// never holds the whole vector set in memory.
    public func candidates(model: TranscriptEmbeddingModelInfo,
                           filter: TranscriptEmbeddingCandidateFilter = TranscriptEmbeddingCandidateFilter(),
                           batchSize: Int = 4096,
                           handler: ([TranscriptEmbeddingCandidate]) -> Void) {
        guard isAvailable, batchSize > 0 else { return }

        var conditions = """
        m.modelIdentifier = ? AND m.modelRevision = ? AND m.dimension = ? AND m.quantization = ?
        """
        var arguments: [(any DatabaseValueConvertible)?] = [model.identifier, model.revision, model.dimension, model.quantization]

        if let source = filter.source {
            conditions += " AND e.source = ?"
            arguments.append(source.rawValue)
        }
        if let podcastUuid = filter.podcastUuid {
            conditions += " AND e.podcastUuid = ?"
            arguments.append(podcastUuid)
        }
        if let excludeEpisodeUuid = filter.excludeEpisodeUuid {
            conditions += " AND e.episodeUuid != ?"
            arguments.append(excludeEpisodeUuid)
        }
        if let publishedBefore = filter.publishedBefore {
            conditions += " AND EXISTS (SELECT 1 FROM \(DataManager.episodeTableName) ep WHERE ep.uuid = e.episodeUuid AND ep.publishedDate < ?)"
            arguments.append(publishedBefore.timeIntervalSince1970)
        }

        // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - keyset-paginated meta join has no query-interface equivalent
        let sql = """
        SELECT e.episodeUuid, e.podcastUuid, e.source, e.windowIndex, e.startSegmentIndex, e.endSegmentIndex,
               e.startTime, e.endTime, e.textPreview, e.vector
        FROM \(Self.embeddingTableName) e
        JOIN \(Self.metaTableName) m ON m.episodeUuid = e.episodeUuid AND m.source = e.source
        WHERE \(conditions) AND (e.episodeUuid, e.source, e.windowIndex) > (?, ?, ?)
        ORDER BY e.episodeUuid, e.source, e.windowIndex
        LIMIT ?
        """

        var cursor: (episodeUuid: String, source: String, windowIndex: Int) = ("", "", -1)
        while true {
            var pageArguments = arguments
            pageArguments.append(cursor.episodeUuid)
            pageArguments.append(cursor.source)
            pageArguments.append(cursor.windowIndex)
            pageArguments.append(batchSize)

            let rows = dbQueue.read { db in
                try Row.fetchAll(db, sql: sql, arguments: StatementArguments(pageArguments))
            } ?? []
            guard !rows.isEmpty else { return }

            let batch = rows.map { row in
                TranscriptEmbeddingCandidate(
                    episodeUuid: row["episodeUuid"] ?? "",
                    podcastUuid: row["podcastUuid"],
                    source: TranscriptSource(rawValue: row["source"] ?? "") ?? .provided,
                    windowIndex: row["windowIndex"] ?? 0,
                    startSegmentIndex: row["startSegmentIndex"] ?? 0,
                    endSegmentIndex: row["endSegmentIndex"] ?? 0,
                    startTime: row["startTime"] ?? 0,
                    endTime: row["endTime"],
                    textPreview: row["textPreview"] ?? "",
                    vector: row["vector"] ?? Data()
                )
            }
            handler(batch)

            if let last = batch.last {
                cursor = (last.episodeUuid, last.source.rawValue, last.windowIndex)
            }
            if batch.count < batchSize { return }
        }
    }

    /// FTS-indexed (episode, source) pairs that lack a current-`model` embedding —
    /// the backfill work list. Newest-indexed first: fresh episodes become
    /// semantically searchable before back-catalog ones.
    public func pendingPairs(model: TranscriptEmbeddingModelInfo, limit: Int = 50) -> [(episodeUuid: String, podcastUuid: String?, source: TranscriptSource)] {
        guard isAvailable else { return [] }

        // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - anti-join against the model-stamped meta has no query-interface equivalent
        let sql = """
        SELECT c.episodeUuid, c.podcastUuid, c.source
        FROM TranscriptSearchIndexMeta c
        LEFT JOIN \(Self.metaTableName) m
          ON m.episodeUuid = c.episodeUuid AND m.source = c.source
          AND m.modelIdentifier = ? AND m.modelRevision = ? AND m.dimension = ? AND m.quantization = ?
        WHERE m.episodeUuid IS NULL
        ORDER BY c.indexedDate DESC
        LIMIT ?
        """
        let rows = dbQueue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: [model.identifier, model.revision, model.dimension, model.quantization, limit])
        } ?? []

        return rows.map { row in
            (
                episodeUuid: row["episodeUuid"] ?? "",
                podcastUuid: row["podcastUuid"],
                source: TranscriptSource(rawValue: row["source"] ?? "") ?? .provided
            )
        }
    }

    /// Total stored vector bytes (storage accounting).
    public func totalVectorBytes() -> Int64 {
        guard isAvailable else { return 0 }
        return dbQueue.read { db in
            try TranscriptEmbeddingMetaRecord
                .select(sum(TranscriptEmbeddingMetaRecord.Columns.vectorBytes), as: Int64.self)
                .fetchOne(db) ?? 0
        } ?? 0
    }
}
