@testable import podcasts
import UIKit
import XCTest

@MainActor
final class NowPlayingAnimationViewTests: XCTestCase {
    // Isolated centre so posting lifecycle notifications only reaches the view
    // under test, not every observer in the test host app.
    private let notificationCenter = NotificationCenter()

    func testRestartsAnimationsAfterForegroundingWhileAttached() throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion disables equalizer animations.")

        let attachment = makeAttachedView()
        let view = attachment.view

        view.animating = true
        XCTAssertTrue(view.hasAnimationsOnEachBar)

        notificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertFalse(view.hasAnimationsOnAnyBar)

        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(view.hasAnimationsOnEachBar)
    }

    func testDoesNotStartAnimationsWhileDetached() throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion disables equalizer animations.")

        let view = makeView()

        view.animating = true
        XCTAssertFalse(view.hasAnimationsOnAnyBar)

        let attachment = attach(view)
        XCTAssertNotNil(attachment.view.window)
        XCTAssertTrue(view.hasAnimationsOnEachBar)

        view.removeFromSuperview()
        XCTAssertNil(view.window)
        XCTAssertFalse(view.hasAnimationsOnAnyBar)

        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(view.hasAnimationsOnAnyBar)
    }

    private func makeView() -> NowPlayingAnimationView {
        NowPlayingAnimationView(frame: CGRect(x: 0, y: 0, width: 30, height: 20), notificationCenter: notificationCenter)
    }

    private func makeAttachedView() -> (view: NowPlayingAnimationView, window: UIWindow) {
        attach(makeView())
    }

    private func attach(_ view: NowPlayingAnimationView) -> (view: NowPlayingAnimationView, window: UIWindow) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.addSubview(view)
        view.layoutIfNeeded()
        return (view, window)
    }
}

private extension NowPlayingAnimationView {
    var hasAnimationsOnAnyBar: Bool {
        bars.contains { $0.animationKeys()?.isEmpty == false }
    }

    var hasAnimationsOnEachBar: Bool {
        !bars.isEmpty && bars.allSatisfy { $0.animationKeys()?.isEmpty == false }
    }
}
