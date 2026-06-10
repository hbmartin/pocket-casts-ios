@testable import podcasts
import UIKit
import XCTest

@MainActor
final class NowPlayingAnimationViewTests: XCTestCase {
    func testRestartsAnimationsAfterForegroundingWhileAttached() throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion disables equalizer animations.")

        let attachment = makeAttachedView()
        let view = attachment.view

        view.animating = true
        XCTAssertTrue(view.hasAnimationsOnEachBar)

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertFalse(view.hasAnimationsOnAnyBar)

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(view.hasAnimationsOnEachBar)
    }

    func testDoesNotStartAnimationsWhileDetached() throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion disables equalizer animations.")

        let view = NowPlayingAnimationView(frame: CGRect(x: 0, y: 0, width: 30, height: 20))

        view.animating = true
        XCTAssertFalse(view.hasAnimationsOnAnyBar)

        let attachment = attach(view)
        XCTAssertNotNil(attachment.view.window)
        XCTAssertTrue(view.hasAnimationsOnEachBar)

        view.removeFromSuperview()
        XCTAssertNil(view.window)
        XCTAssertFalse(view.hasAnimationsOnAnyBar)

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(view.hasAnimationsOnAnyBar)
    }

    private func makeAttachedView() -> (view: NowPlayingAnimationView, window: UIWindow) {
        let view = NowPlayingAnimationView(frame: CGRect(x: 0, y: 0, width: 30, height: 20))
        return attach(view)
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
        barLayers.contains { $0.animationKeys()?.isEmpty == false }
    }

    var hasAnimationsOnEachBar: Bool {
        barLayers.count == 3 && barLayers.allSatisfy { $0.animationKeys()?.isEmpty == false }
    }

    private var barLayers: [CALayer] {
        layer.sublayers ?? []
    }
}
