import XCTest
@testable import PocketCastsServer

/// Exponential-ish backoff used by podcast-refresh polling: tries 1-2 wait 2s, tries 3-6 wait 5s,
/// try 7 waits 10s, and anything else returns -1 (stop polling).
final class IntPollWaitingTimeTests: XCTestCase {

    func testEarlyTriesWaitTwoSeconds() {
        XCTAssertEqual(1.pollWaitingTime, 2)
        XCTAssertEqual(2.pollWaitingTime, 2)
    }

    func testMiddleTriesWaitFiveSeconds() {
        XCTAssertEqual(3.pollWaitingTime, 5)
        XCTAssertEqual(4.pollWaitingTime, 5)
        XCTAssertEqual(5.pollWaitingTime, 5)
        XCTAssertEqual(6.pollWaitingTime, 5)
    }

    func testFinalTryWaitsTenSeconds() {
        XCTAssertEqual(7.pollWaitingTime, 10)
    }

    func testOutOfRangeTriesStopPolling() {
        XCTAssertEqual(0.pollWaitingTime, -1)
        XCTAssertEqual(8.pollWaitingTime, -1)
        XCTAssertEqual((-1).pollWaitingTime, -1)
    }
}
