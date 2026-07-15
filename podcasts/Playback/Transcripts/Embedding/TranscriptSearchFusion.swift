import Foundation
import PocketCastsDataModel

/// Pure fusion of exact (FTS) and semantic (vector) transcript hits into the
/// one Transcripts section, by reciprocal-rank fusion. A semantic hit whose
/// window covers an FTS hit's segment collapses into it — the FTS hit keeps
/// its real highlighted snippet and the two rank contributions sum, so exact
/// matches naturally lead.
nonisolated enum TranscriptSearchFusion {

    static let rrfK: Double = 60

    /// The mild "I heard this recently" boost: at most +25%, decaying with a
    /// 30-day half-life-ish curve. Monotonic in score, so it reorders gently.
    static let recencyBoostWeight = 0.25
    static let recencyDecayDays = 30.0

    enum MatchType: String, Sendable {
        case exact
        case semantic
        case both
    }

    struct FusedHit: Hashable, Sendable {
        let episodeUuid: String
        let podcastUuid: String?
        let segmentIndex: Int
        let startTime: Double
        let endTime: Double?
        let speaker: String?
        let source: PocketCastsDataModel.TranscriptSource
        /// FTS snippet with highlight markers, or the window's plain preview.
        let snippet: String
        var matchType: MatchType
        var score: Double
    }

    static func fused(ftsHits: [TranscriptSearchHit], semanticHits: [SemanticTranscriptHit], k: Double = rrfK) -> [FusedHit] {
        var hits: [FusedHit] = ftsHits.enumerated().map { rank, hit in
            FusedHit(
                episodeUuid: hit.episodeUuid,
                podcastUuid: hit.podcastUuid,
                segmentIndex: hit.segmentIndex,
                startTime: hit.startTime,
                endTime: hit.endTime,
                speaker: hit.speaker,
                source: hit.source,
                snippet: hit.snippet,
                matchType: .exact,
                score: 1 / (k + Double(rank) + 1)
            )
        }

        for (rank, semantic) in semanticHits.enumerated() {
            let contribution = 1 / (k + Double(rank) + 1)
            if let overlapping = hits.firstIndex(where: { hit in
                hit.episodeUuid == semantic.episodeUuid
                    && hit.source == semantic.source
                    && (semantic.startSegmentIndex ... semantic.endSegmentIndex).contains(hit.segmentIndex)
            }) {
                hits[overlapping].score += contribution
                hits[overlapping].matchType = .both
            } else {
                hits.append(FusedHit(
                    episodeUuid: semantic.episodeUuid,
                    podcastUuid: semantic.podcastUuid,
                    segmentIndex: semantic.startSegmentIndex,
                    startTime: semantic.startTime,
                    endTime: semantic.endTime,
                    speaker: nil,
                    source: semantic.source,
                    snippet: semantic.textPreview,
                    matchType: .semantic,
                    score: contribution
                ))
            }
        }

        return hits.sorted { $0.score > $1.score }
    }

    /// Applies the recency boost and re-sorts. `ageDays` maps an episode uuid to
    /// days since it was last played or published (whichever is more recent);
    /// nil means no boost.
    static func recencyBoosted(_ hits: [FusedHit], ageDays: (String) -> Double?) -> [FusedHit] {
        hits.map { hit in
            var boosted = hit
            if let age = ageDays(hit.episodeUuid), age >= 0 {
                boosted.score *= 1 + recencyBoostWeight * exp(-age / recencyDecayDays)
            }
            return boosted
        }
        .sorted { $0.score > $1.score }
    }
}
