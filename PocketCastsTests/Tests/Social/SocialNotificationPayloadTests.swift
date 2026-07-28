import Foundation
import XCTest

@testable import podcasts

final class SocialNotificationPayloadTests: XCTestCase {
    func testIntegerPayloadParsesStringsAndJSONNumbers() {
        let stringValue: Int64? = NotificationsHelper.socialPayloadInteger("12345")
        let numberValue: Int64? = NotificationsHelper.socialPayloadInteger(NSNumber(value: 12345))

        XCTAssertEqual(stringValue, 12345)
        XCTAssertEqual(numberValue, 12345)
    }

    func testIntegerPayloadRejectsFractionsAndOverflow() {
        let fraction: Int64? = NotificationsHelper.socialPayloadInteger(NSNumber(value: 1.5))
        let overflow: Int8? = NotificationsHelper.socialPayloadInteger("128")

        XCTAssertNil(fraction)
        XCTAssertNil(overflow)
    }

    func testSocialSectionVisibilityDoesNotDependOnEnumOrdering() {
        XCTAssertEqual(
            NotificationsViewController.visibleSections(showSocialSection: false),
            NotificationsViewController.Section.allCases.filter { $0 != .social }
        )
        XCTAssertEqual(
            NotificationsViewController.visibleSections(showSocialSection: true),
            NotificationsViewController.Section.allCases
        )
    }
}
