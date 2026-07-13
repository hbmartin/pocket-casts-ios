import PocketCastsServer
import PocketCastsUtils
import UIKit
import XCTest

@testable import podcasts

/// Structural tests for the data-driven theme colour table that backs the generated
/// `ThemeColor` accessors (see scripts/themes/generate_themes.rb and Theme/ThemeColors.json).
final class ThemeColorTableTests: XCTestCase {
    /// Every simple token resolves for every theme without hitting the missing-colour
    /// fallback. The parameterized podcast*/playerBackground*/playerHighlight*/filter*
    /// families are generated Swift with exhaustive switches, so the table covers the
    /// remaining ThemeStyle cases.
    func testEveryTokenResolvesForEveryTheme() {
        let tokens = ThemeColorTable.allTokens
        // 111 simple tokens x 9 themes; update the count when theme.csv gains or loses tokens.
        XCTAssertEqual(tokens.count, 111)
        XCTAssertEqual(ThemeType.allCases.count, 9)

        for token in tokens {
            for theme in ThemeType.allCases {
                XCTAssertNotNil(ThemeColorTable.lookup(token, for: theme), "Missing colour for token \(token) in theme \(theme)")
            }
        }
    }

    func testUnknownTokenIsNotInTable() {
        XCTAssertNil(ThemeColorTable.lookup("notARealToken", for: .light))
    }

    /// Spot-checks copied straight from scripts/themes/theme.csv.
    func testKnownColorLiterals() {
        XCTAssertEqual(ThemeColorTable.color("primaryUi01", for: .light), UIColor(hex: "#FFFFFF"))
        XCTAssertEqual(ThemeColorTable.color("primaryUi01", for: .dark), UIColor(hex: "#292B2E"))
        XCTAssertEqual(ThemeColorTable.color("primaryUi01Active", for: .classic), UIColor(hex: "#F7F9FA"))
        XCTAssertEqual(ThemeColorTable.color("primaryText02", for: .electric), UIColor(hex: "#21ADDB"))
        XCTAssertEqual(ThemeColorTable.color("support05", for: .contrastDark), UIColor(hex: "#FF6557"))
        XCTAssertEqual(ThemeColorTable.color("category19", for: .rosé), UIColor(hex: "#5036AA"))
    }

    /// Tokens with a CSV opacity keep the exact alpha the old generated
    /// `.withAlphaComponent(...)` constants used.
    func testAlphaTokensKeepAlpha() {
        XCTAssertEqual(ThemeColorTable.color("primaryUi05", for: .extraDark), UIColor(hex: "#393A3C").withAlphaComponent(0.5))
        XCTAssertEqual(ThemeColorTable.color("veil", for: .rosé), UIColor(hex: "#f2ccc7").withAlphaComponent(0.75))
        XCTAssertEqual(ThemeColorTable.color("primaryField01", for: .electric), UIColor(hex: "#3FD2E6").withAlphaComponent(0.09))

        XCTAssertEqual(ThemeColorTable.color("primaryUi05", for: .extraDark).cgColor.alpha, 0.5)
    }

    /// The generated ThemeColor accessors route through the table.
    func testThemeColorAccessorsMatchTable() {
        XCTAssertEqual(ThemeColor.primaryUi01(for: .light), ThemeColorTable.color("primaryUi01", for: .light))
        XCTAssertEqual(ThemeColor.veil(for: .dark), UIColor(hex: "#000000").withAlphaComponent(0.5))
    }
}
