import Foundation
import UIKit

/// Class to adjust scroll insets and scroll indicator depending of mini-player visibility and multi-select being enabled
@MainActor
class InsetAdjuster {

    private var messageTokens = [NotificationCenter.ObservationToken]()

    deinit {
        // Property reads must precede removeObserver(self); after it, deinit may
        // only touch nonisolated state (Swift 6.2 isolated-deinit rule).
        let tokens = messageTokens
        NotificationCenter.default.removeObserver(self)
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    var isMultiSelectEnabled: Bool = false {
        didSet {
            miniPlayerVisibilityDidChange()
        }
    }

    private weak var scrollViewAdjustableToMiniPlayer: UIScrollView?

    func setupInsetAdjustmentsForMiniPlayer(scrollView: UIScrollView) {
        guard scrollViewAdjustableToMiniPlayer == nil else {
            // This method should only be called once for each ViewController
            return
        }
        scrollViewAdjustableToMiniPlayer = scrollView

        messageTokens.append(NotificationCenter.default.addObserver(for: MiniPlayerDidDisappear.self) { [weak self] _ in
            self?.miniPlayerVisibilityDidChange()
        })
        messageTokens.append(NotificationCenter.default.addObserver(for: MiniPlayerDidAppear.self) { [weak self] _ in
            self?.miniPlayerVisibilityDidChange()
        })

        miniPlayerVisibilityDidChange()
    }

    func miniPlayerVisibilityDidChange() {
        guard let scrollView = scrollViewAdjustableToMiniPlayer else {
            return
        }
        scrollView.updateContentInset(multiSelectEnabled: self.isMultiSelectEnabled)
    }
}
