import CoreMedia
import XCTest

@testable import podcasts
@testable import PocketCastsDataModel

final class ChapterSkipRulesTests: XCTestCase {
    // MARK: - matches(title:patterns:)

    func testMatchesSimpleSubstring() {
        XCTAssertTrue(ChapterSkipRules.matches(title: "Sponsor Break", patterns: ["sponsor"]))
        XCTAssertTrue(ChapterSkipRules.matches(title: "A word from our sponsors", patterns: ["sponsor"]))
        XCTAssertFalse(ChapterSkipRules.matches(title: "Interview", patterns: ["sponsor"]))
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertTrue(ChapterSkipRules.matches(title: "SPONSOR BREAK", patterns: ["Sponsor"]))
        XCTAssertTrue(ChapterSkipRules.matches(title: "ad break", patterns: ["AD BREAK"]))
    }

    func testMatchingTrimsWhitespace() {
        XCTAssertTrue(ChapterSkipRules.matches(title: "  Sponsor Break \n", patterns: ["sponsor"]))
        XCTAssertTrue(ChapterSkipRules.matches(title: "Sponsor Break", patterns: ["  sponsor  "]))
    }

    func testEmptyOrWhitespaceOnlyPatternsNeverMatch() {
        XCTAssertFalse(ChapterSkipRules.matches(title: "Sponsor Break", patterns: []))
        XCTAssertFalse(ChapterSkipRules.matches(title: "Sponsor Break", patterns: [""]))
        XCTAssertFalse(ChapterSkipRules.matches(title: "Sponsor Break", patterns: ["   ", "\n"]))
    }

    func testEmptyTitleNeverMatches() {
        XCTAssertFalse(ChapterSkipRules.matches(title: "", patterns: ["sponsor"]))
        XCTAssertFalse(ChapterSkipRules.matches(title: "   ", patterns: ["sponsor"]))
    }

    func testAnyPatternInTheListMatches() {
        let patterns = ["intro", "ad break", "outro"]
        XCTAssertTrue(ChapterSkipRules.matches(title: "Intro & welcome", patterns: patterns))
        XCTAssertTrue(ChapterSkipRules.matches(title: "An Ad Break", patterns: patterns))
        XCTAssertFalse(ChapterSkipRules.matches(title: "Listener questions", patterns: patterns))
    }

    func testUnicodeTitlesMatch() {
        XCTAssertTrue(ChapterSkipRules.matches(title: "Café ☕️ sponsor segment", patterns: ["café"]))
        XCTAssertTrue(ChapterSkipRules.matches(title: "スポンサーのお知らせ", patterns: ["スポンサー"]))
        XCTAssertTrue(ChapterSkipRules.matches(title: "🎙 Werbung — Anzeige", patterns: ["werbung"]))
        XCTAssertFalse(ChapterSkipRules.matches(title: "スポンサーのお知らせ", patterns: ["広告"]))
    }

    // MARK: - apply(to:patterns:reEnabledIndices:)

    func testApplyDeselectsMatchingChaptersAndReturnsTheirIndices() {
        let chapters = [
            chapter(index: 0, title: "Intro"),
            chapter(index: 1, title: "Sponsor Break"),
            chapter(index: 2, title: "Main topic"),
            chapter(index: 3, title: "Another sponsor read")
        ]

        let skipped = ChapterSkipRules.apply(to: chapters, patterns: ["sponsor"], reEnabledIndices: [])

        XCTAssertEqual(skipped, [1, 3])
        XCTAssertTrue(chapters[0].shouldPlay)
        XCTAssertFalse(chapters[1].shouldPlay)
        XCTAssertTrue(chapters[2].shouldPlay)
        XCTAssertFalse(chapters[3].shouldPlay)
    }

    func testApplyWithEmptyPatternsChangesNothing() {
        let chapters = [chapter(index: 0, title: "Sponsor Break")]

        let skipped = ChapterSkipRules.apply(to: chapters, patterns: [], reEnabledIndices: [])

        XCTAssertTrue(skipped.isEmpty)
        XCTAssertTrue(chapters[0].shouldPlay)
    }

    func testApplySkipsSessionReEnabledChapters() {
        let chapters = [
            chapter(index: 0, title: "Sponsor Break"),
            chapter(index: 1, title: "Sponsor Break 2")
        ]

        let skipped = ChapterSkipRules.apply(to: chapters, patterns: ["sponsor"], reEnabledIndices: [0])

        XCTAssertEqual(skipped, [1])
        XCTAssertTrue(chapters[0].shouldPlay)
        XCTAssertFalse(chapters[1].shouldPlay)
    }

    func testApplyLeavesManuallyDeselectedChaptersOutOfTheRuleSkippedSet() {
        let manuallyDeselected = chapter(index: 0, title: "Sponsor Break")
        manuallyDeselected.shouldPlay = false

        let skipped = ChapterSkipRules.apply(to: [manuallyDeselected], patterns: ["sponsor"], reEnabledIndices: [])

        XCTAssertTrue(skipped.isEmpty)
        XCTAssertFalse(manuallyDeselected.shouldPlay)
    }

    // MARK: - Helpers

    private func chapter(index: Int, title: String) -> ChapterInfo {
        let chapter = ChapterInfo()
        chapter.index = index
        chapter.title = title
        chapter.startTime = CMTime(seconds: Double(index) * 100, preferredTimescale: .max)
        chapter.duration = 100
        return chapter
    }
}
