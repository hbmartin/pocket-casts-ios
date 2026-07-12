import SwiftUI

/// Settings → Devices: per audio-route playback rules for recently seen routes
/// (auto-resume on connect, pause on disconnect).
struct DevicesSettingsView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model = DevicesSettingsViewModel()

    var body: some View {
        List {
            if model.routes.isEmpty {
                Section(footer: Text(L10n.settingsDevicesEmpty)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))) {
                    EmptyView()
                }
            } else {
                ForEach(model.routes) { route in
                    DeviceRuleSection(route: route, model: model)
                }

                Section(footer: Text(L10n.settingsDevicesFooter)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))) {
                    EmptyView()
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
        .onAppear { model.refresh() }
    }
}

private struct DeviceRuleSection: View {
    @EnvironmentObject private var theme: Theme

    let route: SeenRoute
    @ObservedObject var model: DevicesSettingsViewModel

    var body: some View {
        Section(
            header: Text(route.displayName)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme)),
            footer: Text(L10n.settingsDevicesLastSeenFormat(route.lastSeen.formatted(.relative(presentation: .named))))
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))) {
            Toggle(L10n.settingsDevicesAutoResume, isOn: Binding(
                get: { model.rule(for: route.identity).autoResumeOnConnect },
                set: { model.setAutoResume($0, for: route.identity) }))
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
            Toggle(L10n.settingsDevicesPauseOnDisconnect, isOn: Binding(
                get: { model.rule(for: route.identity).pauseOnDisconnect },
                set: { model.setPauseOnDisconnect($0, for: route.identity) }))
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
        }
    }
}

@MainActor
final class DevicesSettingsViewModel: ObservableObject {
    @Published private(set) var routes: [SeenRoute] = []
    @Published private var rules: [String: RouteRule] = [:]

    private let store: RouteRulesStore

    init(store: RouteRulesStore = .shared) {
        self.store = store
        refresh()
    }

    func refresh() {
        routes = store.recentRoutes
        rules = Dictionary(uniqueKeysWithValues: routes.map { ($0.identity, store.rule(for: $0.identity)) })
    }

    func rule(for identity: String) -> RouteRule {
        rules[identity] ?? RouteRule()
    }

    func setAutoResume(_ enabled: Bool, for identity: String) {
        var rule = rule(for: identity)
        rule.autoResumeOnConnect = enabled
        save(rule, for: identity)
        Analytics.track(.settingsDeviceRuleChanged, properties: ["rule": "auto_resume_on_connect", "enabled": enabled])
    }

    func setPauseOnDisconnect(_ enabled: Bool, for identity: String) {
        var rule = rule(for: identity)
        rule.pauseOnDisconnect = enabled
        save(rule, for: identity)
        Analytics.track(.settingsDeviceRuleChanged, properties: ["rule": "pause_on_disconnect", "enabled": enabled])
    }

    private func save(_ rule: RouteRule, for identity: String) {
        rules[identity] = rule
        store.setRule(rule, for: identity)
    }
}
