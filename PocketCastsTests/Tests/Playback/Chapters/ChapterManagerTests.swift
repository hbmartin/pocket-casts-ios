import Synchronization
import XCTest

@testable import podcasts
@testable import PocketCastsDataModel
@testable import PocketCastsServer
@testable import PocketCastsUtils
import CoreMedia

@MainActor
class ChapterManagerTests: XCTestCase {
    let featureFlagMock = FeatureFlagMock()
    var previousSubscriptionPaidStatus: Int!

    override func setUp() {
    }

    override func tearDown() async throws {
        featureFlagMock.reset()
    }

    func testCachedOnDeviceChaptersSkipTranscriptAndCueLoading() async {
        featureFlagMock.set(.onDeviceChapters, value: true)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chapter-manager-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OnDeviceChapterStore(directoryURL: directory)
        let episode = makeEpisodeMock()
        episode.uuid = "cached-episode"
        store.save(.chapters([
            GeneratedChapter(title: "Intro", timestamp: "0:00", startTime: 0),
            GeneratedChapter(title: "Topic", timestamp: "2:00", startTime: 120)
        ]), episodeUuid: episode.uuid)
        let transcriptLoads = Mutex(0)
        let manager = ChapterManager(
            chapterParser: PodcastChapterParserMock(),
            showInfoCoordinator: ShowInfoCoordinatorMock(),
            onDeviceChapterStore: store,
            localTranscriptCuesLoader: { _, _ in
                transcriptLoads.withLock { $0 += 1 }
                return []
            }
        )

        await manager.parseChapters(episode: episode, duration: 300)

        XCTAssertEqual(transcriptLoads.withLock { $0 }, 0)
        XCTAssertEqual(manager.visibleChapterCount(), 2)
        XCTAssertEqual(manager.chaptersOrigin.analyticsDescription, "generated")
    }

    func testCachedNoChaptersSkipsTranscriptAndCueLoading() async {
        featureFlagMock.set(.onDeviceChapters, value: true)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chapter-manager-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OnDeviceChapterStore(directoryURL: directory)
        let episode = makeEpisodeMock()
        episode.uuid = "no-chapters-episode"
        store.save(.noChapters, episodeUuid: episode.uuid)
        let transcriptLoads = Mutex(0)
        let manager = ChapterManager(
            chapterParser: PodcastChapterParserMock(),
            showInfoCoordinator: ShowInfoCoordinatorMock(),
            onDeviceChapterStore: store,
            localTranscriptCuesLoader: { _, _ in
                transcriptLoads.withLock { $0 += 1 }
                return []
            }
        )

        await manager.parseChapters(episode: episode, duration: 300)

        XCTAssertEqual(transcriptLoads.withLock { $0 }, 0)
        XCTAssertEqual(manager.visibleChapterCount(), 0)
        XCTAssertEqual(manager.chaptersOrigin.analyticsDescription, "unknown")
    }

    /// Update the current chapter given a TimeInterval
    func testUpdateCurrentChapterBasedOnTime() async {
        let parserMock = PodcastChapterParserMock()
        let showInfoCoordinatorMock = ShowInfoCoordinatorMock()
        parserMock.chapters = [
            chapterInfo(startTime: 0, duration: 100, shouldPlay: true),
            chapterInfo(startTime: 101, duration: 200, shouldPlay: false),
            chapterInfo(startTime: 201, duration: 300, shouldPlay: true),
            chapterInfo(startTime: 301, duration: 400, shouldPlay: false),
            chapterInfo(startTime: 401, duration: 500, shouldPlay: true),
            chapterInfo(startTime: 501, duration: 600, shouldPlay: false)
        ]
        let chapterManager = ChapterManager(chapterParser: parserMock, showInfoCoordinator: showInfoCoordinatorMock)
        await chapterManager.parseChapters(episode: makeEpisodeMock(), duration: 600)

        chapterManager.updateCurrentChapter(time: 10)

        XCTAssertEqual(chapterManager.currentChapters.visibleChapter, chapterInfo(startTime: 0, duration: 100, shouldPlay: true))
    }

