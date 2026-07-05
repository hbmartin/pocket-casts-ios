import Foundation

protocol AnalyticsAppThemeProviding {
    var appThemeProperties: [String: Sendable] { get }
}

struct AnalyticsAppThemeProvider: AnalyticsAppThemeProviding {
    var appThemeProperties: [String: Sendable] {
        // Theme state is main-actor; analytics can ask for these properties from
        // any thread, so bridge synchronously (previously this read theme state
        // off-main unguarded)
        if Thread.isMainThread {
            MainActor.assumeIsolated { Self.currentProperties() }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated { Self.currentProperties() }
            }
        }
    }

    @MainActor
    private static func currentProperties() -> [String: Sendable] {
        return [
            "theme_selected": Theme.sharedTheme.activeTheme.analyticsDescription,
            "theme_dark_preference": Theme.preferredDarkTheme().analyticsDescription,
            "theme_light_preference": Theme.preferredLightTheme().analyticsDescription,
            "theme_use_system_settings": Settings.shouldFollowSystemTheme()
        ]
    }
}
