import XCTest

@testable import podcasts

final class ShareLinkQueryParsingTests: XCTestCase {

    func testTimestampOnly() {
        let parsed = ShareLinkQueryParser.timestampAndQuote(from: "social/share/show/abc?t=123")
        XCTAssertEqual(parsed.timestamp, 123)
        XCTAssertNil(parsed.quote)
    }

    func testQuoteOnly() {
        let parsed = ShareLinkQueryParser.timestampAndQuote(from: "social/share/show/abc?q=hello%20world")
        XCTAssertNil(parsed.timestamp)
        XCTAssertEqual(parsed.quote, "hello world")
    }

    func testBothParametersInEitherOrder() {
        let parsed = ShareLinkQueryParser.timestampAndQuote(from: "episode/uuid?q=the%20quote&t=42.5")
        XCTAssertEqual(parsed.timestamp, 42.5)
        XCTAssertEqual(parsed.quote, "the quote")
    }

    func testClipRangeTimestampReadsAsNoTimestamp() {
        // Parity with the original inline parsing: Double("12.5,20") fails.
        let parsed = ShareLinkQueryParser.timestampAndQuote(from: "episode/uuid?t=12.5,20&q=x")
        XCTAssertNil(parsed.timestamp)
        XCTAssertEqual(parsed.quote, "x")
    }

    func testOversizedQuoteIsDropped() {
        let long = String(repeating: "a", count: ShareLinkQueryParser.maxInboundQuoteLength + 1)
        let parsed = ShareLinkQueryParser.timestampAndQuote(from: "e/u?q=\(long)")
        XCTAssertNil(parsed.quote)
    }

    func testWhitespaceOnlyQuoteIsDropped() {
        let parsed = ShareLinkQueryParser.timestampAndQuote(from: "e/u?q=%20%20")
        XCTAssertNil(parsed.quote)
    }

    func testMalformedAndMissingQueries() {
        XCTAssertNil(ShareLinkQueryParser.timestampAndQuote(from: "e/u").timestamp)
        XCTAssertNil(ShareLinkQueryParser.timestampAndQuote(from: "e/u?t=abc").timestamp)
        XCTAssertNil(ShareLinkQueryParser.timestampAndQuote(from: "e/u?q=").quote)
    }
}
