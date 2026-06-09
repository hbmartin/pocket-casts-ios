import Foundation
import PocketCastsServer
import SwiftUI
import PocketCastsDataModel
import PocketCastsUtils

class LoginCoordinator: NSObject, OnboardingModel {
    weak var navigationController: UINavigationController? = nil
    let headerImages: [LoginHeaderImage]
    var isOnboarding: Bool = false

    override init() {
        let maxCount = bundledImages.count
        let bundledImages = bundledImages

        var randomPodcasts = DataManager.sharedManager.allPodcasts(includeUnsubscribed: true)
            // Only return items we have a cached image for
            .filter {
                ImageManager.sharedManager.hasCachedImage(for: $0.uuid, size: .grid)
            }
            // Return a random-ish order
            .shuffled()
            // Limit to the number of bundled images we have
            .prefix(maxCount)
            // Convert the podcasts into the model, we use enumerated because we need the index to map to the placeholder
            .enumerated().map { index, item in
                LoginHeaderImage(podcast: item, imageName: nil, placeholderImageName: bundledImages[index].imageName ?? "")
            }

        // If there aren't enough podcasts in the database, then fill in the missing ones with bundled images
        if randomPodcasts.count < maxCount {
            randomPodcasts.append(contentsOf: bundledImages[randomPodcasts.count..<maxCount])
        }

        self.headerImages = randomPodcasts
    }

    func didAppear() {
        OnboardingFlow.shared.track(.setupAccountShown)
    }

    func didDismiss(type: OnboardingDismissType) {
        guard type == .swipe else { return }
        OnboardingFlow.shared.track(.setupAccountDismissed)
    }

    func loginTapped() {
        OnboardingFlow.shared.track(.setupAccountButtonTapped, properties: ["button": "sign_in"])
        if FeatureFlag.newOnboardingAccountCreation.enabled {
            let vc = OnboardingHostingViewController(rootView: SyncSigninView(coordinator: self, loginAgain: false, onCompleted: { self.navigationController?.presentingViewController?.dismiss(animated: true) }).environmentObject(Theme.sharedTheme))
            vc.viewModel = self
            navigationController?.pushViewController(vc, animated: true)
        } else {
            let controller = SyncSigninViewController()
            controller.delegate = self
            navigationController?.pushViewController(controller, animated: true)
        }
    }

    func signUpTapped() {
        OnboardingFlow.shared.track(.setupAccountButtonTapped, properties: ["button": "create_account"])
        let controller = NewEmailViewController()
        controller.delegate = self
        navigationController?.pushViewController(controller, animated: true)
    }

    func getStartedTapped() {
        OnboardingFlow.shared.updateAnalyticsSource(.onboardingRecommendations)
        let hostingController: UIViewController
        if FeatureFlag.newOnboardingRecommendationChanges.enabled {
            let view = InterestsView(continueCallback: { categories in
                self.interestsContinueTapped(categories: categories)
            }) {
                self.interestsContinueTapped(categories: nil)
            }
            let controller = OnboardingHostingViewController(rootView: view.setupDefaultEnvironment())
            controller.viewModel = self
            hostingController = controller
        } else {
            let controller = OnboardingHostingViewController(rootView: OnboardingRecommendationsView(coordinator: self).setupDefaultEnvironment())
            controller.viewModel = self
            hostingController = controller
        }

        hostingController.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        navigationController?.pushViewController(hostingController, animated: true)
    }

    func interestsContinueTapped(categories: [DiscoverCategory]?) {
        let configuration: RecommendationsViewModel.Configuration
        if let categories {
            configuration = .preselected(categories)
        } else {
            configuration = .all
        }
        let view = OnboardingRecommendationsView(coordinator: self, viewModel: RecommendationsViewModel(configuration: configuration))
        let hostingController = OnboardingHostingViewController(rootView: view.setupDefaultEnvironment())
        hostingController.viewModel = self
        hostingController.navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        navigationController?.pushViewController(hostingController, animated: true)
    }

    func recommendationsContinueTapped() {
        let view = LoginLandingView(coordinator: self, fullScreenMode: true)
        let hostingController = LoginLandingHostingController(rootView: view.setupDefaultEnvironment())
        hostingController.viewModel = self
        navigationController?.pushViewController(hostingController, animated: true)
    }

    @objc func dismissTapped() {
        OnboardingFlow.shared.track(.setupAccountDismissed)
        navigationController?.dismiss(animated: true)
    }

    private let bundledImages: [LoginHeaderImage] = [
        .init(podcast: nil, imageName: "login-cover-1"),
        .init(podcast: nil, imageName: "login-cover-2"),
        .init(podcast: nil, imageName: "login-cover-3"),
        .init(podcast: nil, imageName: "login-cover-4"),
        .init(podcast: nil, imageName: "login-cover-5"),
        .init(podcast: nil, imageName: "login-cover-6"),
        .init(podcast: nil, imageName: "login-cover-7")
    ]

    struct LoginHeaderImage {
        let podcast: Podcast?
        let imageName: String?
        var placeholderImageName: String = ""
    }
}

extension LoginCoordinator: SyncSigninDelegate, CreateAccountDelegate {
    func signingProcessCompleted() {
        // Due to connection issues this might be called even if the user didn't actually
        // signed in. So we make sure the user is actually logged in.
        guard SyncManager.isUserLoggedIn() else {
            return
        }

        // Every feature is free, so there's no upgrade flow to show after signing in.
        handleDismiss()
    }

    func handleAccountCreated() {
        Analytics.track(.userAccountCreated, properties: ["source": "password"])
        OnboardingFlow.shared.accountCreated?(true)
        handleDismiss()
    }

    private func handleDismiss() {
        let resetFlow = {
            DispatchQueue.main.async {
                OnboardingFlow.shared.reset()
            }
        }

        navigationController?.dismiss(animated: true) {
            resetFlow()
        }
    }
}

// MARK: - Helpers

extension LoginCoordinator {
    static func make(in navigationController: UINavigationController? = nil, isOnboarding: Bool = false) -> UIViewController {
        let coordinator = LoginCoordinator()
        coordinator.isOnboarding = isOnboarding

        let controller: UIViewController

        if FeatureFlag.newOnboardingAccountCreation.enabled && isOnboarding {
            let view = IntroCarouselView(coordinator: coordinator)
                .setupDefaultEnvironment()
            let hostingController = IntroCarouselHostingController(rootView: view)
            controller = hostingController
        } else {
            let view = LoginLandingView(coordinator: coordinator, fullScreenMode: true)
            let hostingController = LoginLandingHostingController(rootView: view.setupDefaultEnvironment())
            hostingController.viewModel = coordinator
            controller = hostingController
        }

        let navController = navigationController ?? UINavigationController(rootViewController: controller)
        navController.modalPresentationStyle = UIDevice.current.isiPad() ? .formSheet : .fullScreen
        coordinator.navigationController = navController

        return (navigationController == nil) ? navController : controller
    }
}
