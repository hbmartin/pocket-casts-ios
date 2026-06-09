#if canImport(UIKit)
import SnapshotTesting
import SwiftUI
import XCTest

import EndOfYear

/// Pilot for UI snapshot testing (see `docs/snapshot-testing.md`).
///
/// `CircularProgressView` is a good first candidate: it is a pure, deterministic SwiftUI view with
/// no asynchronous image loading, animation-driven state, or network access, so its rendered output
/// depends only on its inputs and the appearance traits we vary.
///
/// On the first run (or whenever `SNAPSHOT_TESTING_RECORD=all` is set) reference images are written
/// to `__Snapshots__/CircularProgressViewSnapshotTests/` and the assertions fail; commit those
/// images and subsequent runs verify against them.
final class CircularProgressViewSnapshotTests: XCTestCase {
    private let layout = SwiftUISnapshotLayout.fixed(width: 120, height: 120)

    func testCountUpPartialProgress() {
        assertThemedSnapshots(
            of: CircularProgressView(value: 0.67, stroke: Color.blue, strokeWidth: 12),
            layout: layout
        )
    }

    func testCountDownProgress() {
        assertThemedSnapshots(
            of: CircularProgressView(value: 0.25, stroke: Color.red, strokeWidth: 8, direction: .down),
            layout: layout
        )
    }

    func testFullProgress() {
        assertThemedSnapshots(
            of: CircularProgressView(value: 1.0, stroke: Color.green, strokeWidth: 16),
            layout: layout
        )
    }
}
#endif
