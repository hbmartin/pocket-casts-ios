import Dependencies
import PocketCastsServer
import SwiftUI
import XCTest

@testable import podcasts

@MainActor
final class ThemeDependencyTests: XCTestCase {
    func testDefaultValueIsSharedTheme() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.theme) var theme
            XCTAssertTrue((theme as AnyObject) === Theme.sharedTheme)
        }
    }

    func testOverridingWithMockReflectsThemeChanges() {
        let mock = ThemingMock(activeTheme: .light)
        withDependencies {
            $0.theme = mock
        } operation: {
            @Dependency(\.theme) var theme
            theme.activeTheme = .dark

            XCTAssertEqual(mock.activeTheme, .dark)
            XCTAssertEqual(theme.activeTheme, .dark)
            XCTAssertEqual(theme.nonisolatedActiveTheme, .dark)
            XCTAssertTrue((theme as AnyObject) === mock)
        }
    }

    func testToggleThemeFlipsBetweenLightAndDark() {
        let mock = ThemingMock(activeTheme: .light)
        withDependencies {
            $0.theme = mock
        } operation: {
            @Dependency(\.theme) var theme
            theme.toggleTheme()
            XCTAssertEqual(theme.activeTheme, .dark)

            theme.toggleTheme()
            XCTAssertEqual(theme.activeTheme, .light)
            XCTAssertEqual(mock.toggleThemeCallCount, 2)
        }
    }

    func testPublisherEmitsThemeChanges() {
        let mock = ThemingMock(activeTheme: .light)
        var received: [ThemeType] = []
        let cancellable = mock.activeThemePublisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        withDependencies {
            $0.theme = mock
        } operation: {
            @Dependency(\.theme) var theme
            theme.activeTheme = .dark
        }

        XCTAssertEqual(received, [.light, .dark])
    }

    /// The generated color accessors (`Theme+Color.swift`) are declared on `Theming`, so
    /// they must resolve through the dependency's existential, not just the concrete `Theme`.
    func testColorAccessorsResolveThroughProtocol() {
        let mock = ThemingMock(activeTheme: .dark)
        withDependencies {
            $0.theme = mock
        } operation: {
            @Dependency(\.theme) var theme
            let color: Color = theme.primaryUi01
            XCTAssertEqual(color, AppTheme.color(for: .primaryUi01, theme: mock))
        }
    }
}
