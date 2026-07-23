import XCTest
@testable import PocketCastsDataModel
@testable import PocketCastsUtils
@testable import podcasts

final class TranscriptManagerTests: XCTestCase {

    class MockShowCoordinator: ShowInfoCoordinating {
        func loadShowNotes(podcastUuid: String, episodeUuid: String) async throws -> String {
            return ""
        }

        func loadEpisodeArtworkUrl(podcastUuid: String, episodeUuid: String) async throws -> URL? {
            return nil
        }

        func loadChapters(podcastUuid: String, episodeUuid: String) async throws -> (metadata: [Episode.Metadata.EpisodeChapter]?, podcastIndex: [podcasts.PodcastIndexChapter]?, generated: [GeneratedChapter]?) {
            return (metadata: nil, podcastIndex: nil, generated: nil)
        }

        func loadTranscriptsMetadata(podcastUuid: String, episodeUuid: String) async throws -> EpisodeTranscriptData {
            guard let transcriptURL = Bundle(for: Self.self).url(forResource: "sample", withExtension: "vtt") else {
                return (transcripts: [], hasGeneratedTranscripts: false, isDisplayingGeneratedTranscript: false)
            }
            let transcript = Episode.Metadata.Transcript(url: transcriptURL.absoluteString, type: "text/vtt", language: nil)
            return (transcripts: [transcript], hasGeneratedTranscripts: false, isDisplayingGeneratedTranscript: false)
        }

        func loadEpisodeSummary(podcastUuid: String, episodeUuid: String) async throws -> String? {
            nil
        }
    }

    class GeneratedMockShowCoordinator: MockShowCoordinator {
        override func loadTranscriptsMetadata(podcastUuid: String, episodeUuid: String) async throws -> EpisodeTranscriptData {
            guard let transcriptURL = Bundle(for: Self.self).url(forResource: "sample", withExtension: "vtt") else {
                return (transcripts: [], hasGeneratedTranscripts: true, isDisplayingGeneratedTranscript: true)
            }
            let transcript = Episode.Metadata.Transcript(url: transcriptURL.absoluteString, type: "text/vtt", language: nil)
            return (transcripts: [transcript], hasGeneratedTranscripts: true, isDisplayingGeneratedTranscript: true)
        }
    }

    class EmptyMockShowCoordinator: MockShowCoordinator {
        override func loadTranscriptsMetadata(podcastUuid: String, episodeUuid: String) async throws -> EpisodeTranscriptData {
            guard let transcriptURL = Bundle(for: Self.self).url(forResource: "empty_sample", withExtension: "vtt") else {
                return (transcripts: [], hasGeneratedTranscripts: false, isDisplayingGeneratedTranscript: false)
            }
            let transcript = Episode.Metadata.Transcript(url: transcriptURL.absoluteString, type: "text/vtt", language: nil)
            return (transcripts: [transcript], hasGeneratedTranscripts: false, isDisplayingGeneratedTranscript: false)
        }
    }

    func testLoadingTranscript() async throws {
        let mockShowCoordinator = MockShowCoordinator()
        let manager = TranscriptManager(episodeUUID: UUID().uuidString, podcastUUID: UUID().uuidString, showCoordinator: mockShowCoordinator)

        let model = try await manager.loadTranscript()

        XCTAssertFalse(model.cues.isEmpty)
        XCTAssertEqual(model.cues.count, 13)
    }

    func testIsDisplayingGeneratedTranscriptPropagatesTrue() async throws {
        let manager = TranscriptManager(episodeUUID: UUID().uuidString, podcastUUID: UUID().uuidString, showCoordinator: GeneratedMockShowCoordinator())
        _ = try await manager.loadTranscript()
        XCTAssertTrue(manager.isDisplayingGeneratedTranscript)
        XCTAssertTrue(manager.hasGeneratedTranscripts)
    }

    func testIsDisplayingGeneratedTranscriptPropagatesFalse() async throws {
        let manager = TranscriptManager(episodeUUID: UUID().uuidString, podcastUUID: UUID().uuidString, showCoordinator: MockShowCoordinator())
        _ = try await manager.loadTranscript()
        XCTAssertFalse(manager.isDisplayingGeneratedTranscript)
        XCTAssertFalse(manager.hasGeneratedTranscripts)
    }

