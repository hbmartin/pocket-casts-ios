import XCTest

@testable import podcasts

@MainActor
final class TranscriptReaderViewModelTests: XCTestCase {

    @MainActor
    private final class MockTranscriptPlayback: TranscriptPlaybackManaging {
        var episodeUUID: String? = "episode-uuid"
        var podcastUUID: String? = "podcast-uuid"
        var parentIdentifier: String? = "podcast-uuid"
        var isPlayingEpisode = true
        var canSeek = true
        var time: TimeInterval = 0
        private(set) var seeks: [TimeInterval] = []

        func currentTime() -> TimeInterval { time }
        func seekTo(time: TimeInterval) { seeks.append(time) }
    }

    /// Stubbed fingerprint mapping: reference = playback - offset,
    /// playback = reference + offset. Nil offset simulates unmatched content.
    private func timing(active: Bool = true,
                        unavailable: Bool = false,
                        offset: Double? = 0) -> TranscriptReaderViewModel.TimingProvider {
        TranscriptReaderViewModel.TimingProvider(
            isActive: { active },
            isUnavailable: { unavailable },
            matchedReferenceTime: { playbackTime in offset.map { playbackTime - $0 } },
            playbackTime: { referenceTime in offset.map { referenceTime + $0 } }
        )
    }

    private func makeViewModel(playback: MockTranscriptPlayback = MockTranscriptPlayback(),
                               isGenerated: Bool = true,
                               timing: TranscriptReaderViewModel.TimingProvider? = nil,
                               isDownloaded: Bool = false) -> TranscriptReaderViewModel {
        TranscriptReaderViewModel(
            transcript: TranscriptReaderFixture.makeModel(),
            playback: playback,
            isGeneratedTranscript: isGenerated,
            episodeTitle: "Episode One",
            episodeShareURLString: "https://pca.st/episode/abc",
            timing: timing ?? self.timing(),
            isEpisodeDownloaded: { isDownloaded }
        )
    }

    // Fixture block layout: 0 = Alice header, 1 = cue 0 (10-15s),
    // 2 = cue 1 (16-20s), 3 = Bob header, 4 = cue 2 (21-25s).

    // MARK: - Current cue resolution

    func testCurrentCueResolvesBlockForReferenceTime() {
        let viewModel = makeViewModel()

        viewModel.updateCurrentCue(forReferenceTime: 12)
        XCTAssertEqual(viewModel.currentCueBlockID, 1)

        viewModel.updateCurrentCue(forReferenceTime: 17)
        XCTAssertEqual(viewModel.currentCueBlockID, 2)

        viewModel.updateCurrentCue(forReferenceTime: 22)
        XCTAssertEqual(viewModel.currentCueBlockID, 4)
    }

    func testCurrentCueBeforeFirstCueClears() {
        let viewModel = makeViewModel()

        viewModel.updateCurrentCue(forReferenceTime: 12)
        XCTAssertEqual(viewModel.currentCueBlockID, 1)

        viewModel.updateCurrentCue(forReferenceTime: 5)
        XCTAssertNil(viewModel.currentCueBlockID)
    }

    func testCurrentCueBetweenCuesKeepsPreviousHighlight() {
        let viewModel = makeViewModel()

        viewModel.updateCurrentCue(forReferenceTime: 12)
        XCTAssertEqual(viewModel.currentCueBlockID, 1)

        // 15.5 falls in the gap between cue 0 and cue 1 — mirror the VC and
        // keep the previous highlight.
        viewModel.updateCurrentCue(forReferenceTime: 15.5)
        XCTAssertEqual(viewModel.currentCueBlockID, 1)
    }

    func testRefreshCurrentCueMapsPlaybackTimeThroughStubbedFingerprint() {
        let playback = MockTranscriptPlayback()
        playback.time = 42
        // reference = playback - 30 => 12 => cue 0
        let viewModel = makeViewModel(playback: playback, timing: timing(offset: 30))

        viewModel.refreshCurrentCue()

        XCTAssertEqual(viewModel.currentCueBlockID, 1)
    }

