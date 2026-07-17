import Foundation
import PocketCastsServer
import PocketCastsUtils
import SwiftUI

/// View model for the header view that appears on the Profile tab view
class ProfileHeaderViewModel: ProfileDataViewModel {
    weak var navigationController: UINavigationController? = nil

    init(navigationController: UINavigationController? = nil) {
        super.init()

        self.navigationController = navigationController
    }

    /// Opens the login or account details depending on the users logged in state
    func accountTapped() {
        Analytics.track(.profileAccountButtonTapped)

        guard profile.isLoggedIn else {
            // Show the login flow
            NavigationManager.sharedManager.navigateTo(NavigationManager.onboardingFlow,
                                                       data: ["flow": OnboardingFlow.Flow.loggedOut])
            return
        }

        navigationController?.pushViewController(AccountViewController(), animated: true)
    }

    func shareTapped() {
        guard let presenter = navigationController?.topViewController else { return }

        // Social retarget (docs/Social.md decision 9): joined accounts share
        // their Profile Link; not-yet-joined accounts get the Join flow. The
        // legacy device-local Share Profile card remains the flag-off path.
        if FeatureFlag.socialProfiles.enabled, SyncManager.isUserLoggedIn() {
            if SocialIdentityStore.isJoined, let navigationController {
                SocialCoordinator.pushOwnProfile(on: navigationController)
            } else {
                SocialCoordinator.presentJoinFlow(from: presenter, navigationController: navigationController)
            }
            return
        }

        let shareView = ShareProfileView(
            onOpenPrivacySettings: { [weak self] in
                presenter.dismiss(animated: true) {
                    self?.navigationController?.pushViewController(PrivacySettingsViewController(), animated: true)
                }
            },
            onPresentShareActivity: { [weak presenter] items in
                guard let presented = presenter?.presentedViewController ?? presenter else { return }
                let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
                activityVC.popoverPresentationController?.sourceView = presented.view
                presented.present(activityVC, animated: true)
            }
        )

        let hostingController = PCHostingController(rootView: shareView)
        presenter.present(hostingController, animated: true)
    }
}