    func testEmptyLoadingTranscript() async {
        let mockShowCoordinator = EmptyMockShowCoordinator()
        let manager = TranscriptManager(episodeUUID: UUID().uuidString, podcastUUID: UUID().uuidString, showCoordinator: mockShowCoordinator)

        do {
            _ = try await manager.loadTranscript()
        } catch {
            XCTAssertTrue(error is TranscriptError)
        }
    }

    /// A restore brings back the transcription record but not the VTT artifact
    /// (the artifact directory is excluded from backups). The phantom completed
    /// record must be dropped so Generate is offered again, and the load must
    /// fall through to the podcast-provided transcript.
    func testCompletedRecordWithoutArtifactSelfHeals() async throws {
        let store = FeatureFlagOverrideStore()
        defer { store.resetOverrides() }
        try store.override(FeatureFlag.diarizedTranscription, withValue: true)

        let episodeUuid = UUID().uuidString
        var record = EpisodeTranscriptionRecord()
        record.episodeUuid = episodeUuid
        record.transcriptionStatus = .completed
        record.createdAt = Date().timeIntervalSince1970
        DataManager.sharedManager.transcriptions.upsert(record)
        defer { DataManager.sharedManager.transcriptions.delete(episodeUuid: episodeUuid) }

        let manager = TranscriptManager(episodeUUID: episodeUuid, podcastUUID: UUID().uuidString, showCoordinator: MockShowCoordinator())
        let model = try await manager.loadTranscript()

        XCTAssertFalse(model.cues.isEmpty, "Load should fall through to the podcast-provided transcript")
        XCTAssertFalse(manager.hasLocalTranscription)
        XCTAssertFalse(manager.isDisplayingLocalTranscription)
        XCTAssertNil(DataManager.sharedManager.transcriptions.find(episodeUuid: episodeUuid),
                     "The phantom completed record should have been deleted")
    }

    /// A completed record whose artifact file exists but cannot be parsed must
    /// self-heal exactly like a missing artifact so corrupt content cannot hide
    /// the Generate affordance forever.
    func testCompletedRecordWithCorruptArtifactSelfHeals() async throws {
        let store = FeatureFlagOverrideStore()
        defer { store.resetOverrides() }
        try store.override(FeatureFlag.diarizedTranscription, withValue: true)

        let episodeUuid = UUID().uuidString
        let artifactStore = TranscriptionArtifactStore()
        try FileManager.default.createDirectory(at: TranscriptionArtifactStore.defaultDirectoryURL, withIntermediateDirectories: true)
        let artifactURL = artifactStore.fileURL(forEpisodeUuid: episodeUuid)
        try "definitely not parseable WebVTT content".write(to: artifactURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: artifactURL) }

        var record = EpisodeTranscriptionRecord()
        record.episodeUuid = episodeUuid
        record.transcriptionStatus = .completed
        record.filePath = artifactURL.path
        record.createdAt = Date().timeIntervalSince1970
        DataManager.sharedManager.transcriptions.upsert(record)
        defer { DataManager.sharedManager.transcriptions.delete(episodeUuid: episodeUuid) }

        let manager = TranscriptManager(episodeUUID: episodeUuid, podcastUUID: UUID().uuidString, showCoordinator: MockShowCoordinator())
        let model = try await manager.loadTranscript()

        XCTAssertFalse(model.cues.isEmpty, "Load should fall through to the podcast-provided transcript")
        XCTAssertFalse(manager.hasLocalTranscription)
        XCTAssertFalse(manager.isDisplayingLocalTranscription)
        XCTAssertNil(DataManager.sharedManager.transcriptions.find(episodeUuid: episodeUuid),
                     "The corrupt-artifact record should have been deleted")
        XCTAssertFalse(artifactStore.hasUsableArtifact(episodeUuid: episodeUuid),
                       "The corrupt artifact file should have been deleted so a fresh Generate starts clean")
    }

    func testArtifactUsabilityRejectsMissingEmptyCorruptAndDirectoryPaths() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-artifact-tests-\(UUID().uuidString)", isDirectory: true)
        let store = TranscriptionArtifactStore(directoryURL: directory)
        let episodeUuid = "episode"
        let artifactURL = store.fileURL(forEpisodeUuid: episodeUuid)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertFalse(store.hasUsableArtifact(episodeUuid: episodeUuid))

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: artifactURL)
        XCTAssertFalse(store.hasUsableArtifact(episodeUuid: episodeUuid))

        try "not WebVTT".write(to: artifactURL, atomically: true, encoding: .utf8)
        XCTAssertFalse(store.hasUsableArtifact(episodeUuid: episodeUuid))

        try FileManager.default.removeItem(at: artifactURL)
        try FileManager.default.createDirectory(at: artifactURL, withIntermediateDirectories: false)
        XCTAssertFalse(store.hasUsableArtifact(episodeUuid: episodeUuid))

        try FileManager.default.removeItem(at: artifactURL)
        try "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nUsable\n"
            .write(to: artifactURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(store.hasUsableArtifact(episodeUuid: episodeUuid))
    }
}

