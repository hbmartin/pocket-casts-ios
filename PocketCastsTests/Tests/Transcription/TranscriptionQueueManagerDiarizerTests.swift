import Foundation
import GRDB
import PocketCastsTranscription
import PocketCastsUtils
import Synchronization
import XCTest

@testable import PocketCastsDataModel
@testable import podcasts

/// Exercises the Phase 2 diarizing stage of the queue pipeline with mock
/// engines/diarizers: speaker turns flow into `<v>`-tagged cues, diarizer
/// failures degrade to monologue output (never fail the job), the max-speakers
/// setting is plumbed through, and cancellation mid-diarize still cancels.
final class TranscriptionQueueManagerDiarizerTests: XCTestCase {
    private var dataManager: DataManager!
    private var dbPool: DatabasePool!
    private var workDirectory: URL!
    private var audioURL: URL!

    override func setUp() async throws {
        try await super.setUp()

        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-diarizer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        var configuration = Configuration()
        configuration.busyMode = .timeout(10)
        dbPool = try DatabasePool(path: workDirectory.appendingPathComponent("test.sqlite3").path, configuration: configuration)
        dataManager = try DataManager(dbQueue: GRDBQueue(dbPool: dbPool))

        audioURL = workDirectory.appendingPathComponent("episode.mp3")
        try Data("not really audio, the engine is mocked".utf8).write(to: audioURL)
    }

    override func tearDown() async throws {
        try? dbPool.close()
        try? FileManager.default.removeItem(at: workDirectory)
        try await super.tearDown()
    }

    private static let twoSpeakerSegments = [
        ASRSegment(text: "Hello and welcome to the show.", start: 0, end: 4),
        ASRSegment(text: "Thanks for having me on.", start: 5, end: 9)
    ]

    private static let twoSpeakerTurns = [
        SpeakerTurn(speakerId: "SPEAKER_0", start: 0, end: 4.5),
        SpeakerTurn(speakerId: "SPEAKER_1", start: 4.5, end: 9)
    ]

    private func makeManager(engine: MockSpeechEngine,
                             diarizer: MockDiarizer?,
                             maxSpeakers: Int = 0) -> TranscriptionQueueManager {
        let audioURL = audioURL
        return TranscriptionQueueManager(
            dataManager: dataManager,
            engineFactory: MockEngineFactory(engine: engine, diarizer: diarizer),
            artifactStore: TranscriptionArtifactStore(directoryURL: workDirectory.appendingPathComponent("artifacts", isDirectory: true)),
            engineMode: { .appleBuiltIn },
            audioFileURL: { _ in audioURL },
            thermalState: { .nominal },
            maxSpeakers: { maxSpeakers }
        )
    }

    // MARK: - Tests

    func testDiarizerTurnsProduceSpeakerTaggedCues() async throws {
        let engine = MockSpeechEngine(segments: Self.twoSpeakerSegments)
        let diarizer = MockDiarizer(turns: Self.twoSpeakerTurns)
        let manager = makeManager(engine: engine, diarizer: diarizer)

        await manager.enqueue(episodeUuid: "episode-diarized", podcastUuid: "podcast-1")
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-diarized"))
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertEqual(record.speakerCount, 2)

        let vtt = try String(contentsOfFile: XCTUnwrap(record.filePath), encoding: .utf8)
        XCTAssertTrue(vtt.contains("<v Speaker 1>"), "Diarizer turns must surface as voice tags")
        XCTAssertTrue(vtt.contains("<v Speaker 2>"))
    }

    func testDiarizerPrepareFailureFallsBackToMonologue() async throws {
        let engine = MockSpeechEngine(segments: Self.twoSpeakerSegments)
        let diarizer = MockDiarizer(turns: Self.twoSpeakerTurns, prepareError: .modelDownloadFailed)
        let manager = makeManager(engine: engine, diarizer: diarizer)

        await manager.enqueue(episodeUuid: "episode-no-diarizer-model", podcastUuid: nil)
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-no-diarizer-model"))
        XCTAssertEqual(record.transcriptionStatus, .completed, "A diarizer failure must never fail the job")
        XCTAssertEqual(record.speakerCount, 0)

        let vtt = try String(contentsOfFile: XCTUnwrap(record.filePath), encoding: .utf8)
        XCTAssertFalse(vtt.contains("<v "), "Monologue fallback must not carry voice tags")
    }

