import XCTest

@testable import podcasts

final class ShareQuoteBuilderTests: XCTestCase {

    // MARK: - urlQuote (word-boundary truncation)

    func testShortQuotePassesThroughNormalized() {
        XCTAssertEqual(ShareQuoteBuilder.urlQuote("a  short\n quote"), "a short quote")
    }

    func testLongQuoteTruncatesAtWordBoundary() {
        let word = "seven"
        let quote = Array(repeating: word, count: 60).joined(separator: " ") // 359 chars
        let truncated = ShareQuoteBuilder.urlQuote(quote)

        XCTAssertLessThanOrEqual(truncated.count, ShareQuoteBuilder.maxURLQuoteLength)
        XCTAssertFalse(truncated.hasSuffix(" "), "no trailing separator")
        // Every piece is an intact word — nothing was cut mid-word.
        XCTAssertTrue(truncated.split(separator: " ").allSatisfy { $0 == Substring(word) })
    }

    func testLongQuoteWithoutSpacesHardCuts() {
        let quote = String(repeating: "x", count: 300)
        XCTAssertEqual(ShareQuoteBuilder.urlQuote(quote).count, ShareQuoteBuilder.maxURLQuoteLength)
    }

    func testTruncationNeverSplitsGraphemeClusters() {
        // Family emoji is a multi-scalar grapheme cluster; Character-based
        // truncation must keep each one whole.
        let quote = Array(repeating: "👨‍👩‍👧‍👦👨‍👩‍👧‍👦", count: 120).joined(separator: " ")
        let truncated = ShareQuoteBuilder.urlQuote(quote)
        XCTAssertTrue(truncated.split(separator: " ").allSatisfy { $0 == "👨‍👩‍👧‍👦👨‍👩‍👧‍👦" })
    }

    // MARK: - Percent encoding

    func testEncodingEscapesQuerySplittingCharacters() {
        let encoded = ShareQuoteBuilder.percentEncodedURLQuote("a&b=c?d+e")
        XCTAssertFalse(encoded.contains("&"))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertFalse(encoded.contains("?"))
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertEqual(encoded.removingPercentEncoding, "a&b=c?d+e")
    }

    func testEncodingRoundTripsUnicode() {
        let quote = "„Zölle" + " — " + "金利について 🎙️"
        let encoded = ShareQuoteBuilder.percentEncodedURLQuote(quote)
        XCTAssertEqual(encoded.removingPercentEncoding, quote)
    }
}
