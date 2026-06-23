#if canImport(UIKit)
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

/// Asserts an image snapshot of a SwiftUI view across a matrix of appearance and Dynamic Type
/// traits, recording one reference image per combination.
///
/// Each combination is written to a separate, suffixed reference image (e.g. `…-dark-XXXL`) under
/// the test file's `__Snapshots__` directory, so an unexpected change in any single appearance is
/// reported on its own.
///
/// Recording is controlled by `swift-snapshot-testing`'s standard `SNAPSHOT_TESTING_RECORD`
/// environment variable (e.g. `SNAPSHOT_TESTING_RECORD=all`) — the same mechanism already used by
/// the GRDB macro tests — so this helper deliberately does not set a record mode itself.
///
/// Reference images must be recorded on a fixed Simulator/OS configuration (the one CI pins via
/// `IOS_SIMULATOR_RUNTIME_VERSION`); images recorded on a different device/OS will not match.
///
/// - Note: `sizeCategories` only changes output for views that contain text or otherwise honor the
///   content size category. For purely geometric views, leave it at the default to avoid recording
///   redundant, identical baselines.
func assertThemedSnapshots<V: SwiftUI.View>(
    of view: @autoclosure () -> V,
    layout: SwiftUISnapshotLayout,
    colorSchemes: [UIUserInterfaceStyle] = [.light, .dark],
    sizeCategories: [UIContentSizeCategory] = [.large],
    precision: Float = 1,
    // A small perceptual tolerance absorbs sub-pixel anti-aliasing differences between machines
    // without masking real regressions. Tune per view if a snapshot proves flaky.
    perceptualPrecision: Float = 0.98,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) {
    for style in colorSchemes {
        for sizeCategory in sizeCategories {
            let traits = UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: style),
                UITraitCollection(preferredContentSizeCategory: sizeCategory),
            ])

            assertSnapshot(
                of: view(),
                as: .image(
                    precision: precision,
                    perceptualPrecision: perceptualPrecision,
                    layout: layout,
                    traits: traits
                ),
                named: "\(style.snapshotName)-\(sizeCategory.snapshotName)",
                file: file,
                testName: testName,
                line: line
            )
        }
    }
}

private extension UIUserInterfaceStyle {
    var snapshotName: String {
        switch self {
        case .light: return "light"
        case .dark: return "dark"
        case .unspecified: return "unspecified"
        @unknown default: return "unknown"
        }
    }
}

private extension UIContentSizeCategory {
    /// Trims the verbose `UICTContentSizeCategory…` prefix so file names stay readable
    /// (e.g. `UICTContentSizeCategoryL` -> `L`, `…AccessibilityXXXL` -> `AccessibilityXXXL`).
    var snapshotName: String {
        rawValue.replacingOccurrences(of: "UICTContentSizeCategory", with: "")
    }
}
#endif