    /// Update the current chapter given a TimeInterval
    func testReturnNextVisiblePlayableChapter() async {
        let showInfoCoordinatorMock = ShowInfoCoordinatorMock()
        let parserMock = PodcastChapterParserMock()
        parserMock.chapters = [
            chapterInfo(startTime: 0, duration: 100, shouldPlay: true),
            chapterInfo(startTime: 101, duration: 200, shouldPlay: false),
            chapterInfo(startTime: 201, duration: 300, shouldPlay: true),
            chapterInfo(startTime: 301, duration: 400, shouldPlay: false),
            chapterInfo(startTime: 401, duration: 500, shouldPlay: true),
            chapterInfo(startTime: 501, duration: 600, shouldPlay: false)
        ]
        let chapterManager = ChapterManager(chapterParser: parserMock, showInfoCoordinator: showInfoCoordinatorMock)
        await chapterManager.parseChapters(episode: makeEpisodeMock(), duration: 600)
        chapterManager.updateCurrentChapter(time: 10)

        let nextVisiblePlayableChapter = chapterManager.nextVisiblePlayableChapter()

        XCTAssertEqual(nextVisiblePlayableChapter, chapterInfo(startTime: 201, duration: 300, shouldPlay: true))
    }

    /// Update the current chapter given a TimeInterval
    func testReturnPreviousVisiblePlayableChapter() async {
        let showInfoCoordinatorMock = ShowInfoCoordinatorMock()
        let parserMock = PodcastChapterParserMock()
        parserMock.chapters = [
            chapterInfo(startTime: 0, duration: 100, shouldPlay: true),
            chapterInfo(startTime: 101, duration: 200, shouldPlay: false),
            chapterInfo(startTime: 201, duration: 300, shouldPlay: true),
            chapterInfo(startTime: 301, duration: 400, shouldPlay: false),
            chapterInfo(startTime: 401, duration: 500, shouldPlay: true),
            chapterInfo(startTime: 501, duration: 600, shouldPlay: false)
        ]
        let chapterManager = ChapterManager(chapterParser: parserMock, showInfoCoordinator: showInfoCoordinatorMock)
        await chapterManager.parseChapters(episode: makeEpisodeMock(), duration: 600)
        chapterManager.updateCurrentChapter(time: 450)

        let nextVisiblePlayableChapter = chapterManager.previousVisibleChapter()

        XCTAssertEqual(nextVisiblePlayableChapter, chapterInfo(startTime: 201, duration: 300, shouldPlay: true))
    }

    func chapterInfo(startTime: TimeInterval, duration: TimeInterval, shouldPlay: Bool) -> ChapterInfo {
        let chapterInfo = ChapterInfo()
        chapterInfo.shouldPlay = shouldPlay
        chapterInfo.startTime = CMTime(seconds: startTime, preferredTimescale: .max)
        chapterInfo.duration = duration
        return chapterInfo
    }
}

// @unchecked Sendable: subclass restating PodcastChapterParser's conformance; chapters is set before use on the test thread.
class PodcastChapterParserMock: PodcastChapterParser, @unchecked Sendable {
    var chapters: [ChapterInfo] = []

    override func parseRemoteFile(_ remoteUrl: String, episodeDuration: TimeInterval, completion: @escaping (([ChapterInfo]) -> Void)) {
        completion(chapters)
    }

    override func parseRemoteFile(_ remoteUrl: String, episodeDuration: TimeInterval) async -> [ChapterInfo] {
        chapters
    }
}

private class ShowInfoCoordinatorMock: ShowInfoCoordinating {
    func loadShowNotes(podcastUuid: String, episodeUuid: String) async throws -> String {
        ""
    }

    func loadEpisodeArtworkUrl(podcastUuid: String, episodeUuid: String) async throws -> URL? {
        nil
    }

    func loadChapters(podcastUuid: String, episodeUuid: String) async throws -> (metadata: [PocketCastsDataModel.Episode.Metadata.EpisodeChapter]?, podcastIndex: [podcasts.PodcastIndexChapter]?, generated: [GeneratedChapter]?) {
        (metadata: nil, podcastIndex: nil, generated: nil)
    }

    func loadTranscriptsMetadata(podcastUuid: String, episodeUuid: String) async throws -> EpisodeTranscriptData {
        return (transcripts: [], hasGeneratedTranscripts: false, isDisplayingGeneratedTranscript: false)
    }

    func loadEpisodeSummary(podcastUuid: String, episodeUuid: String) async throws -> String? {
        nil
    }
}

private func makeEpisodeMock() -> Episode {
    var episode = Episode()
    episode.downloadUrl = "https://example.com/episode.mp3"
    return episode
}
