import Foundation
import SwiftUI
import UIKit

public enum ViewConstants {
    static let cornerRadius: CGFloat = 5

    // Buttons
    static let buttonCornerRadius = 10.0
    static let buttonStrokeWidth = 2.0
}

extension View {
    func applyDefaultThemeOptions(backgroundOverride: ThemeStyle = .primaryUi01) -> some View {
        modifier(DefaultThemeSettings(backgroundOverride: backgroundOverride))
    }

    func required(_ hasErrored: Bool) -> some View {
        modifier(RequiredInput(hasErrored))
    }

    func themedTextField(style: ThemeStyle = .primaryUi02, hasErrored: Bool = false) -> some View {
        modifier(ThemedTextField(style: style, hasErrored: hasErrored))
    }

    func requiredStyle(_ hasErrored: Bool) -> some View {
        // Applies the same treatment RequiredFieldStyle used to; a TextFieldStyle
        // conformance can't cross into main-actor theme state under Swift 6
        let activeTheme = Theme.sharedTheme.nonisolatedActiveTheme
        return colorScheme(Theme.isDarkTheme() ? .dark : .light)
            .foregroundColor(ThemeColor.primaryText01(for: activeTheme).color)
            .padding(6)
            .required(hasErrored)
            .background(ThemeColor.primaryUi02(for: activeTheme).color.cornerRadius(ViewConstants.cornerRadius))
    }

    func navThemed() -> some View {
        buttonStyle(NavButtonStyle())
    }
}
