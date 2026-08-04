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
        let wakeDelays = Mutex<[TimeInterval]>([])

        var sendCount: Int {
            contributions.withLock { $0.count } + sightings.withLock { $0.count }
        }
    }

    private func makeManager(recorder: Recorder,
                             result: ContributionSendResult,
                             powerDeferred: Bool = false,
                             fingerprintData: Data = Data("fingerprint-json".utf8),
                             audioFileURL: (@Sendable (String) -> URL?)? = nil,
                             fingerprint: (@Sendable (URL) async throws -> Data)? = nil,
                             resultScript: [ContributionSendResult]? = nil,
                             generateMetadata: @escaping @Sendable (String, String, TranscriptContributionManager.MetadataInfo) async -> TranscriptCorpusMetadataGenerationResult = { _, _, _ in .retryable },
                             sendMetadata: @escaping @Sendable (CorpusMetadataAttachment) async -> ContributionSendResult = { _ in .accepted },
                             hasConsent: @escaping @Sendable () -> Bool = { true },
                             now: @escaping @Sendable () -> Date = { Date() },
                             scheduledSleep: @escaping @Sendable (TimeInterval) async throws -> Void = { _ in throw CancellationError() }) -> TranscriptContributionManager {
        let defaultAudioURL = audioURL
        let resolveAudioFileURL = audioFileURL ?? { _ in defaultAudioURL }
        let generateFingerprint = fingerprint ?? { _ in
            recorder.fingerprintCalls.withLock { $0 += 1 }
            return fingerprintData
        }
        let scriptedResults = Mutex(resultScript ?? [result])
        let nextResult: @Sendable () -> ContributionSendResult = {
            scriptedResults.withLock { results in
                if results.count > 1 {
                    return results.removeFirst()
                }
                return results.first ?? result
            }
        }
        return TranscriptContributionManager(
            dataManager: dataManager,
            artifactStore: artifactStore,
            audioFileURL: resolveAudioFileURL,
            fingerprint: generateFingerprint,
            gzip: { $0 }, // Identity: payload bytes are asserted against the inputs.
            sendContribution: { payload in
                recorder.contributions.withLock { $0.append(payload) }
                return nextResult()
            },
            sendSighting: { payload in
                recorder.sightings.withLock { $0.append(payload) }
                return nextResult()
            },
            generateMetadata: generateMetadata,
            sendMetadata: sendMetadata,
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
            now: now,
            sleep: { delay in
                recorder.wakeDelays.withLock { $0.append(delay) }
                try await scheduledSleep(delay)
            },
            hasConsent: hasConsent
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

    /// A pending metadata row (accepted contribution awaiting on-device
    /// generation + one-time token attachment), optionally with its VTT artifact.
    @discardableResult
    private func seedMetadata(episodeUuid: String = "ep-1",
                              podcastUuid: String = "pod-1",
                              payloadJson: String? = nil,
                              withArtifact: Bool = true,
                              attempts: Int32 = 0) throws -> Int64 {
        if withArtifact {
            try Self.vttBody.write(to: artifactStore.fileURL(forEpisodeUuid: episodeUuid), atomically: true, encoding: .utf8)
        }
        var row = PendingTranscriptUploadRecord()
        row.episodeUuid = episodeUuid
        row.podcastUuid = podcastUuid
        row.uploadKind = .metadata
        if let payloadJson {
            row.payloadJson = payloadJson
        } else {
            let info = TranscriptContributionManager.MetadataInfo(candidateID: "cand-1", attachmentToken: "token-1")
            row.payloadJson = try String(decoding: JSONEncoder().encode(info), as: UTF8.self)
        }
        row.attempts = attempts
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

    func testRetryDeadlineAutomaticallyWakesAndDrainsQueue() async throws {
        try seedContribution()
        let recorder = Recorder()
        let clock = Mutex(Date(timeIntervalSince1970: 1_700_000_000))
        let manager = makeManager(
            recorder: recorder,
            result: .accepted,
            resultScript: [.retryAfter(1), .accepted],
            now: { clock.withLock { $0 } },
            scheduledSleep: { delay in
                clock.withLock { $0.addTimeInterval(delay) }
            }
        )

        await drain(manager)
        try await waitUntil("scheduled retry drains the row") {
            recorder.sendCount == 2 && self.dataManager.pendingTranscriptUploads.count() == 0
        }

        XCTAssertEqual(recorder.wakeDelays.withLock { $0.first }, 60,
                       "Attempt one uses the 60-second exponential-backoff floor")
    }

    func testKickRearmsPersistedRetryDeadline() async throws {
        let rowId = try seedContribution()
        let currentDate = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(dataManager.pendingTranscriptUploads.setRetryState(id: rowId,
                                                                         attempts: 1,
                                                                         nextAttemptAt: currentDate.addingTimeInterval(120)))
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder,
                                  result: .accepted,
                                  now: { currentDate })

        await drain(manager)

        let wakeDelay = try XCTUnwrap(recorder.wakeDelays.withLock { $0.first })
        XCTAssertEqual(wakeDelay, 120, accuracy: 0.001)
        XCTAssertEqual(recorder.sendCount, 0, "A persisted retry must remain unsent until its deadline")
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
        let wakeDelay = try XCTUnwrap(recorder.wakeDelays.withLock { $0.first })
        XCTAssertEqual(wakeDelay, 3600, accuracy: 0.1,
                       "A server pause must arm an automatic queue wake-up")

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

    func testMissingAudioSendsContributionWithoutOptionalFingerprint() async throws {
        try seedContribution()
        let recorder = Recorder()
        let manager = makeManager(
            recorder: recorder,
            result: .accepted,
            audioFileURL: { _ in nil }
        )

        await drain(manager)

        let payload = try XCTUnwrap(recorder.contributions.withLock { $0.first })
        XCTAssertTrue(payload.gzippedFingerprint.isEmpty)
        XCTAssertEqual(recorder.fingerprintCalls.withLock { $0 }, 0)
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0)
    }

    func testFingerprintGenerationFailureSendsContributionWithoutFingerprint() async throws {
        try seedContribution()
        let recorder = Recorder()
        let manager = makeManager(
            recorder: recorder,
            result: .accepted,
            fingerprint: { _ in
                recorder.fingerprintCalls.withLock { $0 += 1 }
                throw CocoaError(.fileReadCorruptFile)
            }
        )

        await drain(manager)

        let payload = try XCTUnwrap(recorder.contributions.withLock { $0.first })
        XCTAssertTrue(payload.gzippedFingerprint.isEmpty)
        XCTAssertEqual(recorder.fingerprintCalls.withLock { $0 }, 1)
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0)
    }

    // MARK: - Power gate

    func testPowerDeferredStopsDrainWithoutSending() async throws {
        try seedContribution()
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .accepted, powerDeferred: true)

        await drain(manager)

        XCTAssertEqual(recorder.sendCount, 0, "Contribution fingerprinting obeys the transcription battery policy")
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 1)
    }

    func testPowerDeferredContributionDoesNotBlockSightings() async throws {
        try seedContribution(episodeUuid: "ep-contribution")
        try seedSighting(episodeUuid: "ep-sighting")
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .accepted, powerDeferred: true)

        await drain(manager)

        XCTAssertEqual(recorder.contributions.withLock { $0.count }, 0)
        XCTAssertEqual(recorder.sightings.withLock { $0.count }, 1,
                       "Network-only sightings must drain without battery monitoring")
        let remaining = dataManager.pendingTranscriptUploads.allRecords()
        XCTAssertEqual(remaining.map(\.uploadKind), [.contribution])
    }

    // MARK: - Metadata jobs

    func testAcceptedContributionTransitionsToMetadataAndCompletesInOneDrain() async throws {
        try seedContribution()
        let receipt = TranscriptContributionReceipt(candidateID: "cand-1", sha256: "sha-1", attachmentToken: "token-1")
        let recorder = Recorder()
        let generated = Mutex<[String]>([])
        let attached = Mutex<[CorpusMetadataAttachment]>([])
        let manager = makeManager(
            recorder: recorder,
            result: .acceptedContribution(receipt),
            generateMetadata: { episodeUuid, _, info in
                generated.withLock { $0.append(episodeUuid) }
                return .generated(CorpusMetadataAttachment(candidateID: info.candidateID,
                                                           attachmentToken: info.attachmentToken,
                                                           summary: "summary",
                                                           chapters: []))
            },
            sendMetadata: { metadata in
                attached.withLock { $0.append(metadata) }
                return .accepted
            }
        )

        await drain(manager)

        // The transition resets attempts 0 → 0 on the same rowId; only the kind
        // changes, which the stall guard must count as progress so the metadata
        // job runs in the SAME drain pass instead of being deferred.
        XCTAssertEqual(recorder.contributions.withLock { $0.count }, 1)
        XCTAssertEqual(generated.withLock { $0 }, ["ep-1"])
        XCTAssertEqual(attached.withLock { $0.first?.candidateId }, "cand-1")
        XCTAssertEqual(attached.withLock { $0.first?.attachmentToken }, "token-1")
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0)
        XCTAssertNil(artifactStore.readFingerprint(episodeUuid: "ep-1"))
    }

    func testReceiptOnSightingRowCleansUpInsteadOfRetrying() async throws {
        try seedSighting()
        let receipt = TranscriptContributionReceipt(candidateID: "cand-9", sha256: "sha-9", attachmentToken: "token-9")
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .acceptedContribution(receipt))

        await drain(manager)

        XCTAssertEqual(recorder.sightings.withLock { $0.count }, 1)
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0,
                       "An accepted-but-untransitionable row is success-with-cleanup; retrying would re-upload an accepted payload")
    }

    func testMetadataPermanentSendFailureDeletesRow() async throws {
        try seedMetadata()
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder,
                                  result: .accepted,
                                  generateMetadata: { _, _, info in
                                      .generated(CorpusMetadataAttachment(candidateID: info.candidateID,
                                                                          attachmentToken: info.attachmentToken,
                                                                          summary: "summary",
                                                                          chapters: []))
                                  },
                                  sendMetadata: { _ in .permanentFailure("attachment token consumed") })

        await drain(manager)

        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0,
                       "A consumed one-time token can never succeed; the row must not retry weekly forever")
    }

    func testMetadataTransientSendFailureRetainsRowOnWeeklyCadence() async throws {
        try seedMetadata()
        let recorder = Recorder()
        let before = Date()
        let manager = makeManager(recorder: recorder,
                                  result: .accepted,
                                  generateMetadata: { _, _, info in
                                      .generated(CorpusMetadataAttachment(candidateID: info.candidateID,
                                                                          attachmentToken: info.attachmentToken,
                                                                          summary: "summary",
                                                                          chapters: []))
                                  },
                                  sendMetadata: { _ in .retryAfter(60) })

        await drain(manager)

        let row = try XCTUnwrap(dataManager.pendingTranscriptUploads.allRecords().first)
        XCTAssertEqual(row.attempts, 1)
        let nextAttemptAt = try XCTUnwrap(row.nextAttemptAt)
        XCTAssertEqual(nextAttemptAt,
                       before.timeIntervalSince1970 + TranscriptContributionManager.metadataRetryInterval,
                       accuracy: 10)
    }

    func testMetadataGenerationFailureGivesUpAtAttemptCap() async throws {
        try seedMetadata(attempts: TranscriptContributionManager.maxMetadataAttempts - 1)
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .accepted) // Generation remains retryable until the cap.

        await drain(manager)

        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0,
                       "Out-of-contract generation output must not re-run the map/reduce weekly forever")
    }

    func testPermanentMetadataGenerationFailureDeletesImmediately() async throws {
        try seedMetadata()
        let recorder = Recorder()
        let manager = makeManager(
            recorder: recorder,
            result: .accepted,
            generateMetadata: { _, _, _ in .permanentFailure("invalid transcript") }
        )

        await drain(manager)

        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0)
    }

    func testRevokedConsentPurgesPendingExportsWithoutSending() async throws {
        try seedContribution()
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .accepted, hasConsent: { false })

        await drain(manager)

        XCTAssertEqual(recorder.sendCount, 0)
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0)
    }

    func testMetadataMissingArtifactDeletesRowWithoutGenerating() async throws {
        try seedMetadata(withArtifact: false)
        let generated = Mutex(false)
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder,
                                  result: .accepted,
                                  generateMetadata: { _, _, _ in
                                      generated.withLock { $0 = true }
                                      return .retryable
                                  })

        await drain(manager)

        XCTAssertFalse(generated.withLock { $0 }, "A deleted VTT artifact leaves nothing to generate from")
        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0)
    }

    func testUndecodableMetadataPayloadIsDeleted() async throws {
        try seedMetadata(payloadJson: "not json")
        let recorder = Recorder()
        let manager = makeManager(recorder: recorder, result: .accepted)

        await drain(manager)

        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0,
                       "An undecodable metadata payload must not sit due-immediately at the queue head forever")
    }

    func testTransitionToMetadataOnlyTransitionsContributionRows() throws {
        let sightingId = try seedSighting()
        XCTAssertFalse(dataManager.pendingTranscriptUploads.transitionToMetadata(id: sightingId, payloadJson: "{}"),
                       "A non-contribution row must not be transitioned")
        XCTAssertEqual(dataManager.pendingTranscriptUploads.allRecords().first?.uploadKind, .sighting)

        try seedContribution(episodeUuid: "ep-c")
        let contributionId = try XCTUnwrap(dataManager.pendingTranscriptUploads.allRecords()
            .first { $0.uploadKind == .contribution }?.id)
        XCTAssertTrue(dataManager.pendingTranscriptUploads.setRetryState(id: contributionId,
                                                                         attempts: 3,
                                                                         nextAttemptAt: Date(timeIntervalSinceNow: 60)))
        XCTAssertTrue(dataManager.pendingTranscriptUploads.transitionToMetadata(id: contributionId,
                                                                                payloadJson: #"{"candidateID":"c","attachmentToken":"t"}"#))
        let row = try XCTUnwrap(dataManager.pendingTranscriptUploads.allRecords().first { $0.id == contributionId })
        XCTAssertEqual(row.uploadKind, .metadata)
        XCTAssertEqual(row.attempts, 0)
        XCTAssertNil(row.nextAttemptAt)

        XCTAssertFalse(dataManager.pendingTranscriptUploads.transitionToMetadata(id: 9_999, payloadJson: "{}"),
                       "Zero updated rows must not report success")
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

    private func waitUntil(_ description: String,
                           timeout: TimeInterval = 2,
                           condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting until \(description)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Sighting enqueue

    private func insertEligibilityFixture(episodeUuid: String, podcastUuid: String) {
        var podcast = Podcast()
        podcast.uuid = podcastUuid
        podcast.addedDate = Date()
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
                                                       hasConsent: true,
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
                                                   hasConsent: true,
                                                   kickAfterInsert: false)

        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0)
    }

    func testNoteSightingRequiresContributionConsent() {
        insertEligibilityFixture(episodeUuid: "ep-s", podcastUuid: "pod-s")

        TranscriptContributionManager.noteSighting(
            episodeUuid: "ep-s",
            podcastUuid: "pod-s",
            transcriptUrl: "https://example.com/t.vtt",
            format: "text/vtt",
            language: nil,
            dataManager: dataManager,
            hasConsent: false,
            kickAfterInsert: false
        )

        XCTAssertEqual(dataManager.pendingTranscriptUploads.count(), 0)
    }
}
