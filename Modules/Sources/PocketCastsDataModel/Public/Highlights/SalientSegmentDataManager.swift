import Foundation
import GRDB
import PocketCastsUtils

/// Data access for salient segments (migration 88, ADR-0018). The whole
/// per-episode set replaces in one transaction; status transitions are the
/// only row-level mutations.
public struct SalientSegmentDataManager: Sendable {
    /// Bump when the prompt/validator changes enough that cached segments
    /// should regenerate lazily.
    public static let generatorVersion: Int32 = 1

    private let dbQueue: GRDBQueue

    init(dbQueue: GRDBQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Reads

    /// The generation for an episode, if a current-version one exists. Meta
    /// and segments come from one read transaction so a concurrent
    /// `replaceGeneration` can't produce a torn pair.
    public func generation(episodeUuid: String) -> (meta: SalientSegmentMetaRecord, segments: [SalientSegmentRecord])? {
        let pair: (SalientSegmentMetaRecord, [SalientSegmentRecord])? = dbQueue.read { db in
            guard let meta = try SalientSegmentMetaRecord
                .filter(SalientSegmentMetaRecord.Columns.episodeUuid == episodeUuid)
                .fetchOne(db),
                meta.generatorVersion == Self.generatorVersion else { return nil }

            let segments = try SalientSegmentRecord
                .filter(SalientSegmentRecord.Columns.episodeUuid == episodeUuid)
                .order(SalientSegmentRecord.Columns.rank.asc)
                .fetchAll(db)
            return (meta, segments)
        } ?? nil
        return pair
    }

    /// Pending suggestions across episodes, newest generation first (ties by
    /// rank so one episode's suggestions stay in quality order).
    public func pendingSuggestions(limit: Int = 50) -> [SalientSegmentRecord] {
        dbQueue.read { db in
            // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - ordering by a joined meta column
            try SalientSegmentRecord.fetchAll(db, sql: """
                SELECT s.* FROM SalientSegment s
                JOIN SalientSegmentMeta m ON m.episodeUuid = s.episodeUuid
                WHERE s.suggestionStatus = ?
                ORDER BY m.generatedAt DESC, s.rank ASC
                LIMIT ?
                """, arguments: [SalientSuggestionStatus.pending.rawValue, limit])
        } ?? []
    }

    /// Episodes with no current-version generation attempt, for the scanner's
    /// dedupe (a `noSegments` meta row counts as attempted). Meta-only: the
    /// scanner calls this per episode, so it must not materialize segments.
    public func hasGeneration(episodeUuid: String) -> Bool {
        let count: Int = dbQueue.read { db in
            try SalientSegmentMetaRecord
                .filter(SalientSegmentMetaRecord.Columns.episodeUuid == episodeUuid)
                .filter(SalientSegmentMetaRecord.Columns.generatorVersion == Self.generatorVersion)
                .fetchCount(db)
        } ?? 0
        return count > 0
    }

    // MARK: - Writes

    /// Replaces an episode's whole generation in one transaction.
    @discardableResult
    public func replaceGeneration(
        episodeUuid: String,
        podcastUuid: String?,
        transcriptSource: String,
        generatedAt: Date,
        segments: [SalientSegmentRecord],
        markPendingTop: Int = 0
    ) -> Bool {
        var meta = SalientSegmentMetaRecord()
        meta.episodeUuid = episodeUuid
        meta.podcastUuid = podcastUuid
        meta.outcome = (segments.isEmpty ? SalientSegmentOutcome.noSegments : .segments).rawValue
        meta.transcriptSource = transcriptSource
        meta.generatorVersion = Self.generatorVersion
        meta.generatedAt = generatedAt.timeIntervalSince1970
        meta.segmentCount = Int32(segments.count)
        let metaToSave = meta

        return dbQueue.write { db in
            _ = try SalientSegmentRecord
                .filter(SalientSegmentRecord.Columns.episodeUuid == episodeUuid)
                .deleteAll(db)
            for var segment in segments {
                segment.episodeUuid = episodeUuid
                if segment.rank < Int32(markPendingTop), segment.status == .candidate {
                    segment.status = .pending
                }
                try segment.insert(db)
            }
            try metaToSave.save(db)
        }
    }

    /// Marks the top `count` candidate rows pending (the on-demand
    /// "Suggest highlights" path over an existing generation).
    @discardableResult
    public func markTopCandidatesPending(episodeUuid: String, count: Int) -> Bool {
        dbQueue.write { db in
            let candidates = try SalientSegmentRecord
                .filter(SalientSegmentRecord.Columns.episodeUuid == episodeUuid)
                .filter(SalientSegmentRecord.Columns.suggestionStatus == SalientSuggestionStatus.candidate.rawValue)
                .order(SalientSegmentRecord.Columns.rank.asc)
                .limit(count)
                .fetchAll(db)
            for var candidate in candidates {
                candidate.status = .pending
                try candidate.update(db)
            }
        }
    }

    /// nil `bookmarkUuid` leaves any stored link untouched — a later status
    /// change must not silently sever an accepted segment's created-bookmark
    /// audit trail.
    @discardableResult
    public func setStatus(
        _ status: SalientSuggestionStatus,
        episodeUuid: String,
        rank: Int32,
        bookmarkUuid: String? = nil
    ) -> Bool {
        dbQueue.write { db in
            var assignments = [SalientSegmentRecord.Columns.suggestionStatus.set(to: status.rawValue)]
            if let bookmarkUuid {
                assignments.append(SalientSegmentRecord.Columns.bookmarkUuid.set(to: bookmarkUuid))
            }
            try SalientSegmentRecord
                .filter(SalientSegmentRecord.Columns.episodeUuid == episodeUuid)
                .filter(SalientSegmentRecord.Columns.rank == rank)
                .updateAll(db, assignments)
        }
    }
}
