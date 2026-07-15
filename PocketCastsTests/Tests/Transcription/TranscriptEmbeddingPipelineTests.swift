import Foundation
import PocketCastsDataModel
import XCTest

@testable import podcasts

nonisolated private final class FakeEmbeddingProvider: TextEmbeddingProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var available = true
    private var failNext = false
    private var embedCallTexts: [[String]] = []

    var embedCalls: [[String]] { lock.withLock { embedCallTexts } }
    func setAvailable(_ value: Bool) { lock.withLock { available = value } }
    func setFailNext() { lock.withLock { failNext = true } }

    func modelInfo() async -> TranscriptEmbeddingModelInfo? {
        guard lock.withLock({ available }) else { return nil }
        return TranscriptEmbeddingModelInfo(identifier: "fake.model", revision: 1, dimension: 2, quantization: EmbeddingVectorCodec.quantization)
    }

    func embed(texts: [String], languageHint: String?) async throws -> [[Float]] {
        let shouldFail: Bool = lock.withLock {
            if failNext {
                failNext = false
                return true
            }
            embedCallTexts.append(texts)
            return false
        }
        if shouldFail { throw TextEmbeddingError.embeddingFailed }
        return texts.map { _ in [1, 0] }
    }
}

/// Shared mutable capture for the pipeline's injected sinks.
nonisolated private final class PipelineCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedWindows: [TranscriptEmbeddingWindow] = []
    private var storedModel: TranscriptEmbeddingModelInfo?
    var alreadyEmbedded = false
    var segments: [TranscriptSearchSegment] = []

    var windows: [TranscriptEmbeddingWindow] { lock.withLock { storedWindows } }
    var model: TranscriptEmbeddingModelInfo? { lock.withLock { storedModel } }

    func store(model: TranscriptEmbeddingModelInfo, windows: [TranscriptEmbeddingWindow]) {
        lock.withLock {
            storedModel = model
            storedWindows = windows
        }
    }
}

final class TranscriptEmbeddingPipelineTests: XCTestCase {

    private func makeSegments(count: Int, chars: Int = 300) -> [TranscriptSearchSegment] {
        (0 ..< count).map {
            TranscriptSearchSegment(index: $0, text: String(repeating: "w", count: chars), startTime: Double($0) * 10)
        }
    }

    private func makePipeline(provider: FakeEmbeddingProvider, capture: PipelineCapture, enabled: Bool = true) -> TranscriptEmbeddingPipeline {
        TranscriptEmbeddingPipeline(
            provider: provider,
            isEnabled: { enabled },
            segments: { _, _ in capture.segments },
            isEmbedded: { _, _, _ in capture.alreadyEmbedded },
            replaceWindows: { _, _, _, model, windows in
                capture.store(model: model, windows: windows)
                return true
            },
            languageHint: { _ in "en-US" }
        )
    }

    func testEmbedsWindowsAndStoresEncodedVectors() async {
        let provider = FakeEmbeddingProvider()
        let capture = PipelineCapture()
        capture.segments = makeSegments(count: 8)
        let pipeline = makePipeline(provider: provider, capture: capture)

        let stored = await pipeline.embed(episodeUuid: "ep-1", podcastUuid: "pod-1", source: .generated)

        XCTAssertTrue(stored)
        XCTAssertFalse(capture.windows.isEmpty)
        XCTAssertEqual(capture.model?.identifier, "fake.model")
        for window in capture.windows {
            XCTAssertEqual(window.vector.count, 2 * MemoryLayout<Float16>.size)
            XCTAssertFalse(window.textPreview.isEmpty)
        }
        // Window ordinals are dense and orderly.
        XCTAssertEqual(capture.windows.map(\.windowIndex), Array(0 ..< capture.windows.count))
    }

    func testSkipsWhenAlreadyEmbeddedForCurrentModel() async {
        let provider = FakeEmbeddingProvider()
        let capture = PipelineCapture()
        capture.segments = makeSegments(count: 4)
        capture.alreadyEmbedded = true
        let pipeline = makePipeline(provider: provider, capture: capture)

        let stored = await pipeline.embed(episodeUuid: "ep-1", podcastUuid: nil, source: .generated)

        XCTAssertFalse(stored)
        XCTAssertTrue(provider.embedCalls.isEmpty, "no provider work for an already-embedded pair")
    }

    func testDisabledOrUnavailableProviderShortCircuits() async {
        let provider = FakeEmbeddingProvider()
        let capture = PipelineCapture()
        capture.segments = makeSegments(count: 4)

        let disabled = makePipeline(provider: provider, capture: capture, enabled: false)
        let storedDisabled = await disabled.embed(episodeUuid: "ep-1", podcastUuid: nil, source: .generated)
        XCTAssertFalse(storedDisabled)

        provider.setAvailable(false)
        let unavailable = makePipeline(provider: provider, capture: capture)
        let storedUnavailable = await unavailable.embed(episodeUuid: "ep-1", podcastUuid: nil, source: .generated)
        XCTAssertFalse(storedUnavailable)
        XCTAssertTrue(capture.windows.isEmpty)
    }

