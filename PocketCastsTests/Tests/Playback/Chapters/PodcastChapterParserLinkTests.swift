import PocketCastsDataModel
import XCTest

@testable import podcasts

/// Pure-logic coverage for chapter link passthrough (plans/AI UX
/// Improvements.md Phase 6): Podlove and Podcast Index chapters carry their
/// `url` into `ChapterInfo` only when it survives the shared http(s)
/// validation — the same gate the embedded ID3/MP4 parsers already use.
@MainActor
final class PodcastChapterParserLinkTests: XCTestCase {
    private let parser = PodcastChapterParser()

    // MARK: - Podlove metadata chapters

    func testPodloveChapterUrlPassthrough() {
        let chapters = parser.parsePodloveChapters([
            Episode.Metadata.EpisodeChapter(startTime: 0, title: "Valid", endTime: 60, url: "https://example.com/a"),
            Episode.Metadata.EpisodeChapter(startTime: 60, title: "Uppercase scheme", endTime: 120, url: "HTTPS://example.com/b"),
            Episode.Metadata.EpisodeChapter(startTime: 120, title: "No link", endTime: 180)
        ], episodeDuration: 240)

        XCTAssertEqual(chapters.map(\.url), ["https://example.com/a", "HTTPS://example.com/b", nil])
    }

    func testPodloveChapterInvalidUrlsAreDropped() {
        let chapters = parser.parsePodloveChapters([
            Episode.Metadata.EpisodeChapter(startTime: 0, title: "Script", endTime: 60, url: "javascript:alert(1)"),
            Episode.Metadata.EpisodeChapter(startTime: 60, title: "Ftp", endTime: 120, url: "ftp://example.com/file"),
            Episode.Metadata.EpisodeChapter(startTime: 120, title: "Schemeless", endTime: 180, url: "example.com/page"),
            Episode.Metadata.EpisodeChapter(startTime: 180, title: "Garbage", endTime: 240, url: "   ")
        ], episodeDuration: 300)

        XCTAssertEqual(chapters.map(\.url), [nil, nil, nil, nil])
    }

    func testPodloveChapterUrlDoesNotDisturbTiming() {
        let chapters = parser.parsePodloveChapters([
            Episode.Metadata.EpisodeChapter(startTime: 0, title: "One", endTime: nil, url: "https://example.com/a"),
            Episode.Metadata.EpisodeChapter(startTime: 90, title: "Two", endTime: nil)
        ], episodeDuration: 300)

        XCTAssertEqual(chapters.map(\.duration), [90, 210])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
    }

    // MARK: - Podcast Index chapters

    func testPodcastIndexChapterUrlPassthrough() {
        let chapters = parser.parsePodcastIndexChapters([
            PodcastIndexChapter(title: "Valid", number: nil, endTime: 60, startTime: 0, url: "http://example.com/a", img: nil),
            PodcastIndexChapter(title: "Invalid", number: nil, endTime: 120, startTime: 60, url: "javascript:alert(1)", img: nil),
            PodcastIndexChapter(title: "No link", number: nil, endTime: 180, startTime: 120, url: nil, img: "https://example.com/art.jpg")
        ], episodeDuration: 240)

        XCTAssertEqual(chapters.map(\.url), ["http://example.com/a", nil, nil])
    }

    // MARK: - Shared validation

    func testIsValidUrl() {
        XCTAssertTrue(PodcastChapterParser.isValidUrl("https://example.com"))
        XCTAssertTrue(PodcastChapterParser.isValidUrl("http://example.com/page?a=1"))
        XCTAssertTrue(PodcastChapterParser.isValidUrl("HTTP://EXAMPLE.COM"))

        XCTAssertFalse(PodcastChapterParser.isValidUrl(nil))
        XCTAssertFalse(PodcastChapterParser.isValidUrl(""))
        XCTAssertFalse(PodcastChapterParser.isValidUrl("example.com"))
        XCTAssertFalse(PodcastChapterParser.isValidUrl("ftp://example.com"))
        XCTAssertFalse(PodcastChapterParser.isValidUrl("javascript:alert(1)"))
        XCTAssertFalse(PodcastChapterParser.isValidUrl("file:///etc/passwd"))
    }
}
