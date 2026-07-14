import Foundation
import GRDB
import PocketCastsServer
import PocketCastsUtils
import Synchronization
import XCTest

@testable import PocketCastsDataModel
@testable import podcasts

/// Exercises the contribution upload drain against an isolated database and a
/// mock sender: result mapping for every `ContributionSendResult`, the
/// fingerprint disk cache, the pause/park switch, backoff and the power gate.
final class TranscriptContributionManagerTests: XCTestCase {
    private var dataManager: DataManager!
    private var dbPool: DatabasePool!
    private var workDirectory: URL!
    private var artifactsDirectory: URL!
    private var audioURL: URL!
    private var artifactStore: TranscriptionArtifactStore!

    override func setUp() async throws {
        try await super.setUp()

        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-contribution-tests-\(UUID().uuidString)", isDirectory: true)
        artifactsDirectory = workDirectory.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsDirectory, withIntermediateDirectories: true)

        var configuration = Configuration()
        configuration.busyMode = .timeout(10)
        dbPool = try DatabasePool(path: workDirectory.appendingPathComponent("test.sqlite3").path, configuration: configuration)
        dataManager = try DataManager(dbQueue: GRDBQueue(dbPool: dbPool))

        artifactStore = TranscriptionArtifactStore(directoryURL: artifactsDirectory)

