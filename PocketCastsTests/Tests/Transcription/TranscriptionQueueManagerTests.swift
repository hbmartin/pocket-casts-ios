import Foundation
import GRDB
import PocketCastsServer
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
                             thermalState: ProcessInfo.ThermalState = .nominal,
                             engineMode: TranscriptionEngineMode = .appleBuiltIn,
                             powerState: @escaping @Sendable () -> TranscriptionPowerState = { TranscriptionPowerState(batteryLevel: 1, isCharging: true, isLowPowerModeEnabled: false) },
                             batteryPolicy: TranscriptionBatteryPolicy = .always,
                             podcastDisablesRemote: Bool = false,
                             remoteConsent: Bool = true,
                             contributionEnqueue: @escaping @Sendable (String, EpisodeTranscriptionRecord) -> Void = { _, _ in }) -> TranscriptionQueueManager {
        let audioURL = audioURL
        return TranscriptionQueueManager(
            dataManager: dataManager,
            engineFactory: MockEngineFactory(engine: engine),
            artifactStore: TranscriptionArtifactStore(directoryURL: workDirectory.appendingPathComponent("artifacts", isDirectory: true)),
            engineMode: { engineMode },
            audioFileURL: { _ in audioURL },
            thermalState: { thermalState },
            powerState: { powerState() },
            batteryPolicy: { batteryPolicy },
            podcastDisablesRemote: { _ in podcastDisablesRemote },
            remoteConsent: { _ in remoteConsent },
            contributionEnqueue: contributionEnqueue
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

    // MARK: - Battery policy

    func testPowerDeferralLeavesLocalJobQueuedWithoutRunningEngine() async throws {
        let engine = MockSpeechEngine(segments: [ASRSegment(text: "hi", start: 0, end: 1)])
        let manager = makeManager(engine: engine,
                                  powerState: { TranscriptionPowerState(batteryLevel: 0.2, isCharging: false, isLowPowerModeEnabled: false) },
                                  batteryPolicy: .above30Percent)

        await manager.enqueue(episodeUuid: "episode-drained", podcastUuid: nil)
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-drained"))
        XCTAssertEqual(record.transcriptionStatus, .queued, "A power-deferred job is requeued, never cancelled or failed")
        XCTAssertFalse(engine.prepareCalled)

        let stillQueued = await manager.isEpisodeQueued("episode-drained")
        XCTAssertTrue(stillQueued)
    }

    func testPowerDeferredJobResumesWhenConditionsClear() async throws {
        let engine = MockSpeechEngine(segments: [ASRSegment(text: "resumed after charging", start: 0, end: 2)])
        let power = Mutex(TranscriptionPowerState(batteryLevel: 0.1, isCharging: false, isLowPowerModeEnabled: false))
        let manager = makeManager(engine: engine,
                                  powerState: { power.withLock { $0 } },
                                  batteryPolicy: .onlyWhileCharging)

        await manager.enqueue(episodeUuid: "episode-resumes", podcastUuid: nil)
        await manager.drainUntilIdle()
        XCTAssertFalse(engine.prepareCalled)

        power.withLock { $0 = TranscriptionPowerState(batteryLevel: 0.1, isCharging: true, isLowPowerModeEnabled: false) }
        await manager.powerConditionsChanged()
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-resumes"))
        XCTAssertEqual(record.transcriptionStatus, .completed)
    }

    func testPowerChangeDefersInFlightLocalJob() async throws {
        // The settings UI promises "Low Power Mode always pauses transcription":
        // a local job that started under good conditions must stop (and requeue)
        // when the power state degrades mid-flight.
        let engine = MockSpeechEngine(segments: [ASRSegment(text: "never finishes", start: 0, end: 1)],
                                      blockDuringTranscribe: true)
        let power = Mutex(TranscriptionPowerState(batteryLevel: 1, isCharging: false, isLowPowerModeEnabled: false))
        let manager = makeManager(engine: engine,
                                  powerState: { power.withLock { $0 } },
                                  batteryPolicy: .always)

        await manager.enqueue(episodeUuid: "episode-lpm", podcastUuid: nil)
        try await waitUntil("transcription reaches the transcribe stage") { engine.transcribeStarted }

        power.withLock { $0 = TranscriptionPowerState(batteryLevel: 1, isCharging: false, isLowPowerModeEnabled: true) }
        await manager.powerConditionsChanged()
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-lpm"))
        XCTAssertEqual(record.transcriptionStatus, .queued,
                       "A mid-job power deferral requeues the job — never cancels or fails it")
        let state = await manager.state(for: "episode-lpm")
        XCTAssertEqual(state, .queued)
        let stillQueued = await manager.isEpisodeQueued("episode-lpm")
        XCTAssertTrue(stillQueued)
    }

    // MARK: - Deletion durability

    func testDeleteAllSweepsOrphanedGeneratedFTSRows() async throws {
        // A crash between the old delete steps (record first, FTS second) could
        // leave generated FTS rows with no record; Clear All iterates records,
        // so it must sweep the index too.
        let orphan = TranscriptSearchSegment(index: 0, text: "orphaned stranded segment", startTime: 0, endTime: 2, speaker: nil)
        XCTAssertTrue(dataManager.transcriptSearch.replaceSegments(episodeUuid: "episode-orphan",
                                                                   podcastUuid: nil,
                                                                   source: .generated,
                                                                   segments: [orphan]))
        XCTAssertFalse(dataManager.transcriptSearch.search(term: "stranded", limit: 10, source: .generated).isEmpty)

        let engine = MockSpeechEngine(segments: [ASRSegment(text: "a real recorded transcription", start: 0, end: 2)])
        let manager = makeManager(engine: engine)
        await manager.enqueue(episodeUuid: "episode-real", podcastUuid: nil)
        await manager.drainUntilIdle()

        await manager.deleteAllTranscriptions()

        XCTAssertTrue(dataManager.transcriptions.allRecords().isEmpty)
        XCTAssertTrue(dataManager.transcriptSearch.search(term: "recorded", limit: 10, source: .generated).isEmpty)
        XCTAssertTrue(dataManager.transcriptSearch.search(term: "stranded", limit: 10, source: .generated).isEmpty,
                      "Clear All must sweep FTS rows whose record is already gone")
    }

    // MARK: - Engine fallback (always-on policy)

    func testRemoteModeWithPodcastOptOutFallsBackToLocalEngine() async throws {
        let engine = MockSpeechEngine(segments: [ASRSegment(text: "local fallback words", start: 0, end: 2)])
        let manager = makeManager(engine: engine, engineMode: .remoteProvider, podcastDisablesRemote: true)

        await manager.enqueue(episodeUuid: "episode-optout", podcastUuid: "pod-optout")
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-optout"))
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertEqual(record.engineMode, TranscriptionEngineMode.appleBuiltIn.rawValue,
                       "The opted-out podcast must transcribe on-device despite the remote global mode")
        XCTAssertTrue(engine.prepareCalled)
    }

    func testRemoteModeWithoutConsentFallsBackToLocalEngine() async throws {
        let engine = MockSpeechEngine(segments: [ASRSegment(text: "no consent yet", start: 0, end: 2)])
        let manager = makeManager(engine: engine, engineMode: .remoteProvider, remoteConsent: false)

        await manager.enqueue(episodeUuid: "episode-noconsent", podcastUuid: nil)
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-noconsent"))
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertEqual(record.engineMode, TranscriptionEngineMode.appleBuiltIn.rawValue,
                       "Auto-runs must never spend remote credits before the user consented to the provider")
    }

    // MARK: - Contribution hook

    /// Podcast + episode rows so the contribution eligibility gate can resolve them.
    private func insertEligibilityFixture(episodeUuid: String, podcastUuid: String, refreshSource: PodcastRefreshSource = .server) {
        var podcast = Podcast()
        podcast.uuid = podcastUuid
        podcast.addedDate = Date()
        podcast.feedRefreshSource = refreshSource
        _ = dataManager.save(podcast: podcast)
        var episode = Episode()
        episode.uuid = episodeUuid
        episode.podcastUuid = podcastUuid
        episode.addedDate = Date()
        dataManager.save(episode: episode)
    }

    /// A queue manager whose contribution hook runs the REAL enqueue path
    /// against this suite's isolated database (the production default targets
    /// DataManager.sharedManager).
    private func makeManagerWithContributionHook(engine: MockSpeechEngine) -> TranscriptionQueueManager {
        let dataManager: DataManager = dataManager
        return makeManager(engine: engine, contributionEnqueue: { episodeUuid, record in
            TranscriptContributionManager.enqueueContribution(
                episodeUuid: episodeUuid,
                record: record,
                dataManager: dataManager,
                hasConsent: true
            )
        })
    }

    func testCompleteEnqueuesContributionForEligibleEpisode() async throws {
        insertEligibilityFixture(episodeUuid: "episode-contrib", podcastUuid: "podcast-contrib")
        let engine = MockSpeechEngine(segments: [ASRSegment(text: "worth contributing", start: 0, end: 9)])
        let manager = makeManagerWithContributionHook(engine: engine)

        await manager.enqueue(episodeUuid: "episode-contrib", podcastUuid: "podcast-contrib")
        await manager.drainUntilIdle()

        let rows = dataManager.pendingTranscriptUploads.allRecords()
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.uploadKind, .contribution)
        XCTAssertEqual(row.episodeUuid, "episode-contrib")
        XCTAssertEqual(row.podcastUuid, "podcast-contrib")
        XCTAssertEqual(row.attempts, 0)
        XCTAssertNil(row.nextAttemptAt, "A fresh contribution is due immediately")

        let info = try JSONDecoder().decode(TranscriptContributionManager.ContributionInfo.self,
                                            from: Data(row.payloadJson.utf8))
        XCTAssertEqual(info.engine, "applespeech")
        XCTAssertFalse(info.diarized)
        XCTAssertEqual(info.durationSeconds, 9, accuracy: 0.001,
                       "With no episode duration the transcript span is the sanity anchor")
    }

    func testCompleteDoesNotEnqueueContributionForPrivateLocalFeedPodcast() async throws {
        let previousStore = KeychainHelper.store
        defer { KeychainHelper.store = previousStore }
        KeychainHelper.store = InMemoryKeychainStore()
        LocalFeedCredentials.save(user: "user", password: "pass", podcastUuid: "podcast-private")
        insertEligibilityFixture(episodeUuid: "episode-private", podcastUuid: "podcast-private", refreshSource: .localFeed)
        let engine = MockSpeechEngine(segments: [ASRSegment(text: "private words", start: 0, end: 3)])
        let manager = makeManagerWithContributionHook(engine: engine)

        await manager.enqueue(episodeUuid: "episode-private", podcastUuid: "podcast-private")
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-private"))
        XCTAssertEqual(record.transcriptionStatus, .completed, "The transcription itself must still complete")
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0,
                       "Nothing from a private local feed is ever uploaded")
    }

    func testDeleteTranscriptionCancelsPendingContributionAndCachedFingerprint() async throws {
        insertEligibilityFixture(episodeUuid: "episode-del", podcastUuid: "podcast-del")
        let engine = MockSpeechEngine(segments: [ASRSegment(text: "soon deleted", start: 0, end: 2)])
        let manager = makeManagerWithContributionHook(engine: engine)

        await manager.enqueue(episodeUuid: "episode-del", podcastUuid: "podcast-del")
        await manager.drainUntilIdle()
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 1)

        // A cached upload fingerprint and an unrelated sighting row must behave
        // differently on delete: the fingerprint goes, the sighting survives.
        let artifactStore = TranscriptionArtifactStore(directoryURL: workDirectory.appendingPathComponent("artifacts", isDirectory: true))
        try artifactStore.writeFingerprint(Data("gzipped fingerprint".utf8), episodeUuid: "episode-del")
        var sighting = PendingTranscriptUploadRecord()
        sighting.episodeUuid = "episode-del"
        sighting.podcastUuid = "podcast-del"
        sighting.uploadKind = .sighting
        sighting.payloadJson = "{}"
        dataManager.pendingTranscriptUploads.insert(sighting)

        await manager.deleteTranscription(episodeUuid: "episode-del")

        let remaining = dataManager.pendingTranscriptUploads.allRecords()
        XCTAssertEqual(remaining.map(\.uploadKind), [.sighting],
                       "Local deletion cancels pending contribution uploads only")
        XCTAssertNil(artifactStore.readFingerprint(episodeUuid: "episode-del"),
                     "The cached fingerprint must not outlive its transcription")
    }

    func testCleanupUnusableCompletedRecordDoesNotDeleteNewerRetry() async throws {
        let manager = makeManager(engine: MockSpeechEngine())
        var inspected = EpisodeTranscriptionRecord()
        inspected.episodeUuid = "episode-retried"
        inspected.transcriptionStatus = .completed
        inspected.createdAt = 100
        inspected.updatedAt = 200
        XCTAssertTrue(dataManager.transcriptions.upsert(inspected))

        var retried = inspected
        retried.transcriptionStatus = .queued
        retried.updatedAt = 300
        XCTAssertTrue(dataManager.transcriptions.upsert(retried))

        let deleted = await manager.cleanupUnusableCompletedTranscription(expected: inspected)

        XCTAssertFalse(deleted)
        XCTAssertEqual(dataManager.transcriptions.find(episodeUuid: inspected.episodeUuid), retried,
                       "Cleanup based on an old load must preserve a newer retry")
    }

    func testCleanupRevalidatesArtifactBeforeDeletingCompletedRecord() async throws {
        let manager = makeManager(engine: MockSpeechEngine())
        var inspected = EpisodeTranscriptionRecord()
        inspected.episodeUuid = "episode-restored"
        inspected.transcriptionStatus = .completed
        inspected.createdAt = 100
        inspected.updatedAt = 200
        XCTAssertTrue(dataManager.transcriptions.upsert(inspected))

        let artifactStore = TranscriptionArtifactStore(
            directoryURL: workDirectory.appendingPathComponent("artifacts", isDirectory: true)
        )
        try artifactStore.write(
            transcript: DiarizedTranscript(
                cues: [DiarizedCue(speaker: nil, text: "Restored", start: 0, end: 1)],
                language: "en",
                speakerCount: 1,
                engineDescription: "test"
            ),
            episodeUuid: inspected.episodeUuid
        )

        let deleted = await manager.cleanupUnusableCompletedTranscription(expected: inspected)

        XCTAssertFalse(deleted)
        XCTAssertEqual(dataManager.transcriptions.find(episodeUuid: inspected.episodeUuid), inspected,
                       "An artifact restored during the load must prevent cleanup")
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
