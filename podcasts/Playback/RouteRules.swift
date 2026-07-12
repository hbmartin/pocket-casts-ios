import Foundation

/// Per audio-route playback rules: what should happen when this route connects or disconnects.
nonisolated struct RouteRule: Codable, Equatable, Sendable {
    /// Start playback when this route connects and an episode is loaded but paused.
    var autoResumeOnConnect = false
    /// Pause playback when this route disconnects (the pre-rules hard-wired behavior).
    var pauseOnDisconnect = true
}

/// An audio route the app has seen recently, so it can be offered in the Devices settings screen.
nonisolated struct SeenRoute: Codable, Equatable, Sendable, Identifiable {
    /// Stable route identity: `portType + "|" + portName`.
    let identity: String
    var displayName: String
    var lastSeen: Date

    var id: String { identity }
}

/// Pure decision logic for route changes, separated from AVAudioSession so the decision table
/// (connect/disconnect x rule states) is unit testable.
nonisolated enum RouteChangeDecider {
    enum Event: Equatable, Sendable {
        case connect
        case disconnect
    }

    enum Action: Equatable, Sendable {
        case pause
        case resume
        case noChange
    }

    static func action(for event: Event, rule: RouteRule, isPlaying: Bool, hasCurrentEpisode: Bool) -> Action {
        switch event {
        case .disconnect:
            return rule.pauseOnDisconnect ? .pause : .noChange
        case .connect:
            return (rule.autoResumeOnConnect && !isPlaying && hasCurrentEpisode) ? .resume : .noChange
        }
    }
}

/// Persists per-route playback rules and the recently-seen routes list in UserDefaults as JSON
/// (device-local, deliberately not part of the synced app settings).
@MainActor
final class RouteRulesStore {
    static let shared = RouteRulesStore()

    static let maxRecentRoutes = 10

    private static let rulesKey = "RouteRules.rules"
    private static let recentRoutesKey = "RouteRules.recentRoutes"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Builds the stable identity for a route from its port information.
    nonisolated static func identity(portType: String, portName: String) -> String {
        "\(portType)|\(portName)"
    }

    /// The rule for a route, falling back to the defaults (no auto-resume, pause on disconnect)
    /// when the user hasn't configured this route.
    func rule(for identity: String) -> RouteRule {
        rules[identity] ?? RouteRule()
    }

    func setRule(_ rule: RouteRule, for identity: String) {
        var rules = rules
        if rule == RouteRule() {
            rules.removeValue(forKey: identity)
        } else {
            rules[identity] = rule
        }
        save(rules, forKey: Self.rulesKey)
    }

    /// Records that a route was observed on a route change, keeping the list capped to the most
    /// recently seen routes.
    func noteSeen(identity: String, displayName: String, date: Date = Date()) {
        var routes = recentRoutes.filter { $0.identity != identity }
        routes.append(SeenRoute(identity: identity, displayName: displayName, lastSeen: date))
        routes.sort { $0.lastSeen > $1.lastSeen }
        save(Array(routes.prefix(Self.maxRecentRoutes)), forKey: Self.recentRoutesKey)
    }

    /// Routes observed recently, most recent first.
    var recentRoutes: [SeenRoute] {
        load([SeenRoute].self, forKey: Self.recentRoutesKey) ?? []
    }

    private var rules: [String: RouteRule] {
        load([String: RouteRule].self, forKey: Self.rulesKey) ?? [:]
    }

    private func save(_ value: some Encodable, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