@MainActor
final class TranscriptLoadTaskTests: XCTestCase {
    func testSupersededLoadCannotPublishAfterNewerLoad() async {
        let loadTask = TranscriptLoadTask()
        let recorder = TranscriptLoadPublicationRecorder()
        let firstGate = TranscriptLoadGate()
        let firstStarted = TranscriptLoadSignal()
        let firstAttemptedPublication = TranscriptLoadSignal()
        let secondPublished = TranscriptLoadSignal()

        loadTask.start { [weak loadTask] generation in
            await firstStarted.signal()
            await firstGate.wait()
            await MainActor.run {
                loadTask?.finishIfCurrent(generation) {
                    recorder.values.append("first")
                }
            }
            await firstAttemptedPublication.signal()
        }
        await firstStarted.wait()

        loadTask.start { [weak loadTask] generation in
            await MainActor.run {
                loadTask?.finishIfCurrent(generation) {
                    recorder.values.append("second")
                }
            }
            await secondPublished.signal()
        }
        await secondPublished.wait()

        await firstGate.open()
        await firstAttemptedPublication.wait()

        XCTAssertEqual(recorder.values, ["second"])
    }

    func testCancellationSuppressesLoadThatIgnoresCancellation() async {
        let loadTask = TranscriptLoadTask()
        let recorder = TranscriptLoadPublicationRecorder()
        let gate = TranscriptLoadGate()
        let started = TranscriptLoadSignal()
        let attemptedPublication = TranscriptLoadSignal()

        loadTask.start { [weak loadTask] generation in
            await started.signal()
            await gate.wait()
            let wasCancelled = Task.isCancelled
            await MainActor.run {
                recorder.observedCancellation = wasCancelled
                loadTask?.finishIfCurrent(generation) {
                    recorder.values.append("cancelled")
                }
            }
            await attemptedPublication.signal()
        }
        await started.wait()

        loadTask.cancel()
        await gate.open()
        await attemptedPublication.wait()

        XCTAssertTrue(recorder.observedCancellation)
        XCTAssertTrue(recorder.values.isEmpty)
    }

    func testTaskOwnerDeallocatesWhileLoadIsSuspended() async {
        var loadTask: TranscriptLoadTask? = TranscriptLoadTask()
        weak let weakLoadTask = loadTask
        let recorder = TranscriptLoadPublicationRecorder()
        let gate = TranscriptLoadGate()
        let started = TranscriptLoadSignal()
        let operationFinished = TranscriptLoadSignal()

        loadTask?.start { [weak loadTask] generation in
            await started.signal()
            await gate.wait()
            let wasCancelled = Task.isCancelled
            await MainActor.run {
                recorder.observedCancellation = wasCancelled
                loadTask?.finishIfCurrent(generation) {
                    recorder.values.append("deallocated")
                }
            }
            await operationFinished.signal()
        }
        await started.wait()

        loadTask = nil
        XCTAssertNil(weakLoadTask, "The task closure must not retain its owner")

        await gate.open()
        await operationFinished.wait()

        XCTAssertTrue(recorder.observedCancellation)
        XCTAssertTrue(recorder.values.isEmpty)
    }
}

@MainActor
private final class TranscriptLoadPublicationRecorder {
    var values: [String] = []
    var observedCancellation = false
}

/// A deliberately non-cooperative suspension point used to prove that generation
/// invalidation suppresses publication even when cancellation cannot stop work.
private actor TranscriptLoadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

/// A sticky one-shot signal: signaling before the waiter arrives is supported,
/// which keeps scheduling order from making these concurrency tests flaky.
private actor TranscriptLoadSignal {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isSignaled = false

    func wait() async {
        if isSignaled { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func signal() {
        isSignaled = true
        continuation?.resume()
        continuation = nil
    }
}
