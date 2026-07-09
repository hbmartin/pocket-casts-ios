import Combine
import Foundation
import PocketCastsServer
import UIKit

@testable import podcasts

/// `Theming` test double. Mirrors `Theme`'s storage approach: a lock-guarded snapshot box
/// backs the `nonisolated` requirements so they can be read from any thread, and a
/// thread-safe `CurrentValueSubject` backs the publisher.
///
/// `@MainActor` to match the protocol's isolation (which also supplies the implicit
/// `Sendable` conformance the protocol requires).
@MainActor
final class ThemingMock: Theming {
    /// Lock-guarded mirror of `activeTheme` so the nonisolated requirements can read it.
    nonisolated private let snapshot = MockThemeSnapshotBox()

    // nonisolated(unsafe): Combine subjects are thread-safe; writes go through `activeTheme`.
    nonisolated(unsafe) private let themeSubject: CurrentValueSubject<ThemeType, Never>

    private(set) var toggleThemeCallCount = 0
    private(set) var toggleDarkLightThemeAnimatedCallCount = 0

    init(activeTheme: ThemeType = .light) {
        themeSubject = CurrentValueSubject(activeTheme)
        snapshot.value = activeTheme
    }

    nonisolated var nonisolatedActiveTheme: ThemeType {
        snapshot.value
    }

    nonisolated var activeThemePublisher: AnyPublisher<ThemeType, Never> {
        themeSubject.eraseToAnyPublisher()
    }

    var activeTheme: ThemeType {
        get { snapshot.value }
        set {
            snapshot.value = newValue
            themeSubject.send(newValue)
        }
    }

    func toggleTheme() {
        toggleThemeCallCount += 1
        activeTheme = activeTheme == .dark ? .light : .dark
    }

    func toggleDarkLightThemeAnimated(topLevelView: UIView, originView: UIView) {
        toggleDarkLightThemeAnimatedCallCount += 1
        toggleTheme()
    }
}

/// Test-side copy of `Theme`'s private `ThemeSnapshotBox`: a minimal lock-guarded box for
/// mirroring the active theme to nonisolated readers.
nonisolated private final class MockThemeSnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: ThemeType = .light

    var value: ThemeType {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}
