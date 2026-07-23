import UIKit
import XCTest

@testable import podcasts

@MainActor
final class OptionsPickerRootControllerTests: XCTestCase {
    func testOverlayKeepsActionsInsideSafeAreaAndBackgroundAtScreenEdge() throws {
        let attachment = try makeAttachedController()
        defer { attachment.restore() }

        let scrollView = try XCTUnwrap(
            attachment.controller.view.subviews.first {
                $0.accessibilityIdentifier == "optionsPicker.scrollView"
            } as? UIScrollView
        )
        let cardBackgroundView = try XCTUnwrap(
            attachment.controller.view.subviews.first {
                $0.accessibilityIdentifier == "optionsPicker.cardBackground"
            }
        )
        let actionView = try XCTUnwrap(
            scrollView.allDescendants.first { $0 is SimpleActionView }
        )
        let actionFrame = actionView.convert(actionView.bounds, to: attachment.controller.view)
        let safeAreaBottom = attachment.controller.view.safeAreaLayoutGuide.layoutFrame.maxY

        XCTAssertGreaterThan(attachment.controller.view.safeAreaInsets.bottom, 0)
        XCTAssertEqual(scrollView.frame.maxY, safeAreaBottom, accuracy: 0.5)
        XCTAssertLessThanOrEqual(actionFrame.maxY, safeAreaBottom)
        XCTAssertEqual(cardBackgroundView.frame.minY, scrollView.frame.minY, accuracy: 0.5)
        XCTAssertEqual(cardBackgroundView.frame.maxY, attachment.controller.view.bounds.maxY, accuracy: 0.5)
    }

    func testNativeSheetHidesOverlayBackground() throws {
        let controller = makeController()

        controller.configureForSheetPresentation()

        let cardBackgroundView = try XCTUnwrap(
            controller.view.subviews.first {
                $0.accessibilityIdentifier == "optionsPicker.cardBackground"
            }
        )
        XCTAssertTrue(cardBackgroundView.isHidden)
    }

    private func makeAttachedController() throws -> ControllerAttachment {
        let windowScene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let previousKeyWindow = windowScene.keyWindow
        let window = UIWindow(windowScene: windowScene)
        let controller = makeController()
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        controller.animateIn()
        UIView.setAnimationsEnabled(animationsWereEnabled)
        controller.view.layoutIfNeeded()

        return ControllerAttachment(
            controller: controller,
            window: window,
            previousKeyWindow: previousKeyWindow
        )
    }

    private func makeController() -> OptionsPickerRootController {
        let controller = OptionsPickerRootController()
        controller.setup(
            title: nil,
            iconTintStyle: .primaryIcon01,
            colors: .init(title: .black, background: .white)
        )
        controller.addAction(action: OptionAction(label: "Action", icon: nil, action: {}))
        return controller
    }
}

@MainActor
private struct ControllerAttachment {
    let controller: OptionsPickerRootController
    let window: UIWindow
    let previousKeyWindow: UIWindow?

    func restore() {
        window.isHidden = true
        previousKeyWindow?.makeKey()
    }
}

private extension UIView {
    var allDescendants: [UIView] {
        subviews + subviews.flatMap(\.allDescendants)
    }
}
