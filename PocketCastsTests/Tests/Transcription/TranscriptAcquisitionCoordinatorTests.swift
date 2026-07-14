import Foundation
import GRDB
import PocketCastsTranscription
import PocketCastsUtils
import Synchronization
import XCTest

@testable import PocketCastsDataModel
@testable import podcasts

/// The download-triggered transcript acquisition: the pure decision matrix, and
/// the coordinator's provided-first flow against an isolated database with every
/// network/queue dependency injected.
final class TranscriptAcquisitionCoordinatorTests: XCTestCase {
    private var dataManager: DataManager!
    private var dbPool: DatabasePool!
    private var workDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-acquisition-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.busyMode = .timeout(10)
        dbPool = try DatabasePool(path: workDirectory.appendingPathComponent("test.sqlite3").path, configuration: configuration)
        dataManager = try DataManager(dbQueue: GRDBQueue(dbPool: dbPool))
    }

    override func tearDown() async throws {
        try? dbPool.close()
        try? FileManager.default.removeItem(at: workDirectory)
        try await super.tearDown()
    }

    // MARK: - Decision matrix (pure)

    private func decide(searchIndexingEnabled: Bool = true,
                        transcriptionEnabled: Bool = true,
                        hasProvidedTranscript: Bool = false,
                        alreadyIndexedProvided: Bool = false,
                        hasBlockingRecord: Bool = false) -> TranscriptAcquisitionDecision.Action {
        TranscriptAcquisitionDecision.action(searchIndexingEnabled: searchIndexingEnabled,
                                             transcriptionEnabled: transcriptionEnabled,
                                             hasProvidedTranscript: hasProvidedTranscript,
                                             alreadyIndexedProvided: alreadyIndexedProvided,
                                             hasBlockingRecord: hasBlockingRecord)
    }

    func testProvidedTranscriptWinsOverGeneration() {
        XCTAssertEqual(decide(hasProvidedTranscript: true), .indexProvided)
    }

    func testProvidedAlreadyIndexedDoesNothing() {
        XCTAssertEqual(decide(hasProvidedTranscript: true, alreadyIndexedProvided: true), .none)
    }

    func testProvidedTranscriptNeverTriggersGenerationEvenWhenIndexingIsOff() {
        // A provided transcript exists; generating a duplicate would be wasteful
        // even though we can't index the provided one right now.
        XCTAssertEqual(decide(searchIndexingEnabled: false, hasProvidedTranscript: true), .none)
    }

    func testNoProvidedTranscriptFallsBackToGeneration() {
        XCTAssertEqual(decide(), .enqueueTranscription)
    }

    func testExistingRecordBlocksGeneration() {
        // A blocking record — completed, failed or cancelled alike. Auto-run
        // never retries; another attempt is the user's call.
        XCTAssertEqual(decide(hasBlockingRecord: true), .none)
    }

    func testDisabledTranscriptionFlagBlocksGeneration() {
        XCTAssertEqual(decide(transcriptionEnabled: false), .none)
    }

    func testGenerationDoesNotRequireSearchIndexing() {
        XCTAssertEqual(decide(searchIndexingEnabled: false), .enqueueTranscription)
    }

    // MARK: - recordBlocks (pure)

    private func makeRecord(status: TranscriptionStatus, errorMessage: String? = nil) -> EpisodeTranscriptionRecord {
        var record = EpisodeTranscriptionRecord()
        record.episodeUuid = "ep-record"
        record.transcriptionStatus = status
        record.errorMessage = errorMessage
        return record
    }

    func testNilRecordDoesNotBlock() {
        XCTAssertFalse(TranscriptAcquisitionDecision.recordBlocks(nil))
    }

    func testFailedNotDownloadedRecordDoesNotBlock() {
        // The job never touched the audio (a streaming buffer's premature
        // EpisodeDownloaded raced the durable download) — the durable
        // download's own event may retry it.
        let record = makeRecord(status: .failed, errorMessage: TranscriptionError.notDownloaded.sanitizedDescription)
        XCTAssertFalse(TranscriptAcquisitionDecision.recordBlocks(record))
    }

    func testFailedForOtherReasonsBlocks() {
        let record = makeRecord(status: .failed, errorMessage: TranscriptionError.engineFailure.sanitizedDescription)
        XCTAssertTrue(TranscriptAcquisitionDecision.recordBlocks(record))
    }

    func testFailedWithoutErrorMessageBlocks() {
        XCTAssertTrue(TranscriptAcquisitionDecision.recordBlocks(makeRecord(status: .failed)))
    }

    func testCompletedRecordBlocks() {
        XCTAssertTrue(TranscriptAcquisitionDecision.recordBlocks(makeRecord(status: .completed)))
    }

    func testCancelledRecordBlocks() {
        XCTAssertTrue(TranscriptAcquisitionDecision.recordBlocks(makeRecord(status: .cancelled)))
    }

    func testQueuedRecordBlocks() {
        XCTAssertTrue(TranscriptAcquisitionDecision.recordBlocks(makeRecord(status: .queued)))
    }

    // MARK: - Coordinator flow

    private struct Fixture {
        let episodeUuid = "ep-acquire"
        let podcastUuid = "pod-acquire"
    }

    private static let vttBody = """
    WEBVTT

    00:00:00.000 --> 00:00:04.000
    Welcome back to the acquisition test everyone, glad you are here.

    00:00:04.000 --> 00:00:08.000
    Today we talk about download-triggered transcript indexing at length.
    """

    @discardableResult
    private func insertFixture(_ fixture: Fixture, status: DownloadStatus = .downloaded) -> Fixture {
        var podcast = Podcast()
        podcast.uuid = fixture.podcastUuid
        podcast.addedDate = Date()
        _ = dataManager.save(podcast: podcast)
        var episode = Episode()
        episode.uuid = fixture.episodeUuid
        episode.podcastUuid = fixture.podcastUuid
        episode.addedDate = Date()
        episode.episodeStatus = status.rawValue
        dataManager.save(episode: episode)
        return fixture
    }

    private func makeCoordinator(transcripts: [Episode.Metadata.Transcript],
                                 metadataError: Error? = nil,
                                 transcriptText: String? = TranscriptAcquisitionCoordinatorTests.vttBody,
                                 fetchError: Error? = nil,
                                 onEnqueue: @escaping @Sendable (String, String) -> Void = { _, _ in },
                                 onEnsureInfrastructure: @escaping @Sendable () -> Void = {}) -> TranscriptAcquisitionCoordinator {
        let dataManager: DataManager = dataManager
        return TranscriptAcquisitionCoordinator(
            dataManager: dataManager,
            loadTranscriptsMetadata: { _, _ in
                if let metadataError { throw metadataError }
                return transcripts
            },
            fetchTranscriptText: { _ in
                if let fetchError { throw fetchError }
                return transcriptText
            },
            indexProvided: { episodeUuid, podcastUuid, model in
                let cues = TranscriptSearchIndexer.indexableCues(from: model)
                guard !cues.isEmpty else { return false }
                return dataManager.transcriptSearch.replaceSegments(episodeUuid: episodeUuid, podcastUuid: podcastUuid, source: .provided, segments: cues)
            },
            enqueueTranscription: { episodeUuid, podcastUuid in
                onEnqueue(episodeUuid, podcastUuid)
            },
            ensureInfrastructure: {
                onEnsureInfrastructure()
            }
        )
    }

    private static let vttTranscript = Episode.Metadata.Transcript(url: "https://example.com/ep.vtt", type: "text/vtt", language: nil)

    func testProvidedTranscriptIsFetchedAndIndexed() async {
        let fixture = insertFixture(Fixture())
        let enqueued = Mutex<[String]>([])
        let coordinator = makeCoordinator(transcripts: [Self.vttTranscript],
                                          onEnqueue: { episodeUuid, _ in enqueued.withLock { $0.append(episodeUuid) } })

        await coordinator.evaluate(episodeUuid: fixture.episodeUuid)

        XCTAssertTrue(dataManager.transcriptSearch.isIndexed(episodeUuid: fixture.episodeUuid, source: .provided))
        XCTAssertEqual(dataManager.transcriptSearch.search(term: "acquisition").map(\.episodeUuid), [fixture.episodeUuid])
        XCTAssertEqual(enqueued.withLock { $0 }, [], "A usable provided transcript must not enqueue generation")
        XCTAssertNil(dataManager.transcriptions.find(episodeUuid: fixture.episodeUuid))
    }

    func testNoProvidedTranscriptEnqueuesGeneration() async {
        let fixture = insertFixture(Fixture())
        let enqueued = Mutex<[String]>([])
        let coordinator = makeCoordinator(transcripts: [],
                                          onEnqueue: { episodeUuid, _ in enqueued.withLock { $0.append(episodeUuid) } })

        await coordinator.evaluate(episodeUuid: fixture.episodeUuid)

        XCTAssertEqual(enqueued.withLock { $0 }, [fixture.episodeUuid])
        XCTAssertFalse(dataManager.transcriptSearch.isIndexed(episodeUuid: fixture.episodeUuid, source: .provided))
    }

    func testUnfetchableProvidedTranscriptFallsBackToGeneration() async {
        let fixture = insertFixture(Fixture())
        let enqueued = Mutex<[String]>([])
        let coordinator = makeCoordinator(transcripts: [Self.vttTranscript],
                                          fetchError: URLError(.timedOut),
                                          onEnqueue: { episodeUuid, _ in enqueued.withLock { $0.append(episodeUuid) } })

        await coordinator.evaluate(episodeUuid: fixture.episodeUuid)

        XCTAssertEqual(enqueued.withLock { $0 }, [fixture.episodeUuid],
                       "An unfetchable provided transcript is as good as absent")
    }

    func testMetadataFailureSkipsEntirely() async {
        let fixture = insertFixture(Fixture())
        let enqueued = Mutex<[String]>([])
        let coordinator = makeCoordinator(transcripts: [],
                                          metadataError: URLError(.notConnectedToInternet),
                                          onEnqueue: { episodeUuid, _ in enqueued.withLock { $0.append(episodeUuid) } })

        await coordinator.evaluate(episodeUuid: fixture.episodeUuid)

        XCTAssertEqual(enqueued.withLock { $0 }, [],
                       "Without show-info we must not guess — generating for a show that publishes transcripts wastes compute")
        XCTAssertFalse(dataManager.transcriptSearch.isIndexed(episodeUuid: fixture.episodeUuid, source: .provided))
    }

    func testExistingRecordBlocksEnqueue() async {
        let fixture = insertFixture(Fixture())
        var record = EpisodeTranscriptionRecord()
        record.episodeUuid = fixture.episodeUuid
        record.transcriptionStatus = .failed
        record.errorMessage = TranscriptionError.engineFailure.sanitizedDescription
        dataManager.transcriptions.upsert(record)

        let enqueued = Mutex<[String]>([])
        let coordinator = makeCoordinator(transcripts: [],
                                          onEnqueue: { episodeUuid, _ in enqueued.withLock { $0.append(episodeUuid) } })

        await coordinator.evaluate(episodeUuid: fixture.episodeUuid)

        XCTAssertEqual(enqueued.withLock { $0 }, [])
    }

    func testUnknownEpisodeDoesNothing() async {
        let enqueued = Mutex<[String]>([])
        let coordinator = makeCoordinator(transcripts: [],
                                          onEnqueue: { episodeUuid, _ in enqueued.withLock { $0.append(episodeUuid) } })

        await coordinator.evaluate(episodeUuid: "not-in-library")

        XCTAssertEqual(enqueued.withLock { $0 }, [])
    }

    func testStreamingBufferDownloadDoesNotAcquire() async {
        // DownloadManager posts EpisodeDownloaded for evictable streaming
        // buffers too; acquiring on those would enqueue a job that fails
        // `.notDownloaded` and used to block the real download's pass forever.
        let fixture = insertFixture(Fixture(), status: .downloadedForStreaming)
        let enqueued = Mutex<[String]>([])
        let coordinator = makeCoordinator(transcripts: [],
                                          onEnqueue: { episodeUuid, _ in enqueued.withLock { $0.append(episodeUuid) } })

        await coordinator.evaluate(episodeUuid: fixture.episodeUuid)

        XCTAssertEqual(enqueued.withLock { $0 }, [], "A streaming buffer must not trigger acquisition")
        XCTAssertFalse(dataManager.transcriptSearch.isIndexed(episodeUuid: fixture.episodeUuid, source: .provided))
        XCTAssertNil(dataManager.transcriptions.find(episodeUuid: fixture.episodeUuid))
    }

    func testFailedNotDownloadedRecordRetriesOnDurableDownload() async {
        let fixture = insertFixture(Fixture())
        var record = EpisodeTranscriptionRecord()
        record.episodeUuid = fixture.episodeUuid
        record.transcriptionStatus = .failed
        record.errorMessage = TranscriptionError.notDownloaded.sanitizedDescription
        dataManager.transcriptions.upsert(record)

        let enqueued = Mutex<[String]>([])
        let coordinator = makeCoordinator(transcripts: [],
                                          onEnqueue: { episodeUuid, _ in enqueued.withLock { $0.append(episodeUuid) } })

        await coordinator.evaluate(episodeUuid: fixture.episodeUuid)

        XCTAssertEqual(enqueued.withLock { $0 }, [fixture.episodeUuid],
                       "A notDownloaded failure never touched the audio; the durable download must retry it")
    }

    func testEvaluateEnsuresTranscriptionInfrastructure() async {
        // Enabling the Beta flag mid-session must lazily build the battery/
        // power/BG infrastructure the queue needs — launch-time setup was
        // skipped while the flag was off.
        let fixture = insertFixture(Fixture())
        let ensured = Mutex(0)
        let coordinator = makeCoordinator(transcripts: [],
                                          onEnsureInfrastructure: { ensured.withLock { $0 += 1 } })

        await coordinator.evaluate(episodeUuid: fixture.episodeUuid)

        XCTAssertEqual(ensured.withLock { $0 }, 1)
    }
}
