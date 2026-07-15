import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Drains the sidecar's pending work list — FTS-indexed pairs without a
/// current-model embedding — one episode at a time, newest-indexed first,
/// re-checking the transcription battery policy and thermal state between
/// episodes. Kicked shortly after foreground launch; a model-revision bump
/// naturally re-lists every pair, so backfill is also the lazy re-embed path.
nonisolated final class TranscriptEmbeddingBackfill: Sendable {
    static let shared = TranscriptEmbeddingBackfill()

    /// At most this many pairs per drain: launch backfill nibbles, it never gorges.
    static let maxPairsPerDrain = 20

    private let pipeline: TranscriptEmbeddingPipeline
    private let provider: any TextEmbeddingProviding
    private let isEnabled: @Sendable () -> Bool
    private let pendingPairs: @Sendable (TranscriptEmbeddingModelInfo, Int) -> [(episodeUuid: String, podcastUuid: String?, source: PocketCastsDataModel.TranscriptSource)]
    private let isDeferred: @Sendable () async -> Bool

    private convenience init() {
        self.init(pipeline: .shared, provider: ContextualEmbeddingProvider.shared)
    }

    init(pipeline: TranscriptEmbeddingPipeline,
         provider: any TextEmbeddingProviding,
         isEnabled: @escaping @Sendable () -> Bool = {
             FeatureFlag.semanticTranscriptSearch.enabled && DataManager.sharedManager.transcriptEmbeddings.isAvailable
         },
         pendingPairs: @escaping @Sendable (TranscriptEmbeddingModelInfo, Int) -> [(episodeUuid: String, podcastUuid: String?, source: PocketCastsDataModel.TranscriptSource)] = {
             DataManager.sharedManager.transcriptEmbeddings.pendingPairs(model: $0, limit: $1)
         },
         isDeferred: @escaping @Sendable () async -> Bool = {
             // Battery/thermal live on the main actor (UIDevice-backed).
             let deferred = await MainActor.run {
                 TranscriptionPowerState.isDeferred(policy: Settings.transcriptionBatteryPolicy(), state: .current())
             }
             let thermal = ProcessInfo.processInfo.thermalState
             return deferred || thermal == .serious || thermal == .critical
         }) {
        self.pipeline = pipeline
        self.provider = provider
        self.isEnabled = isEnabled
        self.pendingPairs = pendingPairs
        self.isDeferred = isDeferred
    }

    /// Fire-and-forget launch trigger; delays so it never competes with startup.
    func kickAfterLaunch(delay: TimeInterval = 30) {
        guard isEnabled(), !isRunningTests else { return }
        Task.detached(priority: .background) { [self] in
            try? await Task.sleep(for: .seconds(delay))
            await drain()
        }
    }

    /// Embeds up to `maxPairs` pending pairs, stopping early on cancellation or
    /// when power/thermal conditions defer background work.
    func drain(maxPairs: Int = TranscriptEmbeddingBackfill.maxPairsPerDrain) async {
        guard isEnabled() else { return }
        guard let model = await provider.modelInfo() else { return }

        var embedded = 0
        while embedded < maxPairs {
            if Task.isCancelled { break }
            if await isDeferred() { break }
            // Re-query each iteration: embedding a pair removes it from the list.
            guard let pair = pendingPairs(model, 1).first else { break }

            let stored = await pipeline.embed(episodeUuid: pair.episodeUuid, podcastUuid: pair.podcastUuid, source: pair.source)
            guard stored else {
                // A pair that can't embed (corpus row raced away, provider error)
                // would loop forever at the head of the list — stop this drain.
                break
            }
            embedded += 1
        }

        if embedded > 0 {
            FileLog.shared.addMessage("[Embedding] backfill embedded \(embedded) pair(s)")
            Analytics.track(.transcriptEmbeddingBackfillCompleted, properties: ["episodes": embedded])
        }
    }
}
