import PocketCastsServer
import UIKit
import XCTest

@testable import podcasts

/// Exhaustive coverage for `AppTheme.colorForStyle`, which resolves simple styles
/// through `ThemeColorTable` via the generated `ThemeStyle.simpleToken` mapping
/// (see scripts/themes/generate_themes.rb).
final class AppThemeColorForStyleTests: XCTestCase {
    /// The generated mapping splits ThemeStyle into 111 table-backed simple tokens
    /// and 45 parameterized podcast*/playerBackground*/playerHighlight*/filter*
    /// cases; update the counts when theme.csv gains or loses tokens.
    func testSimpleTokenPartitionsThemeStyle() {
        let allStyles = ThemeStyle.allCases
        let simple = allStyles.filter { $0.simpleToken != nil }
        let parameterized = allStyles.filter { $0.simpleToken == nil }

        XCTAssertEqual(allStyles.count, 156)
        XCTAssertEqual(simple.count, 111)
        XCTAssertEqual(parameterized.count, 45)
        XCTAssertEqual(simple.count, ThemeColorTable.allTokens.count)
    }

    /// Every simple token points at a real table entry, so no style can silently
    /// fall through to the missing-colour fallback.
    func testEverySimpleTokenExistsInTable() {
        let tableTokens = Set(ThemeColorTable.allTokens)
        for style in ThemeStyle.allCases {
            guard let token = style.simpleToken else { continue }
            XCTAssertTrue(tableTokens.contains(token), "ThemeStyle.\(style) maps to token \(token) missing from ThemeColors.json")
        }
    }

    /// The parameterized families are exactly the cases with no table token.
    /// (They are never passed to colorForStyle here because it asserts on them.)
    func testParameterizedFamiliesHaveNoToken() {
        for style in ThemeStyle.allCases where style.simpleToken == nil {
            let name = String(describing: style)
            let isParameterizedFamily = name.hasPrefix("podcast")
                || name.hasPrefix("playerBackground")
                || name.hasPrefix("playerHighlight")
                || name.hasPrefix("filter")
            XCTAssertTrue(isParameterizedFamily, "Unexpected non-parameterized style without a token: \(style)")
        }
    }

    /// colorForStyle agrees with ThemeColorTable for every simple style in every
    /// theme when the theme is passed explicitly.
    func testColorForStyleMatchesTableForEveryThemeOverride() {
        for style in ThemeStyle.allCases {
            guard let token = style.simpleToken else { continue }
            for theme in ThemeType.allCases {
                XCTAssertEqual(
                    AppTheme.colorForStyle(style, themeOverride: theme),
                    ThemeColorTable.color(token, for: theme),
                    "Mismatch for \(style) in theme \(theme)"
                )
            }
        }
    }

    /// Regression test for the pre-table behaviour where 48 styles (support*,
    /// contrast*, veil, gradient*, imageFilter*, category*) ignored the caller's
    /// themeOverride and returned the ambient theme's colour instead.
    func testFormerlyOverrideDroppingStylesHonorOverride() {
        // support01 differs between light and dark in theme.csv, so an honored
        // override must produce different colours.
        let light = AppTheme.colorForStyle(.support01, themeOverride: .light)
        let dark = AppTheme.colorForStyle(.support01, themeOverride: .dark)
        XCTAssertNotEqual(light, dark)
        XCTAssertEqual(light, ThemeColorTable.color("support01", for: .light))
        XCTAssertEqual(dark, ThemeColorTable.color("support01", for: .dark))

        XCTAssertEqual(
            AppTheme.colorForStyle(.category07, themeOverride: .contrastDark),
            ThemeColorTable.color("category07", for: .contrastDark)
        )
        XCTAssertEqual(
            AppTheme.colorForStyle(.veil, themeOverride: .rosé),
            ThemeColorTable.color("veil", for: .rosé)
        )
    }
}
