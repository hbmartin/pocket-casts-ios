import XCTest

@testable import PocketCastsUtils

final class LogRedactionTests: XCTestCase {

    // MARK: - Userinfo

    func testStripsUserinfo() {
        let input = "LocalFeedFetcher: fetched https://user:secret@example.com/feed.xml ok"
        XCTAssertEqual(LogRedaction.redactURLs(in: input),
                       "LocalFeedFetcher: fetched https://example.com/feed.xml ok")
    }

    func testStripsUserOnlyUserinfo() {
        let input = "fetching https://alice@example.com/feed.xml"
        XCTAssertEqual(LogRedaction.redactURLs(in: input),
                       "fetching https://example.com/feed.xml")
    }

    // MARK: - Query values

    func testBlanksSignedQueryValuesButKeepsKeys() {
        let input = "download https://cdn.example.com/ep.mp3?X-Amz-Signature=abc123&Expires=1699999999 failed"
        XCTAssertEqual(LogRedaction.redactURLs(in: input),
                       "download https://cdn.example.com/ep.mp3?X-Amz-Signature=REDACTED&Expires=REDACTED failed")
    }

    func testValuelessQueryKeyStaysValueless() {
        let input = "hit https://example.com/path?flag&token=s3cr3t"
        XCTAssertEqual(LogRedaction.redactURLs(in: input),
                       "hit https://example.com/path?flag&token=REDACTED")
    }

    // MARK: - Fragments

    func testDropsFragment() {
        let input = "opened https://example.com/page?id=42#access_token=abc"
        XCTAssertEqual(LogRedaction.redactURLs(in: input),
                       "opened https://example.com/page?id=REDACTED")
    }

    // MARK: - Diagnostic shape preserved

    func testKeepsSchemeHostPortAndPath() {
        let input = "GET http://media.example.com:8080/shows/123/episode.mp3?auth=tok"
        XCTAssertEqual(LogRedaction.redactURLs(in: input),
                       "GET http://media.example.com:8080/shows/123/episode.mp3?auth=REDACTED")
    }

    func testPlainURLWithoutSecretsIsUnchanged() {
        let input = "refreshed https://example.com/feed.xml fine"
        XCTAssertEqual(LogRedaction.redactURLs(in: input), input)
    }

    // MARK: - Multiple URLs and multi-line text

    func testRedactsMultipleURLsOnOneLine() {
        let input = "redirect https://user:pw@a.example.com/x?t=1 -> https://b.example.com/y?sig=zz"
        XCTAssertEqual(LogRedaction.redactURLs(in: input),
                       "redirect https://a.example.com/x?t=REDACTED -> https://b.example.com/y?sig=REDACTED")
    }

    func testRedactsAcrossMultipleLogLines() {
        let input = """
        2026-07-13 10:00:00 DownloadManager: Failed download uuid-1 https://cdn.example.com/a.mp3?token=one statusCode:Optional(403)
        2026-07-13 10:00:01 LocalFeedFetcher: fetched https://bob:hunter2@feeds.example.com/private.xml
        2026-07-13 10:00:02 Player: buffering stalled
        """
        let expected = """
        2026-07-13 10:00:00 DownloadManager: Failed download uuid-1 https://cdn.example.com/a.mp3?token=REDACTED statusCode:Optional(403)
        2026-07-13 10:00:01 LocalFeedFetcher: fetched https://feeds.example.com/private.xml
        2026-07-13 10:00:02 Player: buffering stalled
        """
        XCTAssertEqual(LogRedaction.redactURLs(in: input), expected)
    }

    // MARK: - Non-URL text

    func testTextWithoutURLsIsUntouched() {
        let input = "Episode duration 42:17 marked played; ratio 3:2 unchanged"
        XCTAssertEqual(LogRedaction.redactURLs(in: input), input)
    }

    func testEmptyStringIsUntouched() {
        XCTAssertEqual(LogRedaction.redactURLs(in: ""), "")
    }

    // MARK: - Malformed URLs

    func testMalformedURLFailsClosed() {
        // Invalid percent-encoding makes URLComponents parsing fail. The raw
        // candidate can contain credentials, so it must never survive export.
        let input = "weird https://exa%ZZmple.com/path?token=abc. happened"
        let output = LogRedaction.redactURLs(in: input)

        XCTAssertEqual(output, "weird <unparseable-url>. happened")
        XCTAssertFalse(output.contains("token=abc"))
    }

    // MARK: - Surrounding punctuation

    func testTrailingSentencePunctuationIsPreserved() {
        let input = "see https://example.com/a?b=c."
        XCTAssertEqual(LogRedaction.redactURLs(in: input),
                       "see https://example.com/a?b=REDACTED.")
    }

    func testParenthesizedURLKeepsClosingParen() {
        let input = "request (https://user:pw@example.com/x) timed out"
        XCTAssertEqual(LogRedaction.redactURLs(in: input),
                       "request (https://example.com/x) timed out")
    }
}
