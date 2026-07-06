import Foundation
import WidgetKit

/// Immutable references to thread-safe services.
nonisolated final class WidgetAnalytics: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let analytics: Analytics

    init(userDefaults: UserDefaults = UserDefaults.standard,
         analytics: Analytics = .shared) {
        self.userDefaults = userDefaults
        self.analytics = analytics
    }

    func track() {
        let initialWidgets = userDefaults.dictionary(forKey: "installed-widgets") as? [String: Bool] ?? [String: Bool]()

        WidgetCenter.shared.getCurrentConfigurations { [self] widgetInfos in
            guard case .success(let infos) = widgetInfos else { return }

            // Local to the callback so nothing mutable crosses into concurrent code
            var previousWidgets = initialWidgets
            var currentWidgets: [String] = []

            // Track installed widgets
            infos.forEach { widget in
                let installed = previousWidgets[widgetKey(widget)] ?? false
                currentWidgets.append(widgetKey(widget))
                if !installed {
                    Analytics.track(.widgetInstalled, properties: ["kind": widget.kind, "family": "\(widget.family)"])
                    previousWidgets[widgetKey(widget)] = true
                }
            }

            // Track uninstalled widgets
            let uninstalledWidgets = previousWidgets.filter { !currentWidgets.contains($0.key) }
            uninstalledWidgets.forEach { widget in
                let components = widget.key.split(separator: "$")
                if let kind = components[safe: 1], let family = components[safe: 2] {
                    Analytics.track(.widgetUninstalled, properties: ["kind": kind, "family": "\(family)"])
                }
                previousWidgets.removeValue(forKey: widget.key)
            }

            userDefaults.set(previousWidgets, forKey: "installed-widgets")
        }
    }

    private func widgetKey(_ widget: WidgetInfo) -> String {
        return "widget$\(widget.kind)$\(widget.family)"
    }
}
