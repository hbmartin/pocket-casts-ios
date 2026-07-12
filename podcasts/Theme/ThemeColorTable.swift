import Foundation
import PocketCastsServer
import PocketCastsUtils
import UIKit

/// Runtime lookup table for the simple (non-parameterized) theme colour tokens.
///
/// `scripts/themes/generate_themes.rb` turns `scripts/themes/theme.csv` into
/// `Theme/ThemeColors.json`, and the generated `ThemeColor` accessors resolve their
/// colours here instead of through per-token generated constants. The JSON is parsed
/// once on first use; `UIColor` is immutable, so the parsed storage is safe to read
/// from any thread.
nonisolated enum ThemeColorTable {
    /// token -> ThemeType JSON key -> resolved colour (~1,000 entries).
    private static let colors: [String: [String: UIColor]] = loadColors()

    static func color(_ token: String, for theme: ThemeType) -> UIColor {
        if let color = lookup(token, for: theme) {
            return color
        }

        assertionFailure("Missing theme colour for token \(token) in theme \(theme)")
        return missingTokenFallback
    }

    /// Optional-returning lookup so tests can prove full token coverage without
    /// tripping the missing-colour assertion.
    static func lookup(_ token: String, for theme: ThemeType) -> UIColor? {
        colors[token]?[theme.themeColorsJSONKey]
    }

    /// Every token in the table, for structural tests.
    static var allTokens: [String] {
        Array(colors.keys)
    }

    private static var missingTokenFallback: UIColor {
        #if DEBUG
        .magenta
        #else
        .black
        #endif
    }

    private static func loadColors() -> [String: [String: UIColor]] {
        guard let url = Bundle(for: ThemeColorTableBundleToken.self).url(forResource: "ThemeColors", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] else {
            assertionFailure("ThemeColors.json is missing or malformed")
            return [:]
        }

        var colors = [String: [String: UIColor]](minimumCapacity: root.count)
        for (token, themes) in root {
            var resolved = [String: UIColor](minimumCapacity: themes.count)
            for (themeKey, value) in themes {
                // Entries are either "#RRGGBB" or {"hex": "#RRGGBB", "alpha": 0.5};
                // see generate_themes.rb.
                if let hex = value as? String {
                    resolved[themeKey] = UIColor(hex: hex)
                } else if let entry = value as? [String: Any],
                          let hex = entry["hex"] as? String,
                          let alpha = entry["alpha"] as? Double {
                    resolved[themeKey] = UIColor(hex: hex).withAlphaComponent(alpha)
                } else {
                    assertionFailure("Malformed ThemeColors.json entry for \(token).\(themeKey)")
                }
            }
            colors[token] = resolved
        }
        return colors
    }
}

nonisolated private extension ThemeType {
    /// Key used in ThemeColors.json; the classic theme reads the Classic Light palette.
    var themeColorsJSONKey: String {
        switch self {
        case .light: "light"
        case .dark: "dark"
        case .extraDark: "extraDark"
        case .electric: "electric"
        case .classic: "classic"
        case .indigo: "indigo"
        case .rosé: "rosé"
        case .contrastLight: "contrastLight"
        case .contrastDark: "contrastDark"
        }
    }
}

private final class ThemeColorTableBundleToken {}
