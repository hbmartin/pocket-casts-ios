import XCTest
@testable import PocketCastsUtils

final class ComparableExtensionTests: XCTestCase {

    // MARK: - clamped(to: Range)

    func testClampedToHalfOpenRange() {
        XCTAssertEqual(5.clamped(to: 0..<10), 5, "value inside the range is unchanged")
        XCTAssertEqual((-1).clamped(to: 0..<10), 0, "below the lower bound clamps up")
        XCTAssertEqual(0.clamped(to: 0..<10), 0, "the lower bound is allowed")
        XCTAssertEqual(15.clamped(to: 0..<10), 10, "above the (exclusive) upper bound clamps to it")
    }

    func testClampedToClosedRange() {
        XCTAssertEqual(5.clamped(to: 0...10), 5)
        XCTAssertEqual((-1).clamped(to: 0...10), 0)
        XCTAssertEqual(10.clamped(to: 0...10), 10, "the closed upper bound is allowed")
        XCTAssertEqual(15.clamped(to: 0...10), 10)
    }

    func testClampedWorksForDoubles() {
        XCTAssertEqual(1.5.clamped(to: 0.0...1.0), 1.0)
        XCTAssertEqual((-0.25).clamped(to: 0.0...1.0), 0.0)
        XCTAssertEqual(0.5.clamped(to: 0.0...1.0), 0.5)
    }

    // MARK: - betweenOrClamped

    func testBetweenOrClampedReturnsValueWhenStrictlyInside() {
        XCTAssertEqual(5.betweenOrClamped(to: 0..<10), 5)
        XCTAssertEqual(5.betweenOrClamped(to: 0...10), 5)
    }

    func testBetweenOrClampedClampsAtOrOutsideBounds() {
        // Bounds are not "strictly inside", so they clamp.
        XCTAssertEqual(0.betweenOrClamped(to: 0..<10), 0)
        XCTAssertEqual(10.betweenOrClamped(to: 0..<10), 10)
        XCTAssertEqual((-3).betweenOrClamped(to: 0..<10), 0)
        XCTAssertEqual(42.betweenOrClamped(to: 0...10), 10)
    }
}
