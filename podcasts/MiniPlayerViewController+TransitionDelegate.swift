import Foundation
import PocketCastsUtils

extension MiniPlayerViewController: UIViewControllerTransitioningDelegate {
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard let fullPlayer = dismissed as? PlayerContainerViewController else {
            return nil
        }

        return PlayerZoomAnimator(
            isPresenting: false,
            fullPlayer: fullPlayer,
            miniPlayer: self,
            interactiveVelocity: fullPlayer.dismissVelocity
        )
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard let fullPlayer = presented as? PlayerContainerViewController else {
            return nil
        }

        let presentVelocity = pendingPresentVelocity
        pendingPresentVelocity = 0

        // Blank the player view before UIKit can position and render it
        // at its final frame — otherwise the first render shows the
        // fully-opaque player flashing in behind the panel.
        fullPlayer.loadViewIfNeeded()
        fullPlayer.view.alpha = 0
        return PlayerZoomAnimator(
            isPresenting: true,
            fullPlayer: fullPlayer,
            miniPlayer: self,
            interactiveVelocity: presentVelocity
        )
    }
}
