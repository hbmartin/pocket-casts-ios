import XCTest

@testable import podcasts

/// The Readwise payload builder is pure; these pin its mapping rules
/// (Highlights program S6).
final class ReadwiseClientTests: XCTestCase {
    func testHighlightMapsExcerptTitleTagsAndIdentity() {
        let highlight = ReadwiseClient.highlight(
            excerpt: "The exact words worth keeping.",
            bookmarkTitle: "Key insight",
            bookmarkUuid: "bm-1",
            time: 3723,
            created: Date(timeIntervalSince1970: 1_700_000_000),
            tags: ["AI", "deep work"],
            episodeTitle: "Episode One",
            podcastTitle: "The Test Show",
            shareLink: "https://pca.st/episode/ep-1?t=3723"
        )

        XCTAssertEqual(highlight.text, "The exact words worth keeping.")
        XCTAssertEqual(highlight.title, "Episode One")
        XCTAssertEqual(highlight.author, "The Test Show")
        XCTAssertEqual(highlight.sourceType, "podcast")
        XCTAssertEqual(highlight.sourceUrl, "https://pca.st/episode/ep-1?t=3723")
        XCTAssertEqual(highlight.highlightUrl, "https://pca.st/episode/ep-1?t=3723&hl=bm-1",
                       "the bookmark uuid rides highlight_url so re-pushes update in place")
        XCTAssertEqual(highlight.note, "Key insight\n.AI .deep-work")
        XCTAssertEqual(highlight.highlightedAt, "2023-11-14T22:13:20Z")
    }

    func testPlainBookmarkFallsBackToTitleAsText() {
        let highlight = ReadwiseClient.highlight(
            excerpt: nil,
            bookmarkTitle: "Remember this part",
            bookmarkUuid: "bm-2",
            time: 60,
            created: Date(timeIntervalSince1970: 0),
            tags: [],
            episodeTitle: "Episode",
            podcastTitle: nil,
            shareLink: nil
        )

        XCTAssertEqual(highlight.text, "Remember this part")
        XCTAssertNil(highlight.note, "no excerpt means the title IS the text, not a note")
        XCTAssertNil(highlight.highlightUrl)
    }

    func testDefaultTitleNeverDuplicatesIntoNote() {
        let highlight = ReadwiseClient.highlight(
            excerpt: "Excerpt.",
            bookmarkTitle: L10n.bookmarkDefaultTitle,
            bookmarkUuid: "bm-3",
            time: 1,
            created: Date(timeIntervalSince1970: 0),
            tags: [],
            episodeTitle: "Episode",
            podcastTitle: nil,
            shareLink: nil
        )

        XCTAssertNil(highlight.note)
    }

    func testEncodingUsesReadwiseFieldNames() throws {
        let highlight = ReadwiseClient.highlight(
            excerpt: "E", bookmarkTitle: "T", bookmarkUuid: "u", time: 0,
            created: Date(timeIntervalSince1970: 0), tags: [],
            episodeTitle: "Ep", podcastTitle: nil, shareLink: "https://x/y"
        )

        let json = String(data: try JSONEncoder().encode(highlight), encoding: .utf8)!

        XCTAssertTrue(json.contains("\"source_type\":\"podcast\""), json)
        XCTAssertTrue(json.contains("\"highlight_url\":"), json)
        XCTAssertTrue(json.contains("\"highlighted_at\":"), json)
    }

    func testRateLimitParsesRetryAfter() {
        let response = HTTPURLResponse(
            url: URL(string: "https://readwise.io/api/v2/highlights/")!,
            statusCode: 429, httpVersion: nil,
            headerFields: ["Retry-After": "120"]
        )!

        XCTAssertThrowsError(try ReadwiseClient.check(response)) { error in
            XCTAssertEqual(error as? ReadwiseClient.ClientError, .rateLimited(retryAfter: 120))
        }
    }
}
