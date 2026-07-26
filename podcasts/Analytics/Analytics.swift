import Foundation
import PocketCastsUtils
import Synchronization

/// Adapters are registered once at startup (or cleared on sign-out) and read by
/// track(); events fire from any thread by design.
nonisolated final class Analytics: AnalyticsTracking, Sendable {
    static let shared = Analytics()

    private struct State {
        var adapters: [AnalyticsAdapter]?
        var adaptersRegistered = false
        var analyticsAppThemeProvider: (any AnalyticsAppThemeProviding)?
    }

    private let state = Mutex(State())

    // Whether we have adapters registered or not
    var adaptersRegistered: Bool {
        state.withLock { $0.adaptersRegistered }
    }

    func register(adapters: [AnalyticsAdapter]) {
        state.withLock {
            $0.adapters = adapters
            $0.adaptersRegistered = true
        }
        logCurrentAdapters()
    }

    /// Unregisters all the registered adapters, disabling analytics
    func unregister() {
        state.withLock {
            $0.adapters = nil
            $0.adaptersRegistered = false
        }
        logCurrentAdapters()
    }

    static func register(adapters: [AnalyticsAdapter]) {
        Self.shared.register(adapters: adapters)
    }

    static func unregister() {
        Self.shared.unregister()
    }
    var analyticsAppThemeProvider: (any AnalyticsAppThemeProviding)? {
        get { state.withLock { $0.analyticsAppThemeProvider } }
        set { state.withLock { $0.analyticsAppThemeProvider = newValue } }
    }

    static func add(analyticsAppThemeProvider: AnalyticsAppThemeProviding) {
        Self.shared.analyticsAppThemeProvider = analyticsAppThemeProvider
    }

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
        // One snapshot for both; appThemeProperties can sync-hop to the main
        // thread, so it must never be called while holding the lock.
        let (adapters, themeProvider) = state.withLock { ($0.adapters, $0.analyticsAppThemeProvider) }
        if FeatureFlag.appThemePropertiesLogging.enabled {
            themeProvider?.appThemeProperties.forEach { key, value in
                properties[key] = value
            }
        }
        Task { [properties] in
            for adapter in adapters ?? [] {
                await adapter.track(name: eventName, properties: properties)
            }
        }
    }

    fileprivate func logCurrentAdapters() {
#if DEBUG
        let adapters = state.withLock { $0.adapters }
        FileLog.shared.console("Analytics adapters: \(adapters ?? [])")
#endif
    }

    fileprivate func setAdaptersRegisteredStatus(_ value: Bool) {
        state.withLock { $0.adaptersRegistered = value }
        logCurrentAdapters()
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
        Settings.setAnalytics(optOut: false)
        setAdaptersRegisteredStatus(false)
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        appDelegate?.configureTelemetryDeck()
        appDelegate?.setupAnalytics()
        Analytics.track(.analyticsOptIn)
    }

    @MainActor func refreshRegistered() {
        if Settings.analyticsOptOut() {
            Analytics.unregister()
        }
        (UIApplication.shared.delegate as? AppDelegate)?.setupAnalytics()
        FileLog.shared.addMessage("Analytics: Refreshed Registered Adapters")
        logCurrentAdapters()
    }
}

// MARK: - Protocols

/// Seam for injecting a test double where an `Analytics` instance is consumed.
/// Deliberately not Sendable-refined: consumers hold it inside their own
/// isolation (e.g. `AppLifecycleAnalytics` is MainActor-isolated), which lets
/// test doubles use a @MainActor isolated conformance.
nonisolated protocol AnalyticsTracking {
    func track(_ event: AnalyticsEvent, properties: [String: Sendable]?)
}

nonisolated extension AnalyticsTracking {
    func track(_ event: AnalyticsEvent) {
        track(event, properties: nil)
    }
}

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
