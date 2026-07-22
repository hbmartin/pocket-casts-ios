import UIKit
import XCTest
@testable import podcasts

@MainActor
final class SocialShareCardsTests: XCTestCase {
    func testPopoverUsesProvidedBarButtonItem() throws {
        let presenter = UIViewController()
        let activity = UIActivityViewController(activityItems: ["Share"], applicationActivities: nil)
        let popover = try XCTUnwrap(activity.popoverPresentationController)
        let barButtonItem = UIBarButtonItem(systemItem: .action)

        SocialShareCards.configurePopover(popover,
                                          presenter: presenter,
                                          barButtonItem: barButtonItem)

        XCTAssertTrue(popover.barButtonItem === barButtonItem)
    }

    func testPopoverFallsBackToCenteredSourceRectangle() throws {
        let presenter = UIViewController()
        presenter.view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        let activity = UIActivityViewController(activityItems: ["Share"], applicationActivities: nil)
        let popover = try XCTUnwrap(activity.popoverPresentationController)

        SocialShareCards.configurePopover(popover,
                                          presenter: presenter,
                                          barButtonItem: nil)

        XCTAssertTrue(popover.sourceView === presenter.view)
        XCTAssertEqual(popover.sourceRect, CGRect(x: 160, y: 240, width: 0, height: 0))
        XCTAssertTrue(popover.permittedArrowDirections.isEmpty)
    }
}