    func testRefreshCurrentCueClearsWhenTimingInactive() {
        let playback = MockTranscriptPlayback()
        playback.time = 42
        let viewModel = makeViewModel(playback: playback, timing: timing(active: false, offset: 30))

        viewModel.updateCurrentCue(forReferenceTime: 12)
        XCTAssertEqual(viewModel.currentCueBlockID, 1)

        viewModel.refreshCurrentCue()
        XCTAssertNil(viewModel.currentCueBlockID)
    }

    func testRefreshCurrentCueClearsWhenMappingReturnsNil() {
        let playback = MockTranscriptPlayback()
        playback.time = 42
        let viewModel = makeViewModel(playback: playback, timing: timing(offset: nil))

        viewModel.updateCurrentCue(forReferenceTime: 12)
        viewModel.refreshCurrentCue()

        XCTAssertNil(viewModel.currentCueBlockID)
    }

    // MARK: - Seeking

    func testSeekMapsReferenceTimeForGeneratedTranscript() {
        let playback = MockTranscriptPlayback()
        let viewModel = makeViewModel(playback: playback, timing: timing(offset: 30))

        let outcome = viewModel.seek(toCueIndex: 0)

        XCTAssertEqual(outcome, .seeked(to: 40)) // cue starts at 10, offset +30
        XCTAssertEqual(playback.seeks, [40])
    }

    func testSeekUsesPlainCueTimeForExternalTranscript() {
        let playback = MockTranscriptPlayback()
        let viewModel = makeViewModel(playback: playback, isGenerated: false, timing: timing(offset: nil))

        let outcome = viewModel.seek(toCueIndex: 2)

        XCTAssertEqual(outcome, .seeked(to: 21))
        XCTAssertEqual(playback.seeks, [21])
    }

    func testSeekWithoutMappingWhenUnavailableStaysSilent() {
        let playback = MockTranscriptPlayback()
        let viewModel = makeViewModel(playback: playback, timing: timing(unavailable: true, offset: nil))

        XCTAssertEqual(viewModel.seek(toCueIndex: 0), .mappingUnavailable)
        XCTAssertTrue(playback.seeks.isEmpty)
    }

    func testSeekWithoutMappingWhenDownloadedStaysSilent() {
        let playback = MockTranscriptPlayback()
        let viewModel = makeViewModel(playback: playback, timing: timing(offset: nil), isDownloaded: true)

        XCTAssertEqual(viewModel.seek(toCueIndex: 0), .mappingUnavailable)
        XCTAssertTrue(playback.seeks.isEmpty)
    }

    func testSeekWithoutMappingWhenStreamingSuggestsDownload() {
        let playback = MockTranscriptPlayback()
        let viewModel = makeViewModel(playback: playback, timing: timing(offset: nil), isDownloaded: false)

        XCTAssertEqual(viewModel.seek(toCueIndex: 0), .downloadRequiredHint)
        XCTAssertTrue(playback.seeks.isEmpty)
    }

    func testSeekNotAllowedWhenPlaybackCannotSeek() {
        let playback = MockTranscriptPlayback()
        playback.canSeek = false
        let viewModel = makeViewModel(playback: playback)

        XCTAssertEqual(viewModel.seek(toCueIndex: 0), .notAllowed)
        XCTAssertTrue(playback.seeks.isEmpty)
    }

