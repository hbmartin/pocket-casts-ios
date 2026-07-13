import XCTest

@testable import podcasts

@MainActor
final class SeekAccelerationTrackerTests: XCTestCase {
    private let base: TimeInterval = 45
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    func testFirstTapReturnsBaseAmount() {
        var tracker = SeekAccelerationTracker()

        XCTAssertEqual(tracker.amount(for: .forward, baseAmount: base, now: start), base)
    }

    func testRapidSameDirectionTapsDoubleThenQuadruple() {
        var tracker = SeekAccelerationTracker()

        XCTAssertEqual(tracker.amount(for: .forward, baseAmount: base, now: start), base)
        XCTAssertEqual(tracker.amount(for: .forward, baseAmount: base, now: start.addingTimeInterval(0.5)), base * 2)
        XCTAssertEqual(tracker.amount(for: .forward, baseAmount: base, now: start.addingTimeInterval(1.0)), base * 4)
    }

    func testMultiplierIsCappedAtFour() {
        var tracker = SeekAccelerationTracker()

        for tap in 0..<6 {
            _ = tracker.amount(for: .back, baseAmount: base, now: start.addingTimeInterval(Double(tap) * 0.2))
        }

        XCTAssertEqual(tracker.amount(for: .back, baseAmount: base, now: start.addingTimeInterval(1.4)), base * 4, "Streak should never exceed the ×4 cap")
    }

    func testTapExactlyOnWindowBoundaryStillAccelerates() {
        var tracker = SeekAccelerationTracker()

        _ = tracker.amount(for: .forward, baseAmount: base, now: start)

        XCTAssertEqual(tracker.amount(for: .forward, baseAmount: base, now: start.addingTimeInterval(1.5)), base * 2, "A tap exactly `window` after the previous one counts as part of the streak")
    }

    func testTapAfterWindowExpiryResetsToBase() {
        var tracker = SeekAccelerationTracker()

        _ = tracker.amount(for: .forward, baseAmount: base, now: start)
        _ = tracker.amount(for: .forward, baseAmount: base, now: start.addingTimeInterval(0.5))

        XCTAssertEqual(tracker.amount(for: .forward, baseAmount: base, now: start.addingTimeInterval(0.5 + 1.6)), base)
    }

    func testDirectionChangeResetsStreak() {
        var tracker = SeekAccelerationTracker()

        _ = tracker.amount(for: .forward, baseAmount: base, now: start)
        _ = tracker.amount(for: .forward, baseAmount: base, now: start.addingTimeInterval(0.3))

        XCTAssertEqual(tracker.amount(for: .back, baseAmount: base, now: start.addingTimeInterval(0.6)), base, "Changing direction should reset the multiplier")
        XCTAssertEqual(tracker.amount(for: .back, baseAmount: base, now: start.addingTimeInterval(0.9)), base * 2, "The new direction should start its own streak")
    }

    func testResetClearsStreak() {
        var tracker = SeekAccelerationTracker()

        _ = tracker.amount(for: .forward, baseAmount: base, now: start)
        _ = tracker.amount(for: .forward, baseAmount: base, now: start.addingTimeInterval(0.3))

        tracker.reset()

        XCTAssertEqual(tracker.amount(for: .forward, baseAmount: base, now: start.addingTimeInterval(0.6)), base)
    }

    func testAcceleratedAmountUsesTheTappedBaseAmount() {
        var tracker = SeekAccelerationTracker()

        _ = tracker.amount(for: .back, baseAmount: 10, now: start)

        XCTAssertEqual(tracker.amount(for: .back, baseAmount: 10, now: start.addingTimeInterval(0.4)), 20)
    }
}
