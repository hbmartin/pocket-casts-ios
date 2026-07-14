import CoreSpotlight
import XCTest

@testable import podcasts

final class SpotlightItemBuilderTests: XCTestCase {

    // MARK: - Identifiers

    func testIdentifierRoundTrip() {
        let episode = SpotlightItemBuilder.Target.episode(uuid: "ep-1")
        XCTAssertEqual(SpotlightItemBuilder.identifier(for: episode), "episode:ep-1")
        XCTAssertEqual(SpotlightItemBuilder.parse(identifier: "episode:ep-1"), episode)

        let highlight = SpotlightItemBuilder.Target.highlight(bookmarkUuid: "bm-1")
        XCTAssertEqual(SpotlightItemBuilder.identifier(for: highlight), "highlight:bm-1")
        XCTAssertEqual(SpotlightItemBuilder.parse(identifier: "highlight:bm-1"), highlight)
    }

    func testParseRejectsJunk() {
        XCTAssertNil(SpotlightItemBuilder.parse(identifier: ""))
        XCTAssertNil(SpotlightItemBuilder.parse(identifier: "episode:"))
        XCTAssertNil(SpotlightItemBuilder.parse(identifier: "podcast:x"))
        XCTAssertNil(SpotlightItemBuilder.parse(identifier: "ep-1"))
    }

    // MARK: - Episode items

    func testEpisodeItemCarriesMetadata() {
        let published = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = SpotlightItemBuilder.EpisodeMetadata(
            uuid: "ep-1",
            title: "The Interest Rates Argument",
            podcastTitle: "Economics Weekly",
            episodeDescription: "A long chat about rates.",
            publishedDate: published,
            duration: 3600
        )
        let item = SpotlightItemBuilder.episodeItem(metadata)

        XCTAssertEqual(item.uniqueIdentifier, "episode:ep-1")
        XCTAssertEqual(item.domainIdentifier, SpotlightItemBuilder.episodeDomain)
        XCTAssertEqual(item.attributeSet.title, "The Interest Rates Argument")
        XCTAssertEqual(item.attributeSet.containerTitle, "Economics Weekly")
        XCTAssertEqual(item.attributeSet.contentDescription, "A long chat about rates.")
        XCTAssertEqual(item.attributeSet.duration, 3600)
        XCTAssertEqual(item.attributeSet.contentCreationDate, published)
        XCTAssertEqual(item.attributeSet.keywords, ["Economics Weekly"])
        XCTAssertNil(item.attributeSet.textContent)
        XCTAssertNotNil(item.expirationDate)
    }

    func testEpisodeItemAttachesTranscriptText() {
        let metadata = SpotlightItemBuilder.EpisodeMetadata(uuid: "ep-1", title: "T")
        let item = SpotlightItemBuilder.episodeItem(metadata, transcriptText: "spoken words here")
        XCTAssertEqual(item.attributeSet.textContent, "spoken words here")
    }

    func testLongDescriptionIsCapped() {
        let metadata = SpotlightItemBuilder.EpisodeMetadata(
            uuid: "ep-1",
            title: "T",
            episodeDescription: String(repeating: "x", count: 1000)
        )
        let item = SpotlightItemBuilder.episodeItem(metadata)
        XCTAssertEqual(item.attributeSet.contentDescription?.count, 300)
    }

    // MARK: - Text content trimming

    func testTrimmedTextContentRespectsByteBudgetAtSegmentBoundaries() {
        let segments = ["alpha", "beta", "gamma", "delta"]
        // "alpha beta" = 10 bytes; adding " gamma" (6 more) exceeds 12.
        XCTAssertEqual(SpotlightItemBuilder.trimmedTextContent(segments, maxBytes: 12), "alpha beta")
        XCTAssertEqual(SpotlightItemBuilder.trimmedTextContent(segments, maxBytes: 4), "")
        XCTAssertEqual(SpotlightItemBuilder.trimmedTextContent([], maxBytes: 100), "")
    }

    func testTrimmedTextContentCountsMultibyteCharactersAsBytes() {
        // Each emoji is 4 UTF-8 bytes: two segments = 9 bytes with the joiner.
        let segments = ["🎙", "🎙", "🎙"]
        XCTAssertEqual(SpotlightItemBuilder.trimmedTextContent(segments, maxBytes: 9), "🎙 🎙")
    }

    func testTrimmedTextContentNeverSplitsASegment() {
        let segments = [String(repeating: "a", count: 100), "tail"]
        let trimmed = SpotlightItemBuilder.trimmedTextContent(segments, maxBytes: 50)
        XCTAssertEqual(trimmed, "", "a segment that doesn't fit is dropped whole, never split")
    }
}