    func testSeekOutOfRangeCueIndexNotAllowed() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.seek(toCueIndex: 99), .notAllowed)
    }

    // MARK: - Search

    func testSearchFindsMatchesAcrossBlocks() {
        let viewModel = makeViewModel()

        viewModel.search(term: "pleasure")

        XCTAssertEqual(viewModel.matches.count, 2)
        XCTAssertEqual(viewModel.matches[0].blockID, 2)
        XCTAssertEqual(viewModel.matches[1].blockID, 4)

        // Offsets are character offsets within the block's trimmed text.
        XCTAssertEqual(viewModel.matches[0].characterRange, 21 ..< 29)
        XCTAssertEqual(viewModel.matches[1].characterRange, 8 ..< 16)

        XCTAssertEqual(viewModel.matchesByBlock[2]?.count, 1)
        XCTAssertEqual(viewModel.matchesByBlock[4]?.count, 1)
        XCTAssertEqual(viewModel.currentMatchIndex, 0)
    }

    func testSearchIsCaseInsensitive() {
        let viewModel = makeViewModel()

        viewModel.search(term: "PLEASURE")

        XCTAssertEqual(viewModel.matches.count, 2)
    }

    func testSearchMatchesSpeakerHeaders() {
        let viewModel = makeViewModel()

        viewModel.search(term: "alice")

        XCTAssertEqual(viewModel.matches.count, 1)
        XCTAssertEqual(viewModel.matches[0].blockID, 0)
        XCTAssertEqual(viewModel.matches[0].characterRange, 0 ..< 5)
    }

    func testMatchNavigationWrapsInBothDirections() {
        let viewModel = makeViewModel()
        viewModel.search(term: "pleasure")

        XCTAssertEqual(viewModel.currentMatchIndex, 0)

        viewModel.nextMatch()
        XCTAssertEqual(viewModel.currentMatchIndex, 1)

        viewModel.nextMatch()
        XCTAssertEqual(viewModel.currentMatchIndex, 0)

        viewModel.previousMatch()
        XCTAssertEqual(viewModel.currentMatchIndex, 1)

        XCTAssertEqual(viewModel.currentMatch?.blockID, 4)
    }

    func testMatchNavigationNoopsWithoutMatches() {
        let viewModel = makeViewModel()

        viewModel.nextMatch()
        viewModel.previousMatch()

        XCTAssertEqual(viewModel.currentMatchIndex, 0)
        XCTAssertNil(viewModel.currentMatch)
    }

    func testEmptyTermClearsSearch() {
        let viewModel = makeViewModel()
        viewModel.search(term: "pleasure")
        XCTAssertFalse(viewModel.matches.isEmpty)

        viewModel.search(term: "")

        XCTAssertTrue(viewModel.matches.isEmpty)
        XCTAssertTrue(viewModel.matchesByBlock.isEmpty)
        XCTAssertEqual(viewModel.currentMatchIndex, 0)
    }

    // MARK: - Quote / clip payloads

    func testQuoteTextForCueBlockIncludesAttributionAndAnchor() {
        let viewModel = makeViewModel()

        let quote = viewModel.quoteText(forBlock: 1)

        XCTAssertEqual(quote, "\u{201C}Hello and welcome to the show.\u{201D} — Episode One\nhttps://pca.st/episode/abc?t=10")
    }

    func testQuoteTextForSpeakerBlockIsNil() {
        let viewModel = makeViewModel()

        XCTAssertNil(viewModel.quoteText(forBlock: 0))
        XCTAssertNil(viewModel.quoteText(forBlock: 99))
    }

    func testClipRangeForCueBlock() {
        let viewModel = makeViewModel()

        let range = viewModel.clipRange(forBlock: 4)

        XCTAssertEqual(range?.start, 21)
        XCTAssertEqual(range?.end, 25)
    }

    func testClipRangeForSpeakerBlockIsNil() {
        let viewModel = makeViewModel()

        XCTAssertNil(viewModel.clipRange(forBlock: 3))
        XCTAssertNil(viewModel.clipRange(forBlock: 99))
    }

    // MARK: - Follow state

    func testUserScrollPausesFollowingAndResumeRestoresIt() {
        let viewModel = makeViewModel()
        XCTAssertTrue(viewModel.isFollowing)

        viewModel.noteUserScrolled()
        XCTAssertFalse(viewModel.isFollowing)

        viewModel.resumeFollowing()
        XCTAssertTrue(viewModel.isFollowing)
    }
}
