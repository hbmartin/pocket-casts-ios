import XCTest

@testable import podcasts

final class TranscriptSearchHighlightStyleTests: XCTestCase {
    private func colors(showFromEpisode: Bool, isCurrent: Bool) -> (background: UIColor?, foreground: UIColor?) {
        let attributes = TranscriptSearchHighlightStyle.attributes(showFromEpisode: showFromEpisode, isCurrent: isCurrent)
        return (attributes[.backgroundColor] as? UIColor, attributes[.foregroundColor] as? UIColor)
    }

    func testFromEpisodeCurrentMatchUsesSolidInteractiveBackground() {
        let (background, foreground) = colors(showFromEpisode: true, isCurrent: true)
        XCTAssertEqual(background, ThemeColor.primaryInteractive01().withAlphaComponent(1))
        XCTAssertEqual(foreground, ThemeColor.primaryUi01())
    }

    func testFromEpisodeOtherMatchUsesTranslucentInteractiveBackground() {
        let (background, foreground) = colors(showFromEpisode: true, isCurrent: false)
        XCTAssertEqual(background, ThemeColor.primaryInteractive01().withAlphaComponent(0.2))
        XCTAssertEqual(foreground, ThemeColor.primaryInteractive01())
    }

    func testPlayerCurrentMatchKeepsHighContrastColors() {
        let (background, foreground) = colors(showFromEpisode: false, isCurrent: true)
        XCTAssertEqual(background, UIColor.white.withAlphaComponent(1))
        XCTAssertEqual(foreground, UIColor.black)
    }

    func testPlayerOtherMatchKeepsLegacyColors() {
        let (background, foreground) = colors(showFromEpisode: false, isCurrent: false)
        XCTAssertEqual(background, UIColor.white.withAlphaComponent(0.4))
        XCTAssertEqual(foreground, ThemeColor.playerContrast01())
    }

    func testCurrentAndOtherMatchesDifferInBothModes() {
        for showFromEpisode in [true, false] {
            let current = colors(showFromEpisode: showFromEpisode, isCurrent: true)
            let other = colors(showFromEpisode: showFromEpisode, isCurrent: false)
            XCTAssertNotEqual(current.background, other.background)
            XCTAssertNotEqual(current.foreground, other.foreground)
        }
    }
}
