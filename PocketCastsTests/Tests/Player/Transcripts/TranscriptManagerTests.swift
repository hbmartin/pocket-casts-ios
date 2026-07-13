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
}