    func testDiarizeFailureFallsBackToMonologue() async throws {
        let engine = MockSpeechEngine(segments: Self.twoSpeakerSegments)
        let diarizer = MockDiarizer(turns: Self.twoSpeakerTurns, diarizeError: .engineFailure)
        let manager = makeManager(engine: engine, diarizer: diarizer)

        await manager.enqueue(episodeUuid: "episode-diarize-failed", podcastUuid: nil)
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-diarize-failed"))
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertEqual(record.speakerCount, 0)
    }

    func testNilDiarizerSkipsStageAndCompletesAsMonologue() async throws {
        let engine = MockSpeechEngine(segments: Self.twoSpeakerSegments)
        let manager = makeManager(engine: engine, diarizer: nil)

        await manager.enqueue(episodeUuid: "episode-no-diarizer", podcastUuid: nil)
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-no-diarizer"))
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertEqual(record.speakerCount, 0)
    }

    func testMaxSpeakersSettingReachesDiarizer() async throws {
        let engine = MockSpeechEngine(segments: Self.twoSpeakerSegments)
        let diarizer = MockDiarizer(turns: Self.twoSpeakerTurns)
        let manager = makeManager(engine: engine, diarizer: diarizer, maxSpeakers: 3)

        await manager.enqueue(episodeUuid: "episode-capped", podcastUuid: nil)
        await manager.drainUntilIdle()

        XCTAssertEqual(diarizer.receivedMaxSpeakers, [3])
    }

    func testAutoMaxSpeakersReachesDiarizerAsNil() async throws {
        let engine = MockSpeechEngine(segments: Self.twoSpeakerSegments)
        let diarizer = MockDiarizer(turns: Self.twoSpeakerTurns)
        let manager = makeManager(engine: engine, diarizer: diarizer, maxSpeakers: 0)

        await manager.enqueue(episodeUuid: "episode-auto", podcastUuid: nil)
        await manager.drainUntilIdle()

        XCTAssertEqual(diarizer.receivedMaxSpeakers, [nil])
    }

    func testCancelDuringDiarizeCancelsJobInsteadOfCompletingMonologue() async throws {
        let engine = MockSpeechEngine(segments: Self.twoSpeakerSegments)
        let diarizer = MockDiarizer(turns: Self.twoSpeakerTurns, blockDuringDiarize: true)
        let manager = makeManager(engine: engine, diarizer: diarizer)

        await manager.enqueue(episodeUuid: "episode-cancel-diarize", podcastUuid: nil)
        try await waitUntil("job reaches the diarize stage") { diarizer.diarizeStarted }

        await manager.cancel(episodeUuid: "episode-cancel-diarize")
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-cancel-diarize"))
        XCTAssertEqual(record.transcriptionStatus, .cancelled,
                       "Cancellation inside the diarizer must cancel the job, not degrade it to a completed monologue")
    }

    // MARK: - Factory defaults

    func testFactoryDefaultsToNilDiarizerAndProductionFactoryToSpeakerKit() {
        XCTAssertNil(MockEngineFactory(engine: MockSpeechEngine(), diarizer: nil).makeDiarizer(),
                     "Factories that don't override makeDiarizer must default to nil (skip stage)")
        XCTAssertTrue(TranscriptionEngineFactory().makeDiarizer() is SpeakerKitDiarizer)
        XCTAssertTrue((try? TranscriptionEngineFactory().makeEngine(for: .localModel)) is WhisperKitEngine)
    }

    // MARK: - Speaker cap post-processing

