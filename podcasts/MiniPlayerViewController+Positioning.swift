import Foundation
import PocketCastsUtils

extension MiniPlayerViewController {
    func hideMiniPlayer(_ animated: Bool) {
        guard let tabBarController = containingTabController, tabBarController.bottomAccessory != nil else { return }
        tabBarController.setBottomAccessory(nil, animated: animated)
        tabBarController.tabBarMinimizeBehavior = .never
        NotificationCenter.postOnMainThread(notification: Constants.Notifications.miniPlayerDidDisappear)
    }

    func showMiniPlayer() {
        // only show if something is playing
        if PlaybackManager.shared.currentEpisode() == nil { return }

        guard let tabBarController = containingTabController, tabBarController.bottomAccessory == nil else { return }
        let accessory = UITabAccessory(contentView: view)
        tabBarController.setBottomAccessory(accessory, animated: true)
        tabBarController.tabBarMinimizeBehavior = Settings.tabBarMinimizingEnabled ? .onScrollDown : .never
        NotificationCenter.postOnMainThread(notification: Constants.Notifications.miniPlayerDidAppear)
    }

    func openFullScreenPlayer(completion: (() -> Void)? = nil) {
        guard PlaybackManager.shared.currentEpisode() != nil else { return }

        if fullScreenPlayer?.presentingViewController != nil || fullScreenPlayer?.isBeingPresented == true { return }

        aboutToDisplayFullScreenPlayer()

        fullScreenPlayer?.modalPresentationStyle = .custom
        fullScreenPlayer?.transitioningDelegate = self

        guard let fullScreenPlayer else {
            return
        }

        fullScreenPlayer.nowPlayingItem.placeholderArtwork = podcastArtwork.imageView?.image

        playerOpenState = .animating

        presentFromRootController(fullScreenPlayer, animated: true) {
            self.playerOpenState = .open
            self.rootViewController()?.setNeedsStatusBarAppearanceUpdate()
            self.rootViewController()?.setNeedsUpdateOfHomeIndicatorAutoHidden()
            AnalyticsHelper.nowPlayingOpened()
            Analytics.track(.playerShown)
            completion?()
        } failure: {
            self.playerOpenState = .closed
        }
    }

    func closeFullScreenPlayer(completion: (() -> Void)? = nil) {
        if fullScreenPlayer?.presentingViewController == nil || fullScreenPlayer?.isBeingDismissed == true {
            completion?()

            return
        }

        playerOpenState = .animating

        rootViewController()?.dismiss(animated: true) {
            self.finishedWithFullScreenPlayer()
            self.playerOpenState = .closed
            Analytics.track(.playerDismissed)
            completion?()
        }
    }

    private func moveToHiddenBottomPosition() {
        view.transform = CGAffineTransform(translationX: 0, y: desiredHeight())
        view.superview?.layoutIfNeeded()
    }

    private func moveToShownPosition() {
        view.transform = .identity
        view.superview?.layoutIfNeeded()
    }

    /// Re-applies `tabBarMinimizeBehavior` from the current `Settings.tabBarMinimizingEnabled`
    /// so a toggle flip in Appearance takes effect right away while the mini player is showing.
    func applyTabBarMinimizingPreference() {
        guard let tabBarController = containingTabController, tabBarController.bottomAccessory != nil else { return }
        tabBarController.tabBarMinimizeBehavior = Settings.tabBarMinimizingEnabled ? .onScrollDown : .never
    }

    func closeUpNextAndFullPlayer(completion: (() -> Void)? = nil) {
        if fullScreenPlayer != nil {
            closeFullScreenPlayer(completion: {
                completion?()
            })
            return
        }

        if let upNextViewController {
            upNextViewController.dismiss(animated: true, completion: nil)
        }
        completion?()
    }
}
