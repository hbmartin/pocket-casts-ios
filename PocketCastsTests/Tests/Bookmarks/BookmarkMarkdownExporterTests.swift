import XCTest
@testable import podcasts

final class BookmarkMarkdownExporterTests: XCTestCase {
    private var exporter: BookmarkMarkdownExporter {
        var exporter = BookmarkMarkdownExporter()
        exporter.locale = Locale(identifier: "en_US_POSIX")
        exporter.timeZone = TimeZone(identifier: "UTC")!
        return exporter
    }

    private func resolved(
        title: String = "A moment",
        time: TimeInterval = 754,
        created: TimeInterval = 1_760_000_000,
        episode: String = "Episode One",
        podcast: String = "Podcast A",
        link: String? = "https://pca.st/episode/abc?t=754"
    ) -> BookmarkMarkdownExporter.ResolvedBookmark {
        .init(
            title: title,
            time: time,
            created: Date(timeIntervalSince1970: created),
            episodeTitle: episode,
            podcastTitle: podcast,
            shareLink: link
        )
    }

    func testGroupsPodcastThenEpisodePreservingOrder() {
        let markdown = exporter.markdown(for: [
            resolved(title: "First", episode: "Ep 1", podcast: "Pod A"),
            resolved(title: "Second", episode: "Ep 2", podcast: "Pod A"),
            resolved(title: "Third", episode: "Ep 9", podcast: "Pod B"),
            resolved(title: "Fourth", episode: "Ep 1", podcast: "Pod A")
        ])

        let lines = markdown.components(separatedBy: "\n")
        let podAIndex = lines.firstIndex(of: "## Pod A")
        let podBIndex = lines.firstIndex(of: "## Pod B")
        XCTAssertNotNil(podAIndex)
        XCTAssertNotNil(podBIndex)
        XCTAssertLessThan(podAIndex!, podBIndex!, "podcast groups keep first-appearance order")

        // Ep 1 groups both of its bookmarks even though Ep 2 came between them
        let ep1Index = lines.firstIndex(of: "### Ep 1")!
        let ep2Index = lines.firstIndex(of: "### Ep 2")!
        XCTAssertLessThan(ep1Index, ep2Index)
        let ep1Section = lines[ep1Index ..< ep2Index].joined(separator: "\n")
        XCTAssertTrue(ep1Section.contains("First"))
        XCTAssertTrue(ep1Section.contains("Fourth"))
    }

    func testBookmarkLineFormatWithShareLink() {
        let markdown = exporter.markdown(for: [resolved()])

        XCTAssertTrue(
            markdown.contains("- [00:12:34](https://pca.st/episode/abc?t=754) A moment — "),
            "line was: \(markdown)"
        )
    }

    func testBookmarkLineWithoutShareLinkUsesPlainTimestamp() {
        let markdown = exporter.markdown(for: [resolved(link: nil)])

        XCTAssertTrue(markdown.contains("- 00:12:34 A moment — "), "line was: \(markdown)")
        XCTAssertFalse(markdown.contains("]("))
    }

    func testTimestampFormatting() {
        XCTAssertEqual(BookmarkMarkdownExporter.timestamp(0), "00:00:00")
        XCTAssertEqual(BookmarkMarkdownExporter.timestamp(59.4), "00:00:59")
        XCTAssertEqual(BookmarkMarkdownExporter.timestamp(3_599), "00:59:59")
        XCTAssertEqual(BookmarkMarkdownExporter.timestamp(3_600), "01:00:00")
        XCTAssertEqual(BookmarkMarkdownExporter.timestamp(7_265), "02:01:05")
        XCTAssertEqual(BookmarkMarkdownExporter.timestamp(-5), "00:00:00")
    }

    func testTitlesCannotBreakMarkdownStructure() {
        let markdown = exporter.markdown(for: [
            resolved(title: "test [evil](x) # title\nsecond line", episode: "Ep # one [x]", podcast: "Pod ## B")
        ])

        XCTAssertTrue(markdown.contains("## Pod \\#\\# B"))
        XCTAssertTrue(markdown.contains("### Ep \\# one \\[x\\]"))
        XCTAssertTrue(markdown.contains("test \\[evil\\](x) \\# title second line"))
    }

    func testEmptyListStillProducesHeader() {
        let markdown = exporter.markdown(for: [])
        XCTAssertTrue(markdown.hasPrefix("# "))
    }
}
