import Foundation
import SwiftUI

class OnboardingHostingViewController<Content>: UIHostingController<Content>, UIAdaptivePresentationControllerDelegate, AnalyticsSourceProvider where Content: View {
    var analyticsSource: AnalyticsSource { .onboarding }
    var navBarIsHidden: Bool = false
    var iconTintColor: UIColor = AppTheme.colorForStyle(.primaryInteractive01)

    var viewModel: OnboardingModel?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateNavigationBarStyle(animated: false)

        navigationController?.navigationBar.isHidden = navBarIsHidden
        navigationController?.navigationBar.tintColor = iconTintColor
        navigationItem.backButtonDisplayMode = .minimal
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel?.didAppear()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let controller = navigationController ?? self
        guard controller.isBeingDismissed else { return }

        DispatchQueue.main.async {
            OnboardingFlow.shared.reset()
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        presentationController?.delegate = self
        navigationController?.presentationController?.delegate = self

        updateNavigationBarStyle(animated: false)

        navigationItem.backButtonDisplayMode = .minimal
        navigationController?.navigationBar.tintColor = iconTintColor

        themeTokenBox.token = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
            self?.updateNavigationBarStyle(animated: false)
        }
    }

    // Token teardown lives in the box: this generic UIHostingController subclass
    // can't declare the isolated deinit it would need (see ObservationTokenBox).
    private let themeTokenBox = ObservationTokenBox()

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        viewModel?.didDismiss(type: .viewDisappearing)
    }

    private func updateNavigationBarStyle(animated: Bool) {
        guard animated else {
            apply()
            return
        }

        UIView.animate(withDuration: Constants.Animation.defaultAnimationTime) {
            self.apply()
        }
    }

    private func apply() {
        // On iOS 26 the system Liquid Glass nav bar handles its own transparent appearance and
        // back-indicator styling, so there is nothing to configure here.
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        viewModel?.didDismiss(type: .swipe)
    }
}

class OnboardingModalHostingViewController<Content>: BottomSheetSwiftUIWrapper<Content>, AnalyticsSourceProvider where Content: View {
    var analyticsSource: AnalyticsSource { .onboarding }
    var viewModel: OnboardingModel?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel?.didAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        viewModel?.didDismiss(type: .viewDisappearing)
    }
}
