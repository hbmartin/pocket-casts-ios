import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// A vector-similarity match: one Embedding Window whose cosine against the
/// query cleared the floor. Seek lands on the window's first segment.
nonisolated struct SemanticTranscriptHit: Hashable, Sendable {
    let episodeUuid: String
    let podcastUuid: String?
    let source: PocketCastsDataModel.TranscriptSource
    let startSegmentIndex: Int
    let endSegmentIndex: Int
    let startTime: Double
    let endTime: Double?
    let textPreview: String
    let score: Float
}

/// Brute-force cosine search over the embedding sidecar: embeds the query once,
/// streams stored windows in batches, and keeps the top matches. At realistic
/// corpus sizes the SQLite read dominates; the arithmetic is microseconds.
nonisolated struct SemanticTranscriptSearch: Sendable {
    static let defaultLimit = 30
    /// Below this cosine, a "match" is noise — better an FTS-only section than
    /// confidently wrong semantic hits.
    static let defaultMinimumScore: Float = 0.55

    private let provider: any TextEmbeddingProviding
    private let isEnabled: @Sendable () -> Bool
    private let scan: @Sendable (TranscriptEmbeddingModelInfo, TranscriptEmbeddingCandidateFilter, Int, ([TranscriptEmbeddingCandidate]) -> Void) -> Void

    init(provider: any TextEmbeddingProviding = ContextualEmbeddingProvider.shared,
         isEnabled: @escaping @Sendable () -> Bool = {
             FeatureFlag.semanticTranscriptSearch.enabled && DataManager.sharedManager.transcriptEmbeddings.isAvailable
         },
         scan: @escaping @Sendable (TranscriptEmbeddingModelInfo, TranscriptEmbeddingCandidateFilter, Int, ([TranscriptEmbeddingCandidate]) -> Void) -> Void = { model, filter, batchSize, handler in
             DataManager.sharedManager.transcriptEmbeddings.candidates(model: model, filter: filter, batchSize: batchSize, handler: handler)
         }) {
        self.provider = provider
        self.isEnabled = isEnabled
        self.scan = scan
    }

    func search(term: String,
                filter: TranscriptEmbeddingCandidateFilter = TranscriptEmbeddingCandidateFilter(),
                limit: Int = SemanticTranscriptSearch.defaultLimit,
                minimumScore: Float = SemanticTranscriptSearch.defaultMinimumScore) async -> [SemanticTranscriptHit] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled(), !trimmed.isEmpty, limit > 0 else { return [] }
        guard let model = await provider.modelInfo(),
              let queryVector = try? await provider.embed(texts: [trimmed], languageHint: nil).first else {
            return []
        }

        var top: [SemanticTranscriptHit] = []
        scan(model, filter, 4096) { batch in
            for candidate in batch {
                guard let score = EmbeddingVectorCodec.dotProduct(candidate.vector, query: queryVector),
                      score >= minimumScore else { continue }
                top.append(SemanticTranscriptHit(
                    episodeUuid: candidate.episodeUuid,
                    podcastUuid: candidate.podcastUuid,
                    source: candidate.source,
                    startSegmentIndex: candidate.startSegmentIndex,
                    endSegmentIndex: candidate.endSegmentIndex,
                    startTime: candidate.startTime,
                    endTime: candidate.endTime,
                    textPreview: candidate.textPreview,
                    score: score
                ))
            }
            // Keep the working set bounded while the scan streams.
            if top.count > limit * 4 {
                top.sort { $0.score > $1.score }
                top.removeLast(top.count - limit)
            }
        }

        top.sort { $0.score > $1.score }
        return Array(top.prefix(limit))
    }
}
