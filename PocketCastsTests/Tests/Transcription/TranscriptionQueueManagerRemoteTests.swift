import Foundation
import GRDB
import PocketCastsTranscription
import PocketCastsUtils
import Synchronization
import XCTest

@testable import PocketCastsDataModel
@testable import podcasts

/// Exercises the remote-provider pipeline of `TranscriptionQueueManager` against
/// a mock provider: synchronous completion, async submit → persist job id → poll
/// → complete, poll resumption from a restored record, and key/credential failures.
final class TranscriptionQueueManagerRemoteTests: XCTestCase {
    private var dataManager: DataManager!
    private var dbPool: DatabasePool!
    private var workDirectory: URL!
    private var audioURL: URL!

    override func setUp() async throws {
        try await super.setUp()

        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-remote-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)

        // A private pool (rather than DataManager.newTestDataManager()) so this
        // suite can't close the shared pool other suites hold on to.
        var configuration = Configuration()
        configuration.busyMode = .timeout(10)
        dbPool = try DatabasePool(path: workDirectory.appendingPathComponent("test.sqlite3").path, configuration: configuration)
        dataManager = try DataManager(dbQueue: GRDBQueue(dbPool: dbPool))

        audioURL = workDirectory.appendingPathComponent("episode.mp3")
        try Data("not really audio, the provider is mocked".utf8).write(to: audioURL)
    }

    override func tearDown() async throws {
        try? dbPool.close()
        try? FileManager.default.removeItem(at: workDirectory)
        try await super.tearDown()
    }

    private func makeManager(provider: MockRemoteProvider,
                             apiKey: String? = "unit-test-key",
                             downloadURL: URL? = URL(string: "https://example.com/episode.mp3"),
                             batteryPolicy: TranscriptionBatteryPolicy = .always,
                             powerState: TranscriptionPowerState = TranscriptionPowerState(batteryLevel: 1, isCharging: true, isLowPowerModeEnabled: false)) -> TranscriptionQueueManager {
        let audioURL = audioURL
        return TranscriptionQueueManager(
            dataManager: dataManager,
            engineFactory: MockRemoteFactory(provider: provider),
            artifactStore: TranscriptionArtifactStore(directoryURL: workDirectory.appendingPathComponent("artifacts", isDirectory: true)),
            engineMode: { .remoteProvider },
            audioFileURL: { _ in audioURL },
            thermalState: { .nominal },
            powerState: { powerState },
            batteryPolicy: { batteryPolicy },
            podcastDisablesRemote: { _ in false },
            remoteConsent: { _ in true },
            remoteProviderId: { "mock" },
            remoteAPIKey: { _ in apiKey },
            episodeDownloadURL: { _ in downloadURL },
            transcodeForUpload: { url in AudioTranscodeHelper.Output(url: url, mimeType: "audio/mp4", isTemporary: false) },
            contributionEnqueue: { _, _ in },
            pollSchedule: TranscriptionQueueManager.PollSchedule(initialInterval: 0.01,
                                                                 backoffFactor: 1,
                                                                 maxInterval: 0.01,
                                                                 overallTimeout: 10)
        )
    }

    private static func makeTranscript() -> DiarizedTranscript {
        DiarizedTranscript(cues: [
            DiarizedCue(speaker: "Speaker 1", text: "Hello from the mock provider.", start: 0, end: 3),
            DiarizedCue(speaker: "Speaker 2", text: "Glad to be transcribed.", start: 3.5, end: 6),
        ], language: "en", speakerCount: 2, engineDescription: "mock")
    }

    // MARK: - Tests

    func testSynchronousProviderCompletesInOnePass() async throws {
        let provider = MockRemoteProvider(submitResult: .success(.completed(Self.makeTranscript())))
        let manager = makeManager(provider: provider)

        await manager.enqueue(episodeUuid: "episode-sync", podcastUuid: "podcast-1")
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-sync"))
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertEqual(record.provider, "mock")
        XCTAssertEqual(record.engineMode, TranscriptionEngineMode.remoteProvider.rawValue)
        XCTAssertEqual(record.speakerCount, 2)
        XCTAssertNil(record.remoteJobId)

        let vtt = try String(contentsOfFile: try XCTUnwrap(record.filePath), encoding: .utf8)
        XCTAssertTrue(vtt.contains("<v Speaker 1>Hello from the mock provider."))

        let hits = dataManager.transcriptSearch.search(term: "transcribed", limit: 10, source: .generated)
        XCTAssertEqual(hits.first?.episodeUuid, "episode-sync")

        // Public URL provider + parseable download URL → no upload happened.
        XCTAssertEqual(provider.submittedSources, ["publicURL(https://example.com/episode.mp3)"])
        XCTAssertEqual(provider.pollCount, 0)
    }

    func testRemoteJobIgnoresBatteryPolicy() async throws {
        // Remote jobs cost network, not compute: even the strictest battery
        // policy must not defer them.
        let provider = MockRemoteProvider(submitResult: .success(.completed(Self.makeTranscript())))
        let manager = makeManager(provider: provider,
                                  batteryPolicy: .onlyWhileCharging,
                                  powerState: TranscriptionPowerState(batteryLevel: 0.1, isCharging: false, isLowPowerModeEnabled: false))

        await manager.enqueue(episodeUuid: "episode-battery", podcastUuid: "podcast-1")
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-battery"))
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertEqual(record.engineMode, TranscriptionEngineMode.remoteProvider.rawValue)
    }

    func testUploadProviderReceivesTranscodedFile() async throws {
        let provider = MockRemoteProvider(submitResult: .success(.completed(Self.makeTranscript())),
                                          supportsPublicURL: false)
        let manager = makeManager(provider: provider)

        await manager.enqueue(episodeUuid: "episode-upload", podcastUuid: nil)
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-upload"))
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertEqual(provider.submittedSources, ["fileUpload(\(audioURL.lastPathComponent), audio/mp4)"])
    }

    func testAsyncJobPersistsJobIdThenPollsToCompletion() async throws {
        let provider = MockRemoteProvider(
            submitResult: .success(.job(RemoteJobHandle(providerId: "mock", jobId: "job-9"))),
            pollResults: [.success(.processing(0.4)), .success(.completed(Self.makeTranscript()))]
        )
        provider.onSubmitted = { [dataManager] in
            // The job id must be durable before the first poll, so a crash can resume.
            dataManager?.transcriptions.find(episodeUuid: "episode-async")?.remoteJobId
        }
        let manager = makeManager(provider: provider)

        await manager.enqueue(episodeUuid: "episode-async", podcastUuid: nil)
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-async"))
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertNil(record.remoteJobId, "Completed records must not keep a stale job id")
        XCTAssertEqual(provider.pollCount, 2)
        XCTAssertEqual(provider.polledJobIds.first, "job-9")
        XCTAssertEqual(provider.persistedJobIdBeforeFirstPoll, "job-9")
    }

    func testMissingKeyFailsWithoutContactingProvider() async throws {
        let provider = MockRemoteProvider(submitResult: .success(.completed(Self.makeTranscript())))
        let manager = makeManager(provider: provider, apiKey: nil)

        await manager.enqueue(episodeUuid: "episode-nokey", podcastUuid: nil)
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-nokey"))
        XCTAssertEqual(record.transcriptionStatus, .failed)
        XCTAssertEqual(record.errorMessage, "invalidAPIKey")
        XCTAssertEqual(provider.submitCount, 0)

        let state = await manager.state(for: "episode-nokey")
        XCTAssertEqual(state, .failed(.invalidAPIKey))
    }

    func testRestorePendingJobsResumesPollingWithoutResubmitting() async throws {
        // A previous run submitted the job and crashed mid-poll.
        var crashed = EpisodeTranscriptionRecord()
        crashed.episodeUuid = "episode-resume"
        crashed.transcriptionStatus = .processing
        crashed.engineMode = TranscriptionEngineMode.remoteProvider.rawValue
        crashed.provider = "mock"
        crashed.remoteJobId = "resume-42"
        crashed.createdAt = Date().timeIntervalSince1970
        dataManager.transcriptions.upsert(crashed)

        let provider = MockRemoteProvider(
            submitResult: .success(.job(RemoteJobHandle(providerId: "mock", jobId: "should-not-submit"))),
            pollResults: [.success(.completed(Self.makeTranscript()))]
        )
        let manager = makeManager(provider: provider)

        await manager.restorePendingJobs()
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-resume"))
        XCTAssertEqual(record.transcriptionStatus, .completed)
        XCTAssertNil(record.remoteJobId)
        XCTAssertEqual(provider.submitCount, 0, "Resuming must never re-submit (and re-bill) the job")
        XCTAssertEqual(provider.polledJobIds, ["resume-42"])
    }

    func testPollReportedFailureFailsTheJob() async throws {
        let provider = MockRemoteProvider(
            submitResult: .success(.job(RemoteJobHandle(providerId: "mock", jobId: "job-fail"))),
            pollResults: [.success(.failed(.remoteJobFailed("provider exploded")))]
        )
        let manager = makeManager(provider: provider)

        await manager.enqueue(episodeUuid: "episode-pollfail", podcastUuid: nil)
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-pollfail"))
        XCTAssertEqual(record.transcriptionStatus, .failed)
        XCTAssertEqual(record.errorMessage, #"remoteJobFailed("provider exploded")"#)
    }

    func testSubmitErrorFailsTheJob() async throws {
        let provider = MockRemoteProvider(submitResult: .failure(.quotaExceeded))
        let manager = makeManager(provider: provider)

        await manager.enqueue(episodeUuid: "episode-quota", podcastUuid: nil)
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-quota"))
        XCTAssertEqual(record.transcriptionStatus, .failed)
        XCTAssertEqual(record.errorMessage, "quotaExceeded")
    }

    func testDeleteDuringNonCooperativeSubmitDoesNotResurrectRecord() async throws {
        let provider = MockRemoteProvider(submitResult: .success(.completed(Self.makeTranscript())),
                                          blockSubmitUntilReleased: true)
        let manager = makeManager(provider: provider)

        await manager.enqueue(episodeUuid: "episode-deleted", podcastUuid: "podcast-1")
        try await waitUntil("provider receives the submit") { provider.submitCount > 0 }

        // The user deletes mid-submit; the provider ignores the cancellation
        // and returns a finished transcript anyway.
        await manager.deleteTranscription(episodeUuid: "episode-deleted")
        provider.releaseSubmit()
        await manager.drainUntilIdle()

        XCTAssertNil(dataManager.transcriptions.find(episodeUuid: "episode-deleted"),
                     "A provider returning after deletion must not resurrect the record")
        XCTAssertTrue(dataManager.transcriptSearch.search(term: "transcribed", limit: 10, source: .generated).isEmpty,
                      "No FTS rows may be written for a deleted transcription")
        let artifactsDir = workDirectory.appendingPathComponent("artifacts", isDirectory: true)
        let artifacts = (try? FileManager.default.contentsOfDirectory(atPath: artifactsDir.path)) ?? []
        XCTAssertEqual(artifacts, [], "No artifact may be written for a deleted transcription")
    }

    func testPowerChangeDoesNotDeferInFlightRemoteJob() async throws {
        // Only LOCAL jobs pause on power changes (they cost compute); a remote
        // job in flight must run to completion even under the strictest policy
        // with Low Power Mode on.
        let provider = MockRemoteProvider(submitResult: .success(.completed(Self.makeTranscript())),
                                          blockSubmitUntilReleased: true)
        let manager = makeManager(provider: provider,
                                  batteryPolicy: .onlyWhileCharging,
                                  powerState: TranscriptionPowerState(batteryLevel: 0.1, isCharging: false, isLowPowerModeEnabled: true))

        await manager.enqueue(episodeUuid: "episode-remote-power", podcastUuid: nil)
        try await waitUntil("provider receives the submit") { provider.submitCount > 0 }

        await manager.powerConditionsChanged()
        provider.releaseSubmit()
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-remote-power"))
        XCTAssertEqual(record.transcriptionStatus, .completed,
                       "A power change must never cancel or requeue an in-flight remote job")
    }

    func testProviderResponseBodyIsKeptOutOfThePersistedRecord() async throws {
        let provider = MockRemoteProvider(
            submitResult: .failure(.remoteResponseFailure(status: 500, providerMessage: "request id abc123, user@example.com"))
        )
        let manager = makeManager(provider: provider)

        await manager.enqueue(episodeUuid: "episode-body", podcastUuid: nil)
        await manager.drainUntilIdle()

        let record = try XCTUnwrap(dataManager.transcriptions.find(episodeUuid: "episode-body"))
        XCTAssertEqual(record.transcriptionStatus, .failed)
        XCTAssertEqual(record.errorMessage, "remoteResponseFailure(HTTP 500)",
                       "Provider-generated response text must not reach the persisted record")

        // The full error (with the provider message) stays available in memory
        // for the failure UI.
        let state = await manager.state(for: "episode-body")
        XCTAssertEqual(state, .failed(.remoteResponseFailure(status: 500, providerMessage: "request id abc123, user@example.com")))
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

nonisolated private struct MockRemoteFactory: TranscriptionEngineProviding {
    let provider: MockRemoteProvider

    func makeEngine(for mode: TranscriptionEngineMode) throws -> any SpeechToTextEngine {
        // Remote jobs never resolve a local engine.
        throw TranscriptionError.engineFailure
    }

    func makeRemoteProvider(id: String) -> (any RemoteTranscriptionProvider)? {
        id == provider.id ? provider : nil
    }
}

nonisolated private final class MockRemoteProvider: RemoteTranscriptionProvider, Sendable {
    let id = "mock"
    let displayName = "Mock Provider"
    let supportsPublicURL: Bool

    private struct State {
        var submittedSources: [String] = []
        var polledJobIds: [String] = []
        var pollResults: [Result<RemoteJobStatus, TranscriptionError>]
        var persistedJobIdBeforeFirstPoll: String?
        var onSubmitted: (@Sendable () -> String?)?
    }

    private let submitResult: Result<SubmitOutcome, TranscriptionError>
    private let blockSubmitUntilReleased: Bool
    private let submitReleased = Mutex(false)
    private let state: Mutex<State>

    init(submitResult: Result<SubmitOutcome, TranscriptionError>,
         pollResults: [Result<RemoteJobStatus, TranscriptionError>] = [],
         supportsPublicURL: Bool = true,
         blockSubmitUntilReleased: Bool = false) {
        self.submitResult = submitResult
        self.supportsPublicURL = supportsPublicURL
        self.blockSubmitUntilReleased = blockSubmitUntilReleased
        state = Mutex(State(pollResults: pollResults))
    }

    /// Lets a `blockSubmitUntilReleased` submit return its result.
    func releaseSubmit() {
        submitReleased.withLock { $0 = true }
    }

    /// Ran right after submit returns, before the first poll; its return value
    /// is captured in `persistedJobIdBeforeFirstPoll`.
    var onSubmitted: (@Sendable () -> String?)? {
        get { state.withLock { $0.onSubmitted } }
        set { state.withLock { $0.onSubmitted = newValue } }
    }

    var submittedSources: [String] { state.withLock { $0.submittedSources } }
    var submitCount: Int { submittedSources.count }
    var polledJobIds: [String] { state.withLock { $0.polledJobIds } }
    var pollCount: Int { polledJobIds.count }
    var persistedJobIdBeforeFirstPoll: String? { state.withLock { $0.persistedJobIdBeforeFirstPoll } }

    func submit(source: RemoteAudioSource, language: String?, apiKey: String) async throws -> SubmitOutcome {
        let description: String
        switch source {
        case .publicURL(let url):
            description = "publicURL(\(url.absoluteString))"
        case .fileUpload(let url, let mimeType):
            description = "fileUpload(\(url.lastPathComponent), \(mimeType))"
        }
        state.withLock { $0.submittedSources.append(description) }
        if blockSubmitUntilReleased {
            // Deliberately IGNORES cancellation — models a non-cooperative
            // provider that returns a finished result after a cancel/delete.
            while !(submitReleased.withLock { $0 }) {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        return try submitResult.get()
    }

    func poll(handle: RemoteJobHandle, apiKey: String) async throws -> RemoteJobStatus {
        let result: Result<RemoteJobStatus, TranscriptionError> = state.withLock { state in
            if state.polledJobIds.isEmpty {
                state.persistedJobIdBeforeFirstPoll = state.onSubmitted?()
            }
            state.polledJobIds.append(handle.jobId)
            guard !state.pollResults.isEmpty else {
                return .success(.processing(nil))
            }
            return state.pollResults.removeFirst()
        }
        return try result.get()
    }
}