    func testCappingKeepsMostHeardSpeakers() {
        let turns = [
            SpeakerTurn(speakerId: "SPEAKER_0", start: 0, end: 10),
            SpeakerTurn(speakerId: "SPEAKER_1", start: 10, end: 30),
            SpeakerTurn(speakerId: "SPEAKER_2", start: 30, end: 31),
            SpeakerTurn(speakerId: "SPEAKER_1", start: 31, end: 40)
        ]

        let capped = SpeakerKitDiarizer.capping(turns: turns, to: 2)

        XCTAssertEqual(Set(capped.map(\.speakerId)), ["SPEAKER_0", "SPEAKER_1"],
                       "The least-heard speaker's turns are dropped")
        XCTAssertEqual(capped.count, 3)
    }

    func testCappingIsANoOpForAutoAndUnderCapCounts() {
        let turns = [
            SpeakerTurn(speakerId: "SPEAKER_0", start: 0, end: 10),
            SpeakerTurn(speakerId: "SPEAKER_1", start: 10, end: 20)
        ]

        XCTAssertEqual(SpeakerKitDiarizer.capping(turns: turns, to: nil), turns)
        XCTAssertEqual(SpeakerKitDiarizer.capping(turns: turns, to: 0), turns)
        XCTAssertEqual(SpeakerKitDiarizer.capping(turns: turns, to: 2), turns)
        XCTAssertEqual(SpeakerKitDiarizer.capping(turns: turns, to: 5), turns)
    }

    // MARK: - Helpers

    private func waitUntil(_ description: String,
                           timeout: TimeInterval = 10,
                           condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting until \(description)")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

// MARK: - Mocks

nonisolated private struct MockEngineFactory: TranscriptionEngineProviding {
    let engine: MockSpeechEngine
    let diarizer: MockDiarizer?

    func makeEngine(for mode: TranscriptionEngineMode) throws -> any SpeechToTextEngine {
        engine
    }

    func makeDiarizer() -> (any SpeakerDiarizing)? {
        diarizer
    }
}

nonisolated private final class MockSpeechEngine: SpeechToTextEngine, Sendable {
    let id = "mock.engine"

    private let segments: [ASRSegment]

    init(segments: [ASRSegment] = []) {
        self.segments = segments
    }

    func prepare(locale: Locale?, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(1)
    }

    func transcribe(audioFile: URL, language: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> [ASRSegment] {
        progress(1)
        return segments
    }
}

nonisolated private final class MockDiarizer: SpeakerDiarizing, Sendable {
    private let turns: [SpeakerTurn]
    private let prepareError: TranscriptionError?
    private let diarizeError: TranscriptionError?
    private let blockDuringDiarize: Bool

    private let receivedMaxSpeakersLog = Mutex<[Int?]>([])
    private let diarizeStartedFlag = Mutex(false)

    init(turns: [SpeakerTurn] = [],
         prepareError: TranscriptionError? = nil,
         diarizeError: TranscriptionError? = nil,
         blockDuringDiarize: Bool = false) {
        self.turns = turns
        self.prepareError = prepareError
        self.diarizeError = diarizeError
        self.blockDuringDiarize = blockDuringDiarize
    }

    var receivedMaxSpeakers: [Int?] { receivedMaxSpeakersLog.withLock { $0 } }
    var diarizeStarted: Bool { diarizeStartedFlag.withLock { $0 } }

    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        if let prepareError {
            throw prepareError
        }
        progress(1)
    }

    func diarize(audioFile: URL, maxSpeakers: Int?, progress: @escaping @Sendable (Double) -> Void) async throws -> [SpeakerTurn] {
        receivedMaxSpeakersLog.withLock { $0.append(maxSpeakers) }
        diarizeStartedFlag.withLock { $0 = true }
        if blockDuringDiarize {
            // Spin until the queue cancels the job (Task.sleep throws on cancel).
            while true {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        if let diarizeError {
            throw diarizeError
        }
        progress(1)
        return turns
    }
}
