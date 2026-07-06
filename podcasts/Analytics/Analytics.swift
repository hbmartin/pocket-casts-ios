import Foundation
import PocketCastsUtils

/// Adapters are registered once at startup (or cleared on sign-out) and read by
/// track(); events fire from any thread by design.
nonisolated class Analytics: @unchecked Sendable {
    static let shared = Analytics()
    private var adapters: [AnalyticsAdapter]?
#if !APPCLIP && !os(tvOS)
    var analyticsAppThemeProvider: AnalyticsAppThemeProviding?
#endif

    // Whether we have adapters registered or not
    var adaptersRegistered: Bool = false

    static func register(adapters: [AnalyticsAdapter]) {
        Self.shared.adapters = adapters
        Self.shared.setAdaptersRegisteredStatus(true)
    }

    /// Unregisters all the registered adapters, disabling analytics
    static func unregister() {
        Self.shared.adapters = nil
        Self.shared.setAdaptersRegisteredStatus(false)
    }
#if !APPCLIP && !os(tvOS)
    static func add(analyticsAppThemeProvider: AnalyticsAppThemeProviding) {
        Self.shared.analyticsAppThemeProvider = analyticsAppThemeProvider
    }
#endif

    /// Convenience method to call Analytics.track*
    static func track(_ event: AnalyticsEvent, properties: [String: Sendable]? = nil) {
        Self.shared.track(event, properties: properties)
    }

    /// Tracks an event whose name is already normalized.
    ///
    /// Prefer `AnalyticsEvent` for new analytics. This exists so legacy
    /// Firebase-only events can keep their existing names while using the
    /// current analytics adapters.
    static func track(name: String, properties: [String: Sendable]? = nil) {
        Self.shared._track(name, properties: properties)
    }

    func track(_ event: AnalyticsEvent, properties: [String: Sendable]? = nil) {
        _track(event.eventName, properties: properties)
    }

    private func _track(_ eventName: String, properties: [String: Sendable]? = nil) {
        var properties: [String: Sendable] = (properties ?? [:]).mapValues { value -> Sendable in
            if let describable = value as? AnalyticsDescribable {
                return describable.analyticsDescription
            }
            return value
        }
#if !APPCLIP && !os(tvOS)
        if FeatureFlag.appThemePropertiesLogging.enabled {
            analyticsAppThemeProvider?.appThemeProperties.forEach { key, value in
                properties[key] = value
            }
        }
#endif
        Task { [adapters] in
            for adapter in adapters ?? [] {
                await adapter.track(name: eventName, properties: properties)
            }
        }
    }

    private static func logCurrentAdapters() {
#if DEBUG
        FileLog.shared.console("Analytics adapters: \(Self.shared.adapters ?? [])")
#endif
    }

    fileprivate func setAdaptersRegisteredStatus(_ value: Bool) {
        adaptersRegistered = value
        Self.logCurrentAdapters()
    }
}

// MARK: - Analytics + Source

nonisolated extension Analytics {
    static func track(_ event: AnalyticsEvent, source: Sendable, properties: [String: Sendable]? = nil) {
        var sourceProperties = properties ?? [:]
        sourceProperties["source"] = source

        track(event, properties: sourceProperties)
    }
}

// MARK: - Opt out/in

nonisolated extension Analytics {
    @MainActor func optOutOfAnalytics() {
        Analytics.track(.analyticsOptOut)
        Settings.setAnalytics(optOut: true)
        refreshRegistered()
    }

    @MainActor func optInOfAnalytics() {
#if !APPCLIP && !os(tvOS)
        Settings.setAnalytics(optOut: false)
        setAdaptersRegisteredStatus(false)
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        appDelegate?.configureTelemetryDeck()
        appDelegate?.setupAnalytics()
        Analytics.track(.analyticsOptIn)
#endif
    }

    @MainActor func refreshRegistered() {
        if Settings.analyticsOptOut() {
            Analytics.unregister()
        }
#if !APPCLIP && !os(tvOS)
        (UIApplication.shared.delegate as? AppDelegate)?.setupAnalytics()
#endif
        FileLog.shared.addMessage("Analytics: Refreshed Registered Adapters")
        Analytics.logCurrentAdapters()
    }
}

// MARK: - Protocols

/// Allows an object to determine how its described in the context of analytics
nonisolated protocol AnalyticsDescribable {
    var analyticsDescription: String { get }
}

/// Classes can implement this to determine their own logic on how to handle each event
protocol AnalyticsAdapter: Sendable {
    func track(name: String, properties: [String: Sendable]) async
}

// MARK: - Dynamic Event Name

nonisolated extension AnalyticsEvent {
    var eventName: String {
        return rawValue.toSnakeCaseFromCamelCase()
    }
}
