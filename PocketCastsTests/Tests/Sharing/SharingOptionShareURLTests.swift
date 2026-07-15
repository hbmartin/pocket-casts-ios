import XCTest
import PocketCastsDataModel

@testable import podcasts

/// Pins the quote-bearing share URL composition: `t` formatting must stay
/// byte-identical to the plain `shareURL`, and a nil/empty quote must yield
/// exactly the plain string (regression guard for pre-quote links).
@MainActor
final class SharingOptionShareURLTests: XCTestCase {

    private func makeEpisode() -> Episode {
        var episode = Episode()
        episode.uuid = "ep-uuid"
        return episode
    }

    func testNilQuoteYieldsByteIdenticalURL() {
        let option = SharingModal.Option.currentPosition(makeEpisode(), 63.4)
        XCTAssertEqual(option.shareURL(quote: nil), option.shareURL)
        XCTAssertEqual(option.shareURL(quote: "   "), option.shareURL, "nothing survives normalization")
    }

    func testTimestampedCasesAppendAmpersandQ() {
        let episode = makeEpisode()
        let options: [SharingModal.Option] = [
            .currentPosition(episode, 63.0),
            .bookmark(episode, 12.0),
            .clip(episode, 30.0)
        ]
        for option in options {
            let url = option.shareURL(quote: "hello world")
            XCTAssertEqual(url, option.shareURL + "&q=hello%20world")
        }
    }

    func testEpisodeWithoutTimestampAppendsQuestionMarkQ() {
        let option = SharingModal.Option.episode(makeEpisode())
        XCTAssertEqual(option.shareURL(quote: "hi"), option.shareURL + "?q=hi")
    }

    func testClipShareKeepsRangeFormattingAndAppendsQuote() {
        let option = SharingModal.Option.clipShare(makeEpisode(), ClipTime(start: 12.5, end: 20), .large)
        let plain = option.shareURL
        // SignificantDigitsFormatStyle(significantDigits: 4) renders 12.5 as
        // "12.50" — pinning the existing format so quote appending never alters it.
        XCTAssertTrue(plain.contains("?t=12.50,20.00"), "range formatting unchanged, got \(plain)")
        XCTAssertEqual(option.shareURL(quote: "x&y=z"), plain + "&q=x%26y%3Dz")
    }

    func testQuoteTruncatesInURL() {
        let longQuote = Array(repeating: "word", count: 100).joined(separator: " ")
        let url = SharingModal.Option.currentPosition(makeEpisode(), 5).shareURL(quote: longQuote)
        let q = url.components(separatedBy: "&q=").last ?? ""
        XCTAssertLessThanOrEqual(q.removingPercentEncoding?.count ?? .max, ShareQuoteBuilder.maxURLQuoteLength)
    }

    func testShareTextCarriesQuoteAndAttribution() {
        let option = SharingModal.Option.currentPosition(makeEpisode(), 5)
        let text = option.shareText(quote: "the sky is blue")
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.hasPrefix("\u{201C}the sky is blue\u{201D}"))
        XCTAssertNil(option.shareText(quote: nil))
    }
}
