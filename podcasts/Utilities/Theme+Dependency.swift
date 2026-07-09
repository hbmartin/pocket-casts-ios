import Combine
import Dependencies
import PocketCastsServer
import UIKit

/// Consumer-facing surface of `Theme`, registered in the dependency container as `\.theme`
/// so consumers can be tested with a mock instead of the shared singleton. Covers the members
/// call sites use today; extend it as adoption grows. The generated color accessors
/// (`Theme+Color.swift`) are defined on this protocol, so converted call sites keep the
/// `theme.primaryUi02` spelling.
///
/// SwiftUI views keep using the concrete `Theme` via `@EnvironmentObject` — `ObservableObject`
/// environment injection needs the concrete class; this seam is for everything else.
///
/// `@MainActor` because the production conformer (`Theme`) is main-actor isolated; the
/// isolation makes the protocol implicitly usable as a `Sendable` dependency value.
@MainActor
protocol Theming: AnyObject, Sendable {
    /// The current theme, readable from any thread.
    nonisolated var nonisolatedActiveTheme: ThemeType { get }

    /// Publisher for theme changes.
    nonisolated var activeThemePublisher: AnyPublisher<ThemeType, Never> { get }

    var activeTheme: ThemeType { get set }

    func toggleTheme()
    func toggleDarkLightThemeAnimated(topLevelView: UIView, originView: UIView)
}

extension Theme: Theming { }

nonisolated enum ThemeKey: DependencyKey {
    static let liveValue: any Theming = Theme.sharedTheme
}

nonisolated extension DependencyValues {
    var theme: any Theming {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
