import XCTest

@testable import PocketCastsUtils

final class TimedActionHelperTests: XCTestCase {

    func testTimerIsInvalidInitially() {
        let helper = TimedActionHelper()

        XCTAssertFalse(helper.isTimerValid())
    }

    func testStartTimerFromMainThreadMarksTimerValid() {
        let helper = TimedActionHelper()

        helper.startTimer(for: 60) {}

        XCTAssertTrue(helper.isTimerValid())

        helper.cancelTimer()
    }

    func testStartTimerFromBackgroundThreadMarksTimerValid() {
        let helper = TimedActionHelper()
        let started = expectation(description: "timer started from background thread")

        DispatchQueue.global().async {
            helper.startTimer(for: 60) {}
            started.fulfill()
        }

        // Waiting on the main thread pumps the run loop, servicing the main.sync
        // hop inside startTimer.
        wait(for: [started], timeout: 5)

        XCTAssertTrue(helper.isTimerValid())

        helper.cancelTimer()
    }

    func testCancelTimerMarksTimerInvalid() {
        let helper = TimedActionHelper()
        helper.startTimer(for: 60) {
            XCTFail("Cancelled action should never fire")
        }

        helper.cancelTimer()

        XCTAssertFalse(helper.isTimerValid())
    }

    func testTimerFireRunsActionOnceAndInvalidatesTimer() {
        let helper = TimedActionHelper()
        let fired = expectation(description: "timer fired")
        var fireCount = 0

        helper.startTimer(for: 0.1) {
            fireCount += 1
            fired.fulfill()
        }

        wait(for: [fired], timeout: 5)

        // Spin the run loop briefly to catch any erroneous repeat fire.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

        XCTAssertEqual(fireCount, 1)
        XCTAssertFalse(helper.isTimerValid())
    }

    func testRestartReplacesRunningTimer() {
        let helper = TimedActionHelper()
        let newActionFired = expectation(description: "replacement timer fired")

        helper.startTimer(for: 60) {
            XCTFail("Replaced action should never fire")
        }
        helper.startTimer(for: 0.1) {
            newActionFired.fulfill()
        }

        XCTAssertTrue(helper.isTimerValid())

        wait(for: [newActionFired], timeout: 5)

        XCTAssertFalse(helper.isTimerValid())
    }
}