    func testProviderFailureStoresNothing() async {
        let provider = FakeEmbeddingProvider()
        let capture = PipelineCapture()
        capture.segments = makeSegments(count: 4)
        provider.setFailNext()
        let pipeline = makePipeline(provider: provider, capture: capture)

        let stored = await pipeline.embed(episodeUuid: "ep-1", podcastUuid: nil, source: .generated)

        XCTAssertFalse(stored)
        XCTAssertTrue(capture.windows.isEmpty, "partial batches never land")
    }

    func testEmptyCorpusStoresNothing() async {
        let provider = FakeEmbeddingProvider()
        let capture = PipelineCapture()
        let pipeline = makePipeline(provider: provider, capture: capture)

        let stored = await pipeline.embed(episodeUuid: "ep-1", podcastUuid: nil, source: .provided)

        XCTAssertFalse(stored)
        XCTAssertTrue(provider.embedCalls.isEmpty)
    }

    func testLargeTranscriptEmbedsInBatches() async {
        let provider = FakeEmbeddingProvider()
        let capture = PipelineCapture()
        // Enough segments for well over batchSize windows.
        capture.segments = makeSegments(count: 60, chars: 900)
        let pipeline = makePipeline(provider: provider, capture: capture)

        let stored = await pipeline.embed(episodeUuid: "ep-1", podcastUuid: nil, source: .generated)

        XCTAssertTrue(stored)
        XCTAssertGreaterThan(provider.embedCalls.count, 1, "provider is called per batch")
        for call in provider.embedCalls {
            XCTAssertLessThanOrEqual(call.count, TranscriptEmbeddingPipeline.batchSize)
        }
        XCTAssertEqual(provider.embedCalls.reduce(0) { $0 + $1.count }, capture.windows.count)
    }
}

/// Backfill drain behavior against the same fakes.
final class TranscriptEmbeddingBackfillTests: XCTestCase {

    func testDrainEmbedsPendingPairsAndStopsWhenListEmpties() async {
        let provider = FakeEmbeddingProvider()
        let capture = PipelineCapture()
        capture.segments = [TranscriptSearchSegment(index: 0, text: String(repeating: "w", count: 400), startTime: 0)]

        let remaining = SharedCounter(2)
        let pipeline = TranscriptEmbeddingPipeline(
            provider: provider,
            isEnabled: { true },
            segments: { _, _ in capture.segments },
            isEmbedded: { _, _, _ in false },
            replaceWindows: { _, _, _, _, _ in
                remaining.decrement()
                return true
            },
            languageHint: { _ in nil }
        )
        let backfill = TranscriptEmbeddingBackfill(
            pipeline: pipeline,
            provider: provider,
            isEnabled: { true },
            pendingPairs: { _, _ in
                remaining.value > 0 ? [(episodeUuid: "ep-\(remaining.value)", podcastUuid: nil, source: .generated)] : []
            },
            isDeferred: { false }
        )

        await backfill.drain(maxPairs: 10)

        XCTAssertEqual(remaining.value, 0, "drains until the pending list is empty")
    }

    func testDrainRespectsDeferralAndPairCap() async {
        let provider = FakeEmbeddingProvider()
        let capture = PipelineCapture()
        capture.segments = [TranscriptSearchSegment(index: 0, text: String(repeating: "w", count: 400), startTime: 0)]

        let embedded = SharedCounter(0)
        let pipeline = TranscriptEmbeddingPipeline(
            provider: provider,
            isEnabled: { true },
            segments: { _, _ in capture.segments },
            isEmbedded: { _, _, _ in false },
            replaceWindows: { _, _, _, _, _ in
                embedded.increment()
                return true
            },
            languageHint: { _ in nil }
        )

        let deferred = TranscriptEmbeddingBackfill(
            pipeline: pipeline,
            provider: provider,
            isEnabled: { true },
            pendingPairs: { _, _ in [(episodeUuid: "ep-x", podcastUuid: nil, source: .generated)] },
            isDeferred: { true }
        )
        await deferred.drain(maxPairs: 10)
        XCTAssertEqual(embedded.value, 0, "deferral stops the drain before any work")

        let capped = TranscriptEmbeddingBackfill(
            pipeline: pipeline,
            provider: provider,
            isEnabled: { true },
            pendingPairs: { _, _ in [(episodeUuid: "ep-\(embedded.value)", podcastUuid: nil, source: .generated)] },
            isDeferred: { false }
        )
        await capped.drain(maxPairs: 3)
        XCTAssertEqual(embedded.value, 3, "the per-drain cap bounds the work")
    }
}

nonisolated private final class SharedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int

    init(_ count: Int) { self.count = count }
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
    func decrement() { lock.withLock { count -= 1 } }
}
