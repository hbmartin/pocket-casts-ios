import XCTest
@testable import podcasts

@MainActor
final class PlaybackIntentActionHandlerTests: XCTestCase {

    /// Records calls and returns scripted results so the handler logic can be
    /// verified without touching `PlaybackManager`/`DataManager`.
    private final class FakePlaybackFacade: PlaybackFacade {
        var playing = false
        var currentEpisode = false
        var upNext = 0
        var suggestedLoads = true
        var filterTopLoads = true
        var filterAllStarts = true
        var podcastTopLoads = true

        private(set) var playCount = 0
        private(set) var pauseCount = 0
        private(set) var playPauseCount = 0
        private(set) var skipBackCount = 0
        private(set) var skipForwardCount = 0
        private(set) var nextChapterCount = 0
        private(set) var previousChapterCount = 0
        private(set) var removedCurrentFromUpNext = 0
        private(set) var sleepTimerSeconds: TimeInterval?
        private(set) var extendedBySeconds: TimeInterval?
        private(set) var refreshCount = 0

        func isPlaying() -> Bool { playing }
        func hasCurrentEpisode() -> Bool { currentEpisode }
        func upNextCount() -> Int { upNext }
        func play() { playCount += 1 }
        func pause() { pauseCount += 1 }
        func playPause() { playPauseCount += 1 }
        func skipBack() { skipBackCount += 1 }
        func skipForward() { skipForwardCount += 1 }
        func skipToNextChapter() { nextChapterCount += 1 }
        func skipToPreviousChapter() { previousChapterCount += 1 }
        func removeCurrentEpisodeFromUpNext() { removedCurrentFromUpNext += 1 }
        func loadSuggestedEpisode() -> Bool { suggestedLoads }
        func loadTopEpisode(forFilterUuid _: String) -> Bool { filterTopLoads }
        func playAllEpisodes(forFilterUuid _: String) -> Bool { filterAllStarts }
        func loadTopEpisode(forPodcastUuid _: String) -> Bool { podcastTopLoads }
        func setSleepTimer(seconds: TimeInterval) { sleepTimerSeconds = seconds }
        func extendSleepTimer(bySeconds seconds: TimeInterval) { extendedBySeconds = seconds }
        func refreshWidgets() { refreshCount += 1 }
    }

    private func makeHandler(_ facade: FakePlaybackFacade) -> PlaybackIntentActionHandler {
        PlaybackIntentActionHandler(facade: facade)
    }

    // MARK: WidgetKit control actions

    func testControlPlayPauseRoutesToFacadeAndRefreshes() {
        let fake = FakePlaybackFacade()
        makeHandler(fake).perform(.playPause)
        XCTAssertEqual(fake.playPauseCount, 1)
        XCTAssertEqual(fake.refreshCount, 1)
    }

    func testControlSkipBackRoutesToFacadeAndRefreshes() {
        let fake = FakePlaybackFacade()
        makeHandler(fake).perform(.skipBack)
        XCTAssertEqual(fake.skipBackCount, 1)
        XCTAssertEqual(fake.refreshCount, 1)
    }

    func testControlSkipForwardRoutesToFacadeAndRefreshes() {
        let fake = FakePlaybackFacade()
        makeHandler(fake).perform(.skipForward)
        XCTAssertEqual(fake.skipForwardCount, 1)
        XCTAssertEqual(fake.refreshCount, 1)
    }

    // MARK: Resume / pause

    func testResumeRequiresCurrentEpisode() {
        let fake = FakePlaybackFacade()
        fake.currentEpisode = false
        XCTAssertFalse(makeHandler(fake).resume())
        XCTAssertEqual(fake.playCount, 0)
        XCTAssertEqual(fake.refreshCount, 0)
    }

    func testResumePlaysWhenEpisodeAvailable() {
        let fake = FakePlaybackFacade()
        fake.currentEpisode = true
        XCTAssertTrue(makeHandler(fake).resume())
        XCTAssertEqual(fake.playCount, 1)
        XCTAssertEqual(fake.refreshCount, 1)
    }

    func testPausePlaybackAlwaysPausesAndRefreshes() {
        let fake = FakePlaybackFacade()
        makeHandler(fake).pausePlayback()
        XCTAssertEqual(fake.pauseCount, 1)
        XCTAssertEqual(fake.refreshCount, 1)
    }

    // MARK: Up Next

