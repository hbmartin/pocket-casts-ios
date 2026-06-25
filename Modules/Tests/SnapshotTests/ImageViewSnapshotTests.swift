#if canImport(UIKit)
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

import EndOfYear

final class ImageViewSnapshotTests: XCTestCase {
    private let layout = SwiftUISnapshotLayout.fixed(width: 80, height: 80)

    @MainActor
    func testRendersProvidedImage() {
        assertThemedSnapshots(
            of: ImageView(image: fixtureImage)
                .frame(width: 64, height: 64)
                .background(Color(red: 0.96, green: 0.96, blue: 0.96)),
            layout: layout
        )
    }

    @MainActor
    func testEmptyImageViewMaintainsLayout() {
        assertThemedSnapshots(
            of: ImageView()
                .frame(width: 64, height: 64)
                .background(Color(red: 0.96, green: 0.96, blue: 0.96)),
            layout: layout
        )
    }

    private var fixtureImage: UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { renderer in
            let context = renderer.cgContext

            context.setFillColor(UIColor(red: 0.84, green: 0.06, blue: 0.12, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))

            context.setFillColor(UIColor(red: 0.12, green: 0.21, blue: 0.34, alpha: 1).cgColor)
            context.fill(CGRect(x: 8, y: 8, width: 48, height: 48))

            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(4)
            context.strokeEllipse(in: CGRect(x: 18, y: 18, width: 28, height: 28))
        }
    }
}
#endif
