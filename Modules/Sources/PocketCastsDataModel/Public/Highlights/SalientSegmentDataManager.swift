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

    /// The generation for an episode, if a current-version one exists.
    public func generation(episodeUuid: String) -> (meta: SalientSegmentMetaRecord, segments: [SalientSegmentRecord])? {
        let meta: SalientSegmentMetaRecord? = dbQueue.read { db in
            try SalientSegmentMetaRecord
                .filter(SalientSegmentMetaRecord.Columns.episodeUuid == episodeUuid)
                .fetchOne(db)
        } ?? nil
        guard let meta, meta.generatorVersion == Self.generatorVersion else { return nil }

        let segments = dbQueue.fetchAll(
            SalientSegmentRecord
                .filter(SalientSegmentRecord.Columns.episodeUuid == episodeUuid)
                .order(SalientSegmentRecord.Columns.rank.asc)
        )
        return (meta, segments)
    }

    /// Pending suggestions across episodes, newest generation first.
    public func pendingSuggestions(limit: Int = 50) -> [SalientSegmentRecord] {
        dbQueue.fetchAll(
            SalientSegmentRecord
                .filter(SalientSegmentRecord.Columns.suggestionStatus == SalientSuggestionStatus.pending.rawValue)
                .order(SalientSegmentRecord.Columns.episodeUuid.asc, SalientSegmentRecord.Columns.rank.asc)
                .limit(limit)
        )
    }

    /// Episodes with no current-version generation attempt, for the scanner's
    /// dedupe (a `noSegments` meta row counts as attempted).
    public func hasGeneration(episodeUuid: String) -> Bool {
        generation(episodeUuid: episodeUuid) != nil
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

    @discardableResult
    public func setStatus(
        _ status: SalientSuggestionStatus,
        episodeUuid: String,
        rank: Int32,
        bookmarkUuid: String? = nil
    ) -> Bool {
        dbQueue.write { db in
            try SalientSegmentRecord
                .filter(SalientSegmentRecord.Columns.episodeUuid == episodeUuid)
                .filter(SalientSegmentRecord.Columns.rank == rank)
                .updateAll(db,
                           SalientSegmentRecord.Columns.suggestionStatus.set(to: status.rawValue),
                           SalientSegmentRecord.Columns.bookmarkUuid.set(to: bookmarkUuid))
        }
    }
}
