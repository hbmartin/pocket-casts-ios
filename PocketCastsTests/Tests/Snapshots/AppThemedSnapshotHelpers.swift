import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import podcasts

/// Asserts an image snapshot of an app-target SwiftUI view across every custom
/// app theme (program item H2) — the SPM helper only varies light/dark traits,
/// but the app's theming flows through `Theme`/`AppTheme`, so each of the nine
/// `ThemeType` cases is its own baseline.
///
/// Recording uses swift-snapshot-testing's standard `SNAPSHOT_TESTING_RECORD`
/// environment variable; record on the CI-pinned Simulator/OS
/// (`IOS_SIMULATOR_RUNTIME_VERSION`) or the images will not match.
@MainActor
func assertAppThemedSnapshots<V: SwiftUI.View>(
    of view: @autoclosure () -> V,
    layout: SwiftUISnapshotLayout,
    themes: [Theme.ThemeType] = Theme.ThemeType.allCases,
    precision: Float = 1,
    perceptualPrecision: Float = 0.98,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) {
    for themeType in themes {
        let traits = UITraitCollection(mutations: { mutableTraits in
            mutableTraits.userInterfaceStyle = themeType.isDark ? .dark : .light
        })

        assertSnapshot(
            of: view().environmentObject(Theme(previewTheme: themeType)),
            as: .image(
                precision: precision,
                perceptualPrecision: perceptualPrecision,
                layout: layout,
                traits: traits
            ),
            named: "\(themeType)",
            file: file,
            testName: testName,
            line: line
        )
    }
}
