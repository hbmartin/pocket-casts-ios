import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Embeds an indexed transcript into the sidecar: reads the pair's corpus
/// segments, builds Embedding Windows, embeds them in small batches, and
/// stores quantized vectors. Mirrors `TranscriptSearchIndexer`'s shape:
/// fire-and-forget `embedIfNeeded` off the corpus write points, plus an
/// awaitable `embed` shared with the backfill. Never blocks indexing or
/// transcription completion.
nonisolated final class TranscriptEmbeddingPipeline: Sendable {
    static let shared = TranscriptEmbeddingPipeline()

    /// Windows per provider call: keeps peak memory small and cancellation responsive.
    static let batchSize = 12

    private let provider: any TextEmbeddingProviding
    private let isEnabled: @Sendable () -> Bool
    private let segments: @Sendable (String, PocketCastsDataModel.TranscriptSource) -> [TranscriptSearchSegment]
    private let isEmbedded: @Sendable (String, PocketCastsDataModel.TranscriptSource, TranscriptEmbeddingModelInfo) -> Bool
    private let replaceWindows: @Sendable (String, String?, PocketCastsDataModel.TranscriptSource, TranscriptEmbeddingModelInfo, [TranscriptEmbeddingWindow]) -> Bool
    private let languageHint: @Sendable (String) -> String?

    init(provider: any TextEmbeddingProviding = ContextualEmbeddingProvider.shared,
         isEnabled: @escaping @Sendable () -> Bool = {
             FeatureFlag.semanticTranscriptSearch.enabled && DataManager.sharedManager.transcriptEmbeddings.isAvailable
         },
         segments: @escaping @Sendable (String, PocketCastsDataModel.TranscriptSource) -> [TranscriptSearchSegment] = {
             DataManager.sharedManager.transcriptSearch.segments(episodeUuid: $0, source: $1)
         },
         isEmbedded: @escaping @Sendable (String, PocketCastsDataModel.TranscriptSource, TranscriptEmbeddingModelInfo) -> Bool = {
             DataManager.sharedManager.transcriptEmbeddings.isEmbedded(episodeUuid: $0, source: $1, model: $2)
         },
         replaceWindows: @escaping @Sendable (String, String?, PocketCastsDataModel.TranscriptSource, TranscriptEmbeddingModelInfo, [TranscriptEmbeddingWindow]) -> Bool = {
             DataManager.sharedManager.transcriptEmbeddings.replaceWindows(episodeUuid: $0, podcastUuid: $1, source: $2, model: $3, windows: $4)
         },
         languageHint: @escaping @Sendable (String) -> String? = {
             DataManager.sharedManager.transcriptions.find(episodeUuid: $0)?.language
         }) {
        self.provider = provider
        self.isEnabled = isEnabled
        self.segments = segments
        self.isEmbedded = isEmbedded
        self.replaceWindows = replaceWindows
        self.languageHint = languageHint
    }

    /// Fire-and-forget: kicks a background task and returns immediately. Called
    /// from the corpus write points on success.
    func embedIfNeeded(episodeUuid: String, podcastUuid: String?, source: PocketCastsDataModel.TranscriptSource) {
        guard isEnabled() else { return }
        // Background embedding of the live database is unwanted noise under XCTest.
        guard !isRunningTests else { return }

        Task.detached(priority: .utility) { [self] in
            _ = await embed(episodeUuid: episodeUuid, podcastUuid: podcastUuid, source: source)
        }
    }

    /// Awaitable single entry point shared with the backfill. Dedupes against
    /// the sidecar's model stamp; returns whether new windows were written.
    @discardableResult
    func embed(episodeUuid: String, podcastUuid: String?, source: PocketCastsDataModel.TranscriptSource) async -> Bool {
        guard isEnabled() else { return false }
        guard let model = await provider.modelInfo() else { return false }
        guard !isEmbedded(episodeUuid, source, model) else { return false }

        let pairSegments = segments(episodeUuid, source)
        guard !pairSegments.isEmpty else { return false }

        let windows = TranscriptWindowBuilder.windows(from: pairSegments)
        guard !windows.isEmpty else { return false }

        let hint = languageHint(episodeUuid)
        var stored: [TranscriptEmbeddingWindow] = []
        stored.reserveCapacity(windows.count)

        for batch in stride(from: 0, to: windows.count, by: Self.batchSize).map({ Array(windows[$0 ..< min($0 + Self.batchSize, windows.count)]) }) {
            if Task.isCancelled { return false }
            let vectors: [[Float]]
            do {
                vectors = try await provider.embed(texts: batch.map(\.text), languageHint: hint)
            } catch {
                FileLog.shared.addMessage("[Embedding] embed failed for \(episodeUuid): \(error)")
                return false
            }
            guard vectors.count == batch.count else { return false }

            for (window, vector) in zip(batch, vectors) {
                stored.append(TranscriptEmbeddingWindow(
                    windowIndex: window.windowIndex,
                    startSegmentIndex: window.startSegmentIndex,
                    endSegmentIndex: window.endSegmentIndex,
                    startTime: window.startTime,
                    endTime: window.endTime,
                    textPreview: TranscriptWindowBuilder.preview(of: window.text),
                    vector: EmbeddingVectorCodec.encode(vector)
                ))
            }
        }

        let written = replaceWindows(episodeUuid, podcastUuid, source, model, stored)
        if written {
            FileLog.shared.addMessage("[Embedding] stored \(stored.count) windows for \(episodeUuid) (\(source.rawValue))")
        }
        return written
    }
}
