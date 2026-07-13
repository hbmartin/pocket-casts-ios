import PocketCastsDataModel
import XCTest

@testable import podcasts

/// Pure logic of the transcript search screen: FTS-snippet highlight-marker
/// parsing and grouping of flat search hits into per-episode sections.
@MainActor
final class TranscriptSearchViewModelTests: XCTestCase {
    private typealias SnippetRun = TranscriptSearchViewModel.SnippetRun

    private func result(episode: String,
                        podcast: String? = "podcast-1",
                        segmentIndex: Int,
                        startTime: Double,
                        snippet: String = "plain") -> TranscriptSearchHit {
        TranscriptSearchHit(episodeUuid: episode,
                            podcastUuid: podcast,
                            segmentIndex: segmentIndex,
                            startTime: startTime,
                            endTime: nil,
                            speaker: nil,
                            source: .generated,
                            snippet: snippet)
    }

    // MARK: - Snippet parsing

    func testSnippetRunsSplitsHighlightMarkers() {
        let runs = TranscriptSearchViewModel.snippetRuns(from: "…talking about <b>ducks</b> in the park")

        XCTAssertEqual(runs, [
            SnippetRun(text: "…talking about ", isHighlighted: false),
            SnippetRun(text: "ducks", isHighlighted: true),
            SnippetRun(text: " in the park", isHighlighted: false)
        ])
    }

    func testSnippetRunsHandlesMultipleHighlights() {
        let runs = TranscriptSearchViewModel.snippetRuns(from: "<b>swift</b> and <b>concurrency</b>")

        XCTAssertEqual(runs, [
            SnippetRun(text: "swift", isHighlighted: true),
            SnippetRun(text: " and ", isHighlighted: false),
            SnippetRun(text: "concurrency", isHighlighted: true)
        ])
    }

    func testSnippetRunsWithoutMarkersIsSinglePlainRun() {
        XCTAssertEqual(TranscriptSearchViewModel.snippetRuns(from: "no matches here"),
                       [SnippetRun(text: "no matches here", isHighlighted: false)])
    }

    func testSnippetRunsHandlesUnterminatedMarkerGracefully() {
        // An unterminated start marker renders the remainder as plain text with
        // the marker stripped — never as a visible "<b>" literal.
        XCTAssertEqual(TranscriptSearchViewModel.snippetRuns(from: "before <b>after"),
                       [SnippetRun(text: "before after", isHighlighted: false)])
    }

    func testSnippetRunsDropsEmptyFragments() {
        XCTAssertEqual(TranscriptSearchViewModel.snippetRuns(from: "<b>edge</b>"),
                       [SnippetRun(text: "edge", isHighlighted: true)])
        XCTAssertTrue(TranscriptSearchViewModel.snippetRuns(from: "").isEmpty)
    }

    // MARK: - Grouping

    func testMakeSectionsGroupsByEpisodePreservingRelevanceOrder() {
        // Results arrive relevance-ordered (BM25): episode B has the best hit,
        // then A, then another B hit further down.
        let results = [
            result(episode: "episode-b", segmentIndex: 7, startTime: 70),
            result(episode: "episode-a", segmentIndex: 2, startTime: 20),
            result(episode: "episode-b", segmentIndex: 3, startTime: 30)
        ]

        let sections = TranscriptSearchViewModel.makeSections(from: results) { episodeUuid, _ in
            .init(episodeTitle: "Title \(episodeUuid)", podcastTitle: "Podcast")
        }

        XCTAssertEqual(sections.map(\.episodeUuid), ["episode-b", "episode-a"],
                       "Sections keep the relevance order of each episode's best hit")
        XCTAssertEqual(sections[0].episodeTitle, "Title episode-b")
        XCTAssertEqual(sections[0].podcastTitle, "Podcast")
    }

    func testMakeSectionsSortsRowsByStartTimeWithinEpisode() {
        let results = [
            result(episode: "episode-a", segmentIndex: 9, startTime: 90),
            result(episode: "episode-a", segmentIndex: 1, startTime: 10),
            result(episode: "episode-a", segmentIndex: 5, startTime: 50)
        ]

        let sections = TranscriptSearchViewModel.makeSections(from: results) { _, _ in
            .init(episodeTitle: "Title", podcastTitle: nil)
        }

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].rows.map(\.startTime), [10, 50, 90],
                       "Rows within an episode run in playback order")
        XCTAssertEqual(sections[0].rows.map(\.id), [1, 5, 9])
    }

    func testMakeSectionsFallsBackWhenEpisodeIsMissing() {
        let results = [result(episode: "gone-episode", segmentIndex: 0, startTime: 5)]

        let sections = TranscriptSearchViewModel.makeSections(from: results) { _, _ in nil }

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].episodeTitle, L10n.transcriptionSearchUnknownEpisode)
        XCTAssertNil(sections[0].podcastTitle)
    }

    func testMakeSectionsSkipsResultsWithoutAnEpisodeUuid() {
        let results = [
            result(episode: "", segmentIndex: 0, startTime: 0),
            result(episode: "episode-a", segmentIndex: 1, startTime: 10)
        ]

        let sections = TranscriptSearchViewModel.makeSections(from: results) { _, _ in
            .init(episodeTitle: "Title", podcastTitle: nil)
        }

        XCTAssertEqual(sections.map(\.episodeUuid), ["episode-a"])
    }

    func testMakeSectionsParsesSnippetRunsIntoRows() {
        let results = [result(episode: "episode-a", segmentIndex: 4, startTime: 42, snippet: "the <b>answer</b>")]

        let sections = TranscriptSearchViewModel.makeSections(from: results) { _, _ in
            .init(episodeTitle: "Title", podcastTitle: nil)
        }

        XCTAssertEqual(sections[0].rows[0].runs, [
            SnippetRun(text: "the ", isHighlighted: false),
            SnippetRun(text: "answer", isHighlighted: true)
        ])
    }
}
