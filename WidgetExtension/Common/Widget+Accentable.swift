import SwiftUI
import WidgetKit

extension View {
    @ViewBuilder
    func backwardWidgetAccentable(_ accentable: Bool = true) -> some View {
        self.widgetAccentable(accentable)
    }
}

extension Image {
    @ViewBuilder
    func backwardWidgetAccentedRenderingMode(_ isAccentedRenderingMode: Bool = true) -> some View {
        self.widgetAccentedRenderingMode(isAccentedRenderingMode ? .accented : .fullColor)
    }

    @ViewBuilder
    func backwardWidgetAccentedDesaturatedRenderingMode() -> some View {
        self.widgetAccentedRenderingMode(.accentedDesaturated)
    }

    @ViewBuilder
    func backwardWidgetFullColorRenderingMode() -> some View {
        backwardWidgetAccentedRenderingMode(false)
    }
}

extension EnvironmentValues {
    var isAccentedRenderingMode: Bool {
        get {
            widgetRenderingMode == .accented
        }
    }
}

private enum AccentedWidgetKey: EnvironmentKey {
    static let defaultValue = false
}
