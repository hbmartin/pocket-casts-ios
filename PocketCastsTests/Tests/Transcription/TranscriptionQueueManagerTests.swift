import Foundation
import GRDB
import PocketCastsTranscription
import PocketCastsUtils
import Synchronization
import XCTest

@testable import PocketCastsDataModel
@testable import podcasts

/// Exercises the queue pipeline end-to-end against a mock speech engine and an
/// isolated on-disk database: enqueue → drain → artifact + FTS segments + record.
final class TranscriptionQueueManagerTests: XCTestCase {
    private var dataManager: DataManager!
    private var dbPool: DatabasePool!
    private var workDirectory: URL!
    private var audioURL: URL!

    override func setUp() async throws {
        try await super.setUp()

        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-queue-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        // A private pool (rather than DataManager.newTestDataManager()) so this
        // suite can't close the shared pool other suites hold on to.
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

    private func makeManager(engine: MockSpeechEngine,
                             thermalState: ProcessInfo.ThermalState = .nominal) -> TranscriptionQueueManager {
        let audioURL = audioURL
        return TranscriptionQueueManager(
            dataManager: dataManager,
            engineFactory: MockEngineFactory(engine: engine),
            artifactStore: TranscriptionArtifactStore(directoryURL: workDirectory.appendingPathComponent("artifacts", isDirectory: true)),
            engineMode: { .appleBuiltIn },
            audioFileURL: { _ in audioURL },
            thermalState: { thermalState }
        )
    }

    // MARK: - Tests

    func testHappyPathWritesArtifactSegmentsAndRecord() async throws {
        let engine = MockSpeechEngine(segments: [
            ASRSegment(text: "Hello and welcome to the show.", start: 0, end: 4),
            ASRSegment(text: "Today we talk about ducks.", start: 5, end: 9)
        ])
        let manager = makeManager(engine: engine)

        let completed = expectation(description: "completion notification posted")
        let token = NotificationCenter.default.addObserver(for: EpisodeTranscriptionCompleted.self) { message in
            if message.episodeUuid == "episode-1", message.succeeded {
                completed.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await manager.enqueue(episodeUuid: "episode-1", podcastUuid: "podcast-1")
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-1"))
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertNil(record.errorMessage)
        XCTAssertEqual(record.podcastUuid, "podcast-1")
        XCTAssertEqual(record.engineMode, TranscriptionEngineMode.appleBuiltIn.rawValue)
        XCTAssertEqual(record.durationSecs, 9, accuracy: 0.001)

        let filePath = try XCTUnwrap(record.filePath)
        let vtt = try String(contentsOfFile: filePath, encoding: .utf8)
        XCTAssertTrue(vtt.hasPrefix("WEBVTT"))
        XCTAssertTrue(vtt.contains("Hello and welcome to the show."))

        let hits = dataManager.transcriptSearch.search(term: "ducks", limit: 10, source: .generated)
        XCTAssertEqual(hits.first?.episodeUuid, "episode-1")
        XCTAssertEqual(hits.first?.podcastUuid, "podcast-1")

        let state = await manager.state(for: "episode-1")
        XCTAssertEqual(state, .completed)

        await fulfillment(of: [completed], timeout: 10)
    }

    func testFailurePathSetsFailedStatusAndErrorMessage() async throws {
        let engine = MockSpeechEngine(transcribeError: .audioUnreadable)
        let manager = makeManager(engine: engine)

        let completed = expectation(description: "failure notification posted")
        let token = NotificationCenter.default.addObserver(for: EpisodeTranscriptionCompleted.self) { message in
            if message.episodeUuid == "episode-fail", !message.succeeded {
                completed.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        await manager.enqueue(episodeUuid: "episode-fail", podcastUuid: nil)
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-fail"))
        XCTAssertEqual(record.transcriptionStatus, .failed)
        XCTAssertEqual(record.errorMessage, "audioUnreadable")

        let state = await manager.state(for: "episode-fail")
        XCTAssertEqual(state, .failed(.audioUnreadable))

        await fulfillment(of: [completed], timeout: 10)
    }

    func testCancelMidTranscribeMarksJobCancelled() async throws {
        let engine = MockSpeechEngine(segments: [ASRSegment(text: "never delivered", start: 0, end: 1)],
                                      blockDuringTranscribe: true)
        let manager = makeManager(engine: engine)

        await manager.enqueue(episodeUuid: "episode-cancel", podcastUuid: nil)
        try await waitUntil("transcription reaches the transcribe stage") { engine.transcribeStarted }

        await manager.cancel(episodeUuid: "episode-cancel")
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-cancel"))
        XCTAssertEqual(record.transcriptionStatus, .cancelled)

        let state = await manager.state(for: "episode-cancel")
        XCTAssertEqual(state, .cancelled)
    }

    func testRestorePendingJobsResetsCrashedProcessingToQueued() async throws {
        var crashed = EpisodeTranscriptionRecord()
        crashed.episodeUuid = "episode-crashed"
        crashed.transcriptionStatus = .processing
        crashed.createdAt = Date().timeIntervalSince1970
        dataManager.transcriptions.upsert(crashed)

        // A serious thermal state keeps the drain from immediately re-running the
        // restored job, so the processing → queued reset is observable.
        let engine = MockSpeechEngine()
        let manager = makeManager(engine: engine, thermalState: .serious)

        await manager.restorePendingJobs()
        await manager.drainUntilIdle()

        let restored = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-crashed"))
        XCTAssertEqual(restored.transcriptionStatus, .queued)

        let state = await manager.state(for: "episode-crashed")
        XCTAssertEqual(state, .queued)
        let stillQueued = await manager.isEpisodeQueued("episode-crashed")
        XCTAssertTrue(stillQueued)
        XCTAssertFalse(engine.prepareCalled)
    }

    func testThermalThrottleLeavesJobQueuedWithoutRunningEngine() async throws {
        let engine = MockSpeechEngine(segments: [ASRSegment(text: "hi", start: 0, end: 1)])
        let manager = makeManager(engine: engine, thermalState: .serious)

        await manager.enqueue(episodeUuid: "episode-hot", podcastUuid: nil)
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-hot"))
        XCTAssertEqual(record.transcriptionStatus, .queued)
        XCTAssertFalse(engine.prepareCalled)

        let stillQueued = await manager.isEpisodeQueued("episode-hot")
        XCTAssertTrue(stillQueued)
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

    func makeEngine(for mode: TranscriptionEngineMode) throws -> any SpeechToTextEngine {
        engine
    }
}

nonisolated private final class MockSpeechEngine: SpeechToTextEngine, Sendable {
    let id = "mock.engine"

    private let segments: [ASRSegment]
    private let prepareError: TranscriptionError?
    private let transcribeError: TranscriptionError?
    private let blockDuringTranscribe: Bool

    private let prepareCalledFlag = Mutex(false)
    private let transcribeStartedFlag = Mutex(false)

    init(segments: [ASRSegment] = [],
         prepareError: TranscriptionError? = nil,
         transcribeError: TranscriptionError? = nil,
         blockDuringTranscribe: Bool = false) {
        self.segments = segments
        self.prepareError = prepareError
        self.transcribeError = transcribeError
        self.blockDuringTranscribe = blockDuringTranscribe
    }

    var prepareCalled: Bool { prepareCalledFlag.withLock { $0 } }
    var transcribeStarted: Bool { transcribeStartedFlag.withLock { $0 } }

    func prepare(locale: Locale?, progress: @escaping @Sendable (Double) -> Void) async throws {
        prepareCalledFlag.withLock { $0 = true }
        if let prepareError {
            throw prepareError
        }
        progress(1)
    }

    func transcribe(audioFile: URL, language: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> [ASRSegment] {
        transcribeStartedFlag.withLock { $0 = true }
        if blockDuringTranscribe {
            // Spin until the queue cancels the job (Task.sleep throws on cancel).
            while true {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        if let transcribeError {
            throw transcribeError
        }
        progress(1)
        return segments
    }
}
