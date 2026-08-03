import UserNotifications
import XCTest

@testable import podcasts

final class HighlightNotificationScheduleTests: XCTestCase {
    override func tearDown() {
        NotificationsGroup.speedUpNotifications = false
        super.tearDown()
    }

    func testWeeklyHighlightRequestsUseDistinctOneShotDates() throws {
        NotificationsGroup.speedUpNotifications = false

        let first = try XCTUnwrap(
            NotificationsGroup.fromYourHighlights.trigger(order: 0, notification: .highlightResurfacing)
                as? UNCalendarNotificationTrigger
        )
        let second = try XCTUnwrap(
            NotificationsGroup.fromYourHighlights.trigger(order: 1, notification: .highlightResurfacing)
                as? UNCalendarNotificationTrigger
        )
        let firstDate = try XCTUnwrap(first.nextTriggerDate())
        let secondDate = try XCTUnwrap(second.nextTriggerDate())

        XCTAssertFalse(first.repeats)
        XCTAssertFalse(second.repeats)
        XCTAssertGreaterThan(secondDate.timeIntervalSince(firstDate), 6.9 * 24 * 60 * 60)
    }
}
