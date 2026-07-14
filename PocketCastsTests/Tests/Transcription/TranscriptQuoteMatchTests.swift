import XCTest

@testable import podcasts

final class TranscriptQuoteMatchTests: XCTestCase {

    private let transcript = """
    Welcome back to the show.
    Today we are talking about climate change,
    interest rates, and everything in between.
    Thanks for joining us, Alice.
    """

    func testExactQuoteMatchesAcrossLineBreaks() {
        // The outbound quote joined cue texts with single spaces; the transcript
        // has newlines. Whitespace-flexible matching must bridge them.
        let quote = "talking about climate change, interest rates"
        let range = TranscriptQuoteMatcher.range(ofQuote: quote, in: transcript)
        XCTAssertNotNil(range)

        let matched = (transcript as NSString).substring(with: range!)
        XCTAssertTrue(matched.lowercased().hasPrefix("talking about climate"))
    }

    func testMatchIsCaseInsensitive() {
        XCTAssertNotNil(TranscriptQuoteMatcher.range(ofQuote: "WELCOME BACK TO THE SHOW", in: transcript))
    }

    func testTruncatedQuoteFallsBackToPrefix() {
        // Tail words that aren't in the transcript: the 6- and 3-word prefixes
        // still anchor the match.
        let quote = "Today we are talking about climate but then something entirely different happened later"
        XCTAssertNotNil(TranscriptQuoteMatcher.range(ofQuote: quote, in: transcript))
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(TranscriptQuoteMatcher.range(ofQuote: "quantum entanglement basics", in: transcript))
        XCTAssertNil(TranscriptQuoteMatcher.range(ofQuote: "   ", in: transcript))
        XCTAssertNil(TranscriptQuoteMatcher.range(ofQuote: "hello", in: ""))
    }

    func testRegexMetacharactersInQuoteAreEscaped() {
        let text = "the price rose (roughly 3.5%) last week"
        XCTAssertNotNil(TranscriptQuoteMatcher.range(ofQuote: "(roughly 3.5%)", in: text))
    }

    func testShortQuotesMatchWhole() {
        XCTAssertNotNil(TranscriptQuoteMatcher.range(ofQuote: "Alice", in: transcript))
    }
}
