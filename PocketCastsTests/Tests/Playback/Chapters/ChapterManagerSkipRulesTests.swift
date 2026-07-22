import CoreMedia
import XCTest

@testable import podcasts
@testable import PocketCastsDataModel

/// Exercises the smart-skip rule application inside `ChapterManager.handleChaptersLoaded` using an
/// injected patterns provider (so no podcast row or settings lookup is needed).
@MainActor
final class ChapterManagerSkipRulesTests: XCTestCase {
    func testRuleMatchingChaptersAreDeselectedOnLoad() async {
        let (manager, parser) = makeManager(patterns: ["sponsor"])
        parser.chapters = [
            chapter(index: 0, title: "Intro"),
            chapter(index: 1, title: "Sponsor Break"),
            chapter(index: 2, title: "Main topic")
        ]

        await manager.parseChapters(episode: makeEpisode(), duration: 300)

        XCTAssertEqual(manager.chapterAt(index: 0)?.isPlayable(), true)
        XCTAssertEqual(manager.chapterAt(index: 1)?.isPlayable(), false)
        XCTAssertEqual(manager.chapterAt(index: 2)?.isPlayable(), true)
        XCTAssertTrue(manager.isRuleSkipped(chapterIndex: 1))
        XCTAssertFalse(manager.isRuleSkipped(chapterIndex: 0))
    }

    func testManualDeselectionsAreNotCountedAsRuleSkips() async {
        let (manager, parser) = makeManager(patterns: ["sponsor"])
        parser.chapters = [
            chapter(index: 0, title: "Sponsor Break"),
            chapter(index: 1, title: "Main topic")
        ]

        var episode = makeEpisode()
        episode.deselectedChapters = "0"
        await manager.parseChapters(episode: episode, duration: 200)

        XCTAssertEqual(manager.chapterAt(index: 0)?.isPlayable(), false)
        XCTAssertFalse(manager.isRuleSkipped(chapterIndex: 0), "a chapter the user deselected manually should not be attributed to a rule")
    }

    func testSessionReEnableSurvivesAChapterReload() async {
        let (manager, parser) = makeManager(patterns: ["sponsor"])
        let sponsorChapter = chapter(index: 1, title: "Sponsor Break")
        parser.chapters = [chapter(index: 0, title: "Intro"), sponsorChapter]
        let episode = makeEpisode()

        await manager.parseChapters(episode: episode, duration: 200)
        XCTAssertEqual(manager.chapterAt(index: 1)?.isPlayable(), false)

        // The user re-enables the rule-skipped chapter in the chapters UI
        sponsorChapter.shouldPlay = true
        manager.registerSessionReEnable(chapterIndex: 1, episodeUuid: episode.uuid)

        await manager.parseChapters(episode: episode, duration: 200)
        XCTAssertEqual(manager.chapterAt(index: 1)?.isPlayable(), true, "a session re-enable should stop the rule re-deselecting the chapter on reload")
        XCTAssertFalse(manager.isRuleSkipped(chapterIndex: 1))

        // The user deselects it again: the exception is dropped and the rule applies once more
        manager.unregisterSessionReEnable(chapterIndex: 1, episodeUuid: episode.uuid)
        await manager.parseChapters(episode: episode, duration: 200)
        XCTAssertEqual(manager.chapterAt(index: 1)?.isPlayable(), false)
        XCTAssertTrue(manager.isRuleSkipped(chapterIndex: 1))
    }

    func testNoPatternsLeavesChaptersUntouched() async {
        let (manager, parser) = makeManager(patterns: [])
        parser.chapters = [chapter(index: 0, title: "Sponsor Break")]

        await manager.parseChapters(episode: makeEpisode(), duration: 100)

        XCTAssertEqual(manager.chapterAt(index: 0)?.isPlayable(), true)
        XCTAssertFalse(manager.isRuleSkipped(chapterIndex: 0))
    }

    // MARK: - Current-chapter revalidation (review finding P2-6)

    func testParseCompletionRevalidatesTheCurrentChapterAfterRulesApply() async {
        // A rule-skipped chapter can already be playing when parsing finishes;
        // the manager must hand playback a revalidation pass — and only after
        // the skip rules have run, or the current chapter still looks playable.
        let parser = PodcastChapterParserMock()
        var revalidatedEpisodes = [String]()
        var manager: ChapterManager!
        manager = ChapterManager(
            chapterParser: parser,
            showInfoCoordinator: SkipRulesShowInfoCoordinatorMock(),
            skipPatternsProvider: { _ in ["sponsor"] },
            currentChapterRevalidator: { episode in
                revalidatedEpisodes.append(episode.uuid)
                XCTAssertEqual(manager.chapterAt(index: 0)?.isPlayable(), false,
                               "revalidation must run after skip rules are applied, or the skip is missed")
            })
        parser.chapters = [chapter(index: 0, title: "Sponsor Break"), chapter(index: 1, title: "Main topic")]
        let episode = makeEpisode()

        await manager.parseChapters(episode: episode, duration: 200)

        XCTAssertEqual(revalidatedEpisodes, [episode.uuid], "exactly one revalidation per parse, for the parsed episode")
    }

    // MARK: - Helpers

    private func makeManager(patterns: [String]) -> (ChapterManager, PodcastChapterParserMock) {
        let parser = PodcastChapterParserMock()
        let manager = ChapterManager(
            chapterParser: parser,
            showInfoCoordinator: SkipRulesShowInfoCoordinatorMock(),
            skipPatternsProvider: { _ in patterns })
        return (manager, parser)
    }

    private func chapter(index: Int, title: String) -> ChapterInfo {
        let chapter = ChapterInfo()
        chapter.index = index
        chapter.title = title
        chapter.startTime = CMTime(seconds: Double(index) * 100, preferredTimescale: .max)
        chapter.duration = 100
        return chapter
    }

    private func makeEpisode() -> Episode {
        var episode = Episode()
        episode.uuid = "chapter-skip-rules-test-episode"
        episode.downloadUrl = "https://example.com/episode.mp3"
        return episode
    }
}

private class SkipRulesShowInfoCoordinatorMock: ShowInfoCoordinating {
    func loadShowNotes(podcastUuid _: String, episodeUuid _: String) async throws -> String {
        ""
    }

    func loadEpisodeArtworkUrl(podcastUuid _: String, episodeUuid _: String) async throws -> URL? {
        nil
    }

    func loadChapters(podcastUuid _: String, episodeUuid _: String) async throws -> (metadata: [PocketCastsDataModel.Episode.Metadata.EpisodeChapter]?, podcastIndex: [podcasts.PodcastIndexChapter]?, generated: [GeneratedChapter]?) {
        (metadata: nil, podcastIndex: nil, generated: nil)
    }

    func loadTranscriptsMetadata(podcastUuid _: String, episodeUuid _: String) async throws -> EpisodeTranscriptData {
        (transcripts: [], hasGeneratedTranscripts: false, isDisplayingGeneratedTranscript: false)
    }

    func loadEpisodeSummary(podcastUuid _: String, episodeUuid _: String) async throws -> String? {
        nil
    }
}
