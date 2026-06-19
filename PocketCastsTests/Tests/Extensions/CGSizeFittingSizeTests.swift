import XCTest
@testable import podcasts

/// Pure-logic tests for `CGSize.fitting(aspectRatio:)`, which scales a size down to a target aspect
/// ratio by constraining whichever dimension would otherwise overflow.
final class CGSizeFittingSizeTests: XCTestCase {

    func testFitting_wideSizeToSquare_constrainsWidth() {
        let result = CGSize(width: 200, height: 100).fitting(aspectRatio: CGSize(width: 1, height: 1))
        XCTAssertEqual(result.width, 100, accuracy: 0.0001)
        XCTAssertEqual(result.height, 100, accuracy: 0.0001)
    }

    func testFitting_tallSizeToSquare_constrainsWidthDimension() {
        let result = CGSize(width: 100, height: 200).fitting(aspectRatio: CGSize(width: 1, height: 1))
        XCTAssertEqual(result.width, 100, accuracy: 0.0001)
        XCTAssertEqual(result.height, 100, accuracy: 0.0001)
    }

    func testFitting_squareToWidescreen_constrainsHeight() {
        // Source 1:1 is taller than 16:9, so width is kept and height is reduced.
        let result = CGSize(width: 100, height: 100).fitting(aspectRatio: CGSize(width: 16, height: 9))
        XCTAssertEqual(result.width, 100, accuracy: 0.0001)
        XCTAssertEqual(result.height, 100.0 * 9.0 / 16.0, accuracy: 0.0001)
    }

    func testFitting_preservesTargetAspectRatio() {
        let result = CGSize(width: 640, height: 480).fitting(aspectRatio: CGSize(width: 16, height: 9))
        XCTAssertEqual(result.width / result.height, 16.0 / 9.0, accuracy: 0.0001)
    }
}