    func testPlayUpNextRequiresQueuedContent() {
        let fake = FakePlaybackFacade()
        fake.currentEpisode = true
        fake.upNext = 0
        XCTAssertFalse(makeHandler(fake).playUpNext())
        XCTAssertEqual(fake.removedCurrentFromUpNext, 0)
        XCTAssertEqual(fake.refreshCount, 0)
    }

    func testPlayUpNextRequiresCurrentEpisode() {
        let fake = FakePlaybackFacade()
        fake.currentEpisode = false
        fake.upNext = 3
        XCTAssertFalse(makeHandler(fake).playUpNext())
        XCTAssertEqual(fake.removedCurrentFromUpNext, 0)
    }

    func testPlayUpNextRemovesCurrentWhenQueued() {
        let fake = FakePlaybackFacade()
        fake.currentEpisode = true
        fake.upNext = 2
        XCTAssertTrue(makeHandler(fake).playUpNext())
        XCTAssertEqual(fake.removedCurrentFromUpNext, 1)
        XCTAssertEqual(fake.refreshCount, 1)
    }

    // MARK: Conditional loads

    func testPlaySuggestedReflectsFacadeResult() {
        let failing = FakePlaybackFacade()
        failing.suggestedLoads = false
        XCTAssertFalse(makeHandler(failing).playSuggested())
        XCTAssertEqual(failing.refreshCount, 0)

        let succeeding = FakePlaybackFacade()
        succeeding.suggestedLoads = true
        XCTAssertTrue(makeHandler(succeeding).playSuggested())
        XCTAssertEqual(succeeding.refreshCount, 1)
    }

    func testPlayPodcastReflectsFacadeResult() {
        let failing = FakePlaybackFacade()
        failing.podcastTopLoads = false
        XCTAssertFalse(makeHandler(failing).playPodcast(uuid: "abc"))

        let succeeding = FakePlaybackFacade()
        succeeding.podcastTopLoads = true
        XCTAssertTrue(makeHandler(succeeding).playPodcast(uuid: "abc"))
        XCTAssertEqual(succeeding.refreshCount, 1)
    }

    func testPlayFilterAndPlayAllReflectFacadeResult() {
        let fake = FakePlaybackFacade()
        fake.filterTopLoads = true
        fake.filterAllStarts = true
        XCTAssertTrue(makeHandler(fake).playFilter(uuid: "f"))
        XCTAssertTrue(makeHandler(fake).playAllFilter(uuid: "f"))
    }

    // MARK: Chapters / sleep timer

    func testChapterNavigationRoutesAndRefreshes() {
        let fake = FakePlaybackFacade()
        let handler = makeHandler(fake)
        handler.nextChapter()
        handler.previousChapter()
        XCTAssertEqual(fake.nextChapterCount, 1)
        XCTAssertEqual(fake.previousChapterCount, 1)
        XCTAssertEqual(fake.refreshCount, 2)
    }

    func testSleepTimerConvertsMinutesToSeconds() {
        let fake = FakePlaybackFacade()
        XCTAssertTrue(makeHandler(fake).setSleepTimer(minutes: 10))
        XCTAssertEqual(fake.sleepTimerSeconds, 600)
        XCTAssertEqual(fake.refreshCount, 1)
    }

    func testSleepTimerRejectsNonPositiveMinutes() {
        let fake = FakePlaybackFacade()

        XCTAssertFalse(makeHandler(fake).setSleepTimer(minutes: 0))
        XCTAssertFalse(makeHandler(fake).setSleepTimer(minutes: -1))
        XCTAssertNil(fake.sleepTimerSeconds)
        XCTAssertEqual(fake.refreshCount, 0)
    }

    func testExtendSleepTimerConvertsMinutesToSeconds() {
        let fake = FakePlaybackFacade()
        XCTAssertTrue(makeHandler(fake).extendSleepTimer(minutes: 5))
        XCTAssertEqual(fake.extendedBySeconds, 300)
        XCTAssertEqual(fake.refreshCount, 1)
    }

    func testExtendSleepTimerRejectsNonPositiveMinutes() {
        let fake = FakePlaybackFacade()

        XCTAssertFalse(makeHandler(fake).extendSleepTimer(minutes: 0))
        XCTAssertFalse(makeHandler(fake).extendSleepTimer(minutes: -1))
        XCTAssertNil(fake.extendedBySeconds)
        XCTAssertEqual(fake.refreshCount, 0)
    }
}
