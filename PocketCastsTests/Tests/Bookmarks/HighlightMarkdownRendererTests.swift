import XCTest

@testable import podcasts

/// Golden coverage for the PKM Markdown renderer (Highlights program S5).
final class HighlightMarkdownRendererTests: XCTestCase {
    private var renderer: HighlightMarkdownRenderer {
        var renderer = HighlightMarkdownRenderer()
        renderer.locale = Locale(identifier: "en_US")
        renderer.timeZone = TimeZone(identifier: "UTC")!
        return renderer
    }

    private func makeExport(highlights: [HighlightMarkdownRenderer.ResolvedHighlight]) -> HighlightMarkdownRenderer.EpisodeExport {
        .init(podcastTitle: "The Test Show", episodeTitle: "Episode One", episodeUuid: "ep-1", highlights: highlights)
    }

    func testRendersFrontmatterBlocksAndTags() {
        let export = makeExport(highlights: [
            .init(title: "Key insight", time: 3723, endTime: 3750,
                  created: Date(timeIntervalSince1970: 1_700_000_000),
                  excerpt: "The exact words worth keeping.",
                  tags: ["AI", "investing"],
                  shareLink: "https://pca.st/episode/ep-1?t=3723"),
            .init(title: "Plain bookmark", time: 65, endTime: nil,
                  created: Date(timeIntervalSince1970: 1_700_000_000),
                  excerpt: nil, tags: [], shareLink: nil)
        ])

        let markdown = renderer.markdown(for: export)

        XCTAssertTrue(markdown.hasPrefix("""
        ---
        podcast: "The Test Show"
        episode: "Episode One"
        episode_uuid: ep-1
        tags: ["AI", "investing"]
        ---
        """), markdown)
        XCTAssertTrue(markdown.contains("# Episode One"), markdown)
        XCTAssertTrue(markdown.contains("## [1:02:03](https://pca.st/episode/ep-1?t=3723) Key insight"), markdown)
        XCTAssertTrue(markdown.contains("> The exact words worth keeping."), markdown)
        XCTAssertTrue(markdown.contains("#AI #investing — Nov 14, 2023"), markdown)
        XCTAssertTrue(markdown.contains("## 1:05 Plain bookmark"), markdown)
    }

    func testTagsWithSpacesBecomeHyphenatedHashtags() {
        let export = makeExport(highlights: [
            .init(title: "T", time: 1, endTime: nil, created: Date(timeIntervalSince1970: 0),
                  excerpt: "E", tags: ["deep work"], shareLink: nil)
        ])

        XCTAssertTrue(renderer.markdown(for: export).contains("#deep-work"))
    }

    func testExcerptTransformHookApplies() {
        var renderer = self.renderer
        renderer.excerptTransform = { $0.replacingOccurrences(of: "Ada Lovelace", with: "[[Ada Lovelace]]") }

        let export = makeExport(highlights: [
            .init(title: "T", time: 1, endTime: nil, created: Date(timeIntervalSince1970: 0),
                  excerpt: "As Ada Lovelace said.", tags: [], shareLink: nil)
        ])

        XCTAssertTrue(renderer.markdown(for: export).contains("> As [[Ada Lovelace]] said."))
    }

    func testRelativePathSanitizesComponents() {
        let export = HighlightMarkdownRenderer.EpisodeExport(
            podcastTitle: "Slash/Colon: Show?",
            episodeTitle: "What <is> \"this\"|really*",
            episodeUuid: "ep-2",
            highlights: []
        )

        let path = renderer.relativePath(for: export)

        XCTAssertEqual(path, "Slash Colon  Show/What  is   this  really--ep-2.md")
        XCTAssertFalse(path.dropFirst().contains(":"))
    }

    func testRelativePathNeutralizesDotComponents() {
        let export = HighlightMarkdownRenderer.EpisodeExport(
            podcastTitle: "..",
            episodeTitle: ".",
            episodeUuid: "ep-3",
            highlights: []
        )

        let path = renderer.relativePath(for: export)

        XCTAssertEqual(path, "Untitled/Untitled--ep-3.md",
                       "dot components must not escape the export root")
    }

    func testRelativePathDistinguishesEpisodesWithTheSameTitle() {
        let first = HighlightMarkdownRenderer.EpisodeExport(
            podcastTitle: "The Show",
            episodeTitle: "Trailer",
            episodeUuid: "first-uuid",
            highlights: []
        )
        let second = HighlightMarkdownRenderer.EpisodeExport(
            podcastTitle: "The Show",
            episodeTitle: "Trailer",
            episodeUuid: "second-uuid",
            highlights: []
        )

        XCTAssertNotEqual(renderer.relativePath(for: first), renderer.relativePath(for: second))
        XCTAssertEqual(renderer.legacyRelativePath(for: first), "The Show/Trailer.md")
    }

    func testYamlEscapesQuotesInTitles() {
        let export = HighlightMarkdownRenderer.EpisodeExport(
            podcastTitle: "The \"Quoted\" Show",
            episodeTitle: "Plain",
            episodeUuid: "ep-3",
            highlights: []
        )

        XCTAssertTrue(renderer.markdown(for: export).contains(#"podcast: "The \"Quoted\" Show""#))
    }

    func testYamlAndHeadingsSurviveNewlineTitles() {
        // A feed-controlled title containing "\n---\n" must not terminate the
        // frontmatter block early or break the heading line.
        let export = HighlightMarkdownRenderer.EpisodeExport(
            podcastTitle: "Show",
            episodeTitle: "Line one\n---\nLine two",
            episodeUuid: "ep-4",
            highlights: []
        )

        let markdown = renderer.markdown(for: export)

        XCTAssertTrue(markdown.contains(#"episode: "Line one\n---\nLine two""#),
                      "newlines encode as literal \\n inside the quoted scalar")
        XCTAssertTrue(markdown.contains("# Line one --- Line two"),
                      "the heading folds newlines to spaces")
        // Exactly the frontmatter's own two fences survive as standalone lines.
        let fenceLines = markdown.components(separatedBy: "\n").filter { $0 == "---" }
        XCTAssertEqual(fenceLines.count, 2)
    }
}