        audioURL = workDirectory.appendingPathComponent("episode.mp3")
        try Data("not really audio, fingerprinting is mocked".utf8).write(to: audioURL)
    }

    override func tearDown() async throws {
        try? dbPool.close()
        try? FileManager.default.removeItem(at: workDirectory)
        try await super.tearDown()
    }

    // MARK: - Harness

    /// Everything the mock seams record during a drain.
    nonisolated private final class Recorder: Sendable {
        let contributions = Mutex<[TranscriptContributionPayload]>([])
        let sightings = Mutex<[TranscriptSightingPayload]>([])
        let fingerprintCalls = Mutex(0)
        let attestationHandled = Mutex(false)
        let pausedUntil = Mutex<Date?>(nil)

        var sendCount: Int {
            contributions.withLock { $0.count } + sightings.withLock { $0.count }
        }
    }

    private func makeManager(recorder: Recorder,
                             result: ContributionSendResult,
                             powerDeferred: Bool = false,
                             fingerprintData: Data = Data("fingerprint-json".utf8)) -> TranscriptContributionManager {
        let audioURL = audioURL
        return TranscriptContributionManager(
            dataManager: dataManager,
            artifactStore: artifactStore,
            audioFileURL: { _ in audioURL },
            fingerprint: { _ in
                recorder.fingerprintCalls.withLock { $0 += 1 }
                return fingerprintData
            },
            gzip: { $0 }, // Identity: payload bytes are asserted against the inputs.
            sendContribution: { payload in
                recorder.contributions.withLock { $0.append(payload) }
                return result
            },
            sendSighting: { payload in
                recorder.sightings.withLock { $0.append(payload) }
                return result
            },
            powerState: {
                TranscriptionPowerState(batteryLevel: 1,
                                        isCharging: !powerDeferred,
                                        isLowPowerModeEnabled: powerDeferred)
            },
            batteryPolicy: { .always },
            handleAttestationRejection: { recorder.attestationHandled.withLock { $0 = true } },
            appVersion: { "7.99-test" },
            loadPausedUntil: { recorder.pausedUntil.withLock { $0 } },
            storePausedUntil: { date in recorder.pausedUntil.withLock { $0 = date } },
            now: { Date() }
        )
    }

    private static let vttBody = "WEBVTT\n\n00:00:00.000 --> 00:00:04.000\n<v Speaker 1>Hello contribution world.\n"

    /// A completed transcription record + VTT artifact + pending contribution
    /// row, ready to drain. Returns the row id.
    @discardableResult
    private func seedContribution(episodeUuid: String = "ep-1",
                                  podcastUuid: String = "pod-1",
                                  withRecord: Bool = true,
                                  withArtifact: Bool = true) throws -> Int64 {
        if withRecord {
            var record = EpisodeTranscriptionRecord()
            record.episodeUuid = episodeUuid
            record.podcastUuid = podcastUuid
            record.transcriptionStatus = .completed
            record.createdAt = Date().timeIntervalSince1970
            XCTAssertTrue(dataManager.transcriptions.upsert(record))
        }
        if withArtifact {
            try Self.vttBody.write(to: artifactStore.fileURL(forEpisodeUuid: episodeUuid), atomically: true, encoding: .utf8)
        }

        let info = TranscriptContributionManager.ContributionInfo(engine: "whisperkit",
                                                                  modelId: "openai_whisper-small",
                                                                  language: "en",
                                                                  diarized: true,
                                                                  durationSeconds: 1234,
                                                                  createdAt: 1_700_000_000)
        var row = PendingTranscriptUploadRecord()
        row.episodeUuid = episodeUuid
        row.podcastUuid = podcastUuid
        row.uploadKind = .contribution
        row.payloadJson = try String(decoding: JSONEncoder().encode(info), as: UTF8.self)
        XCTAssertTrue(dataManager.pendingTranscriptUploads.insert(row))
        return try XCTUnwrap(dataManager.pendingTranscriptUploads.allRecords().last?.id)
    }

    @discardableResult
    private func seedSighting(episodeUuid: String = "ep-1", podcastUuid: String = "pod-1") throws -> Int64 {
        let info = TranscriptContributionManager.SightingInfo(url: "https://example.com/t.vtt",
                                                              format: "text/vtt",
                                                              language: "en")
        var row = PendingTranscriptUploadRecord()
        row.episodeUuid = episodeUuid
        row.podcastUuid = podcastUuid
        row.uploadKind = .sighting
        row.payloadJson = try String(decoding: JSONEncoder().encode(info), as: UTF8.self)
        XCTAssertTrue(dataManager.pendingTranscriptUploads.insert(row))
        return try XCTUnwrap(dataManager.pendingTranscriptUploads.allRecords().last?.id)
    }

    private func drain(_ manager: TranscriptContributionManager) async {
        await manager.kick()
        await manager.drainUntilIdle()
    }

    // MARK: - Result mapping

    func testAcceptedContributionDeletesRowAndCachedFingerprint() async throws {
        try seedContribution()
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .accepted)

        await drain(manager)

        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0)
        XCTAssertNil(artifactStore.readFingerprint(episodeUuid: "ep-1"),
                     "The cache exists only to survive retries; success removes it")

        let payload = try XCTUnwrap(recorder.contributions.withLock { $0.first })
        XCTAssertEqual(payload.episodeUuid, "ep-1")
        XCTAssertEqual(payload.podcastUuid, "pod-1")
        XCTAssertEqual(payload.gzippedVtt, Data(Self.vttBody.utf8))
        XCTAssertEqual(payload.gzippedFingerprint, Data("fingerprint-json".utf8))
        XCTAssertEqual(payload.engine, "whisperkit")
        XCTAssertEqual(payload.modelId, "openai_whisper-small")
        XCTAssertEqual(payload.language, "en")
        XCTAssertTrue(payload.diarized)
        XCTAssertEqual(payload.appVersion, "7.99-test")
        XCTAssertEqual(payload.episodeDurationSeconds, 1234, accuracy: 0.001)
        XCTAssertEqual(payload.createdAt.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
    }

    func testAcceptedSightingSendsCapturedMetadata() async throws {
        try seedSighting()
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .accepted)

        await drain(manager)

        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0)
        let payload = try XCTUnwrap(recorder.sightings.withLock { $0.first })
        XCTAssertEqual(payload.episodeUuid, "ep-1")
        XCTAssertEqual(payload.podcastUuid, "pod-1")
        XCTAssertEqual(payload.transcriptUrl, "https://example.com/t.vtt")
        XCTAssertEqual(payload.format, "text/vtt")
        XCTAssertEqual(payload.language, "en")
    }

    func testRetryAfterBacksOffRowAndDoesNotResendUntilDue() async throws {
        try seedContribution()
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .retryAfter(1))

        let before = Date()
        await drain(manager)

        let row = try XCTUnwrap(dataManager.pendingTranscriptUploads.allRecords().first)
        XCTAssertEqual(row.attempts, 1)
        let nextAttemptAt = try XCTUnwrap(row.nextAttemptAt)
        // Backoff floor (60s for attempt 1) dominates the server's 1s hint.
        XCTAssertEqual(nextAttemptAt, before.timeIntervalSince1970 + 60, accuracy: 10)

        await drain(manager)
        XCTAssertEqual(recorder.sendCount, 1, "A backed-off row must not be re-sent before nextAttemptAt")
    }

    func testRetryAfterHonorsServerDelayWhenLongerThanBackoff() async throws {
        try seedContribution()
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .retryAfter(600))

        let before = Date()
        await drain(manager)

        let row = try XCTUnwrap(dataManager.pendingTranscriptUploads.allRecords().first)
        let nextAttemptAt = try XCTUnwrap(row.nextAttemptAt)
        XCTAssertEqual(nextAttemptAt, before.timeIntervalSince1970 + 600, accuracy: 10)
    }

    func testPauseQueuePersistsParkDateAndBlocksSubsequentDrains() async throws {
        try seedContribution()
        try seedSighting(episodeUuid: "ep-2", podcastUuid: "pod-2")
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .pauseQueue(3600))

        let before = Date()
        await drain(manager)

        // The first row's response parks the WHOLE queue: exactly one send.
        XCTAssertEqual(recorder.sendCount, 1)
        let pausedUntil = try XCTUnwrap(recorder.pausedUntil.withLock { $0 })
        XCTAssertEqual(pausedUntil.timeIntervalSince(before), 3600, accuracy: 10)

        // Rows are untouched — they resume when the pause lapses.
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 2)
        XCTAssertTrue(dataManager.pendingTranscriptUploads.allRecords().allSatisfy { $0.attempts == 0 })

        await drain(manager)
        XCTAssertEqual(recorder.sendCount, 1, "A parked queue must not send anything")

        // Pause elapsed: the drain resumes with the oldest row (whose pauseQueue
        // response then re-parks the queue before the second row is reached).
        recorder.pausedUntil.withLock { $0 = Date(timeIntervalSinceNow: -1) }
        await drain(manager)
        XCTAssertEqual(recorder.sendCount, 2)
    }

    func testAttestationRejectionRunsHandlerAndRetries() async throws {
        try seedContribution()
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .attestationRejected)

        let before = Date()
        await drain(manager)

        XCTAssertTrue(recorder.attestationHandled.withLock { $0 }, "Must re-enroll the App Attest key")
        let row = try XCTUnwrap(dataManager.pendingTranscriptUploads.allRecords().first)
        XCTAssertEqual(row.attempts, 1)
        let nextAttemptAt = try XCTUnwrap(row.nextAttemptAt)
        XCTAssertEqual(nextAttemptAt, before.timeIntervalSince1970 + 60, accuracy: 10)
    }

    func testPermanentFailureDeletesRow() async throws {
        try seedContribution()
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .permanentFailure("cue span mismatch"))

        await drain(manager)

        XCTAssertEqual(recorder.sendCount, 1)
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0,
                       "Validation failures never succeed with the same bytes — the one terminal case")
    }

    // MARK: - Tombstone

    func testDeletedTranscriptionDropsContributionWithoutSending() async throws {
        try seedContribution(withRecord: false)
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .accepted)

        await drain(manager)

        XCTAssertEqual(recorder.sendCount, 0, "No transcription record = tombstoned; nothing must be uploaded")
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0)
    }

    // MARK: - Fingerprint cache

    func testFingerprintIsComputedOnceAndCachedOnDisk() async throws {
        try seedContribution()
        let recorder = Recorder()
        // retryAfter leaves the row queued, so the cache write is observable.
        let manager = makeManager(recorder: recorder, result: .retryAfter(1))

        await drain(manager)

        XCTAssertEqual(recorder.fingerprintCalls.withLock { $0 }, 1)
        XCTAssertEqual(artifactStore.readFingerprint(episodeUuid: "ep-1"), Data("fingerprint-json".utf8),
                       "The gzipped fingerprint must be cached next to the VTT artifact")
    }

    func testCachedFingerprintSkipsRecomputation() async throws {
        try seedContribution()
        try artifactStore.writeFingerprint(Data("cached-bytes".utf8), episodeUuid: "ep-1")
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .accepted)

        await drain(manager)

        XCTAssertEqual(recorder.fingerprintCalls.withLock { $0 }, 0,
                       "Retries must never re-decode the audio when the cache exists")
        let payload = try XCTUnwrap(recorder.contributions.withLock { $0.first })
        XCTAssertEqual(payload.gzippedFingerprint, Data("cached-bytes".utf8))
    }

    // MARK: - Power gate

    func testPowerDeferredStopsDrainWithoutSending() async throws {
        try seedContribution()
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .accepted, powerDeferred: true)

        await drain(manager)

        XCTAssertEqual(recorder.sendCount, 0, "Uploads obey the transcription battery policy")
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 1)
    }

    // MARK: - Backoff

    func testBackoffGrowsWithAttemptsAndIsCapped() {
        XCTAssertEqual(TranscriptContributionManager.backoffInterval(attempts: 1), 60)
        XCTAssertEqual(TranscriptContributionManager.backoffInterval(attempts: 2), 120)
        XCTAssertEqual(TranscriptContributionManager.backoffInterval(attempts: 3), 240)
        XCTAssertLessThan(TranscriptContributionManager.backoffInterval(attempts: 5),
                          TranscriptContributionManager.backoffInterval(attempts: 6))
        XCTAssertEqual(TranscriptContributionManager.backoffInterval(attempts: 30),
                       TranscriptContributionManager.maxRetryInterval)
    }

    // MARK: - Sighting enqueue

    private func insertEligibilityFixture(episodeUuid: String, podcastUuid: String,
                                          refreshSource: PodcastRefreshSource = .server) {
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

    func testNoteSightingDeduplicatesPerEpisode() throws {
        insertEligibilityFixture(episodeUuid: "ep-s", podcastUuid: "pod-s")

        for _ in 0..<3 {
            TranscriptContributionManager.noteSighting(episodeUuid: "ep-s",
                                                       podcastUuid: "pod-s",
                                                       transcriptUrl: "https://example.com/t.vtt",
                                                       format: "text/vtt",
                                                       language: "en",
                                                       dataManager: dataManager,
                                                       kickAfterInsert: false)
        }

        let rows = dataManager.pendingTranscriptUploads.allRecords()
        XCTAssertEqual(rows.count, 1, "Sightings are deduplicated locally per episode")
        XCTAssertEqual(rows.first?.uploadKind, .sighting)
        let info = try JSONDecoder().decode(TranscriptContributionManager.SightingInfo.self,
                                            from: Data(try XCTUnwrap(rows.first?.payloadJson).utf8))
        XCTAssertEqual(info.url, "https://example.com/t.vtt")
        XCTAssertEqual(info.format, "text/vtt")
        XCTAssertEqual(info.language, "en")
    }

    func testNoteSightingRejectsTokenCarryingURL() {
        insertEligibilityFixture(episodeUuid: "ep-s", podcastUuid: "pod-s")

        TranscriptContributionManager.noteSighting(episodeUuid: "ep-s",
                                                   podcastUuid: "pod-s",
                                                   transcriptUrl: "https://example.com/t.vtt?token=abc",
                                                   format: "text/vtt",
                                                   language: nil,
                                                   dataManager: dataManager,
                                                   kickAfterInsert: false)

        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0)
    }

    func testNoteSightingRejectsPrivateLocalFeedPodcast() {
        let previousStore = KeychainHelper.store
        defer { KeychainHelper.store = previousStore }
        KeychainHelper.store = InMemoryKeychainStore()
        LocalFeedCredentials.save(user: "user", password: "pass", podcastUuid: "pod-s")
        insertEligibilityFixture(episodeUuid: "ep-s", podcastUuid: "pod-s", refreshSource: .localFeed)

        TranscriptContributionManager.noteSighting(episodeUuid: "ep-s",
                                                   podcastUuid: "pod-s",
                                                   transcriptUrl: "https://example.com/t.vtt",
                                                   format: "text/vtt",
                                                   language: nil,
                                                   dataManager: dataManager,
                                                   kickAfterInsert: false)

        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0,
                       "A credentialed (private) feed is never sighted")
    }

    func testNoteSightingAcceptsPublicLocalFeedPodcast() {
        let previousStore = KeychainHelper.store
        defer { KeychainHelper.store = previousStore }
        KeychainHelper.store = InMemoryKeychainStore()
        insertEligibilityFixture(episodeUuid: "ep-pub", podcastUuid: "pod-pub", refreshSource: .localFeed)

        TranscriptContributionManager.noteSighting(episodeUuid: "ep-pub",
                                                   podcastUuid: "pod-pub",
                                                   transcriptUrl: "https://example.com/t.vtt",
                                                   format: "text/vtt",
                                                   language: nil,
                                                   dataManager: dataManager,
                                                   kickAfterInsert: false)

        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 1,
                       "A credential-less locally-refreshed feed is public — out-of-catalog episodes are deliberately eligible")
    }
}
