#if canImport(UIKit)
import SnapshotTesting
import UIKit
import XCTest

import PocketCastsUtils

final class GradientViewSnapshotTests: XCTestCase {
    private let size = CGSize(width: 160, height: 90)

    @MainActor
    func testInitialGradient() {
        let view = GradientView(
            firstColor: UIColor(red: 0.93, green: 0.08, blue: 0.15, alpha: 1),
            secondColor: UIColor(red: 0.05, green: 0.16, blue: 0.42, alpha: 1)
        )

        assertSnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, size: size)
        )
    }

    @MainActor
    func testUpdatedGradient() {
        let view = GradientView(
            firstColor: UIColor(red: 0.93, green: 0.08, blue: 0.15, alpha: 1),
            secondColor: UIColor(red: 0.05, green: 0.16, blue: 0.42, alpha: 1)
        )

        view.updateColors(
            firstColor: UIColor(red: 0.06, green: 0.58, blue: 0.44, alpha: 1),
            secondColor: UIColor(red: 0.98, green: 0.75, blue: 0.18, alpha: 1)
        )

        assertSnapshot(
            of: view,
            as: .image(perceptualPrecision: 0.98, size: size)
        )
    }
}
#endif
