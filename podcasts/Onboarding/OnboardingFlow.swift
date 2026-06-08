import Foundation
import PocketCastsUtils

struct OnboardingFlow: AnalyticsSourceProvider {
    typealias Context = [String: Any]

    static var shared = OnboardingFlow()

    private(set) var currentFlow: Flow = .none
    private(set) var source: OnboardingFlowSource? = nil

    private(set) var accountCreated: ((Bool)->())?

    mutating func begin(flow: Flow, in controller: UIViewController? = nil, source: OnboardingFlowSource, context: Context? = nil, customTitle: String? = nil, accountCreated: ((Bool)->())? = nil) -> UIViewController {
        self.currentFlow = flow
        self.source = source
        self.accountCreated = accountCreated

        let navigationController = controller as? UINavigationController

        let flowController: UIViewController
        switch flow {
        case .encourageAccountCreation:
            flowController = InformationalModalViewModel.makeController()

        case .initialOnboarding:
            flowController = LoginCoordinator.make(in: navigationController, isOnboarding: true)
        default:
            flowController = LoginCoordinator.make(in: navigationController, isOnboarding: false)
        }

        return flowController
    }

    /// Resets the internal flow state to none and clears any analytics sources
    mutating func reset() {
        if (currentFlow == .initialOnboarding) || (currentFlow == .encourageAccountCreation) {
            NavigationManager.sharedManager.showNotificationsPermissionsModal()
        }
        source = .unknown
        currentFlow = .none

        NotificationCenter.default.post(name: .onboardingFlowDidDismiss, object: nil)
    }

    /// Updates the source passed for analytics
    /// Any `track` events will use this new source
    mutating func updateAnalyticsSource(_ source: OnboardingFlowSource) {
        self.source = source
    }

    func track(_ event: AnalyticsEvent, properties: [String: Any]? = nil) {
        var defaultProperties: [String: Any] = ["flow": currentFlow]

        // Append the source, only if it's set because not every event needs a source
        if let source {
            defaultProperties["source"] = source.rawValue
        }

        let mergedProperties = defaultProperties.merging(properties ?? [:]) { current, _ in current }
        Analytics.track(event, properties: mergedProperties)
    }

    // MARK: - Flow
    enum Flow: String, AnalyticsDescribable {
        /// Default state / not currently in a flow.. not tracked
        case none

        /// When the app first launches, and the user is asked to login/create account
        case initialOnboarding = "initial_onboarding"

        /// When the user is logged out and enters the login flow
        /// This is the same as the onboarding flow
        case loggedOut = "logged_out"

        /// When the user was logged out due to a server or token issue, not as a result of user interaction and is
        /// asked to sign in again. See the `BackgroundSignOutListener`
        case forcedLoggedOut = "forced_logged_out"

        /// When the user is brought into the onboarding flow from the End Of Year prompt
        case endOfYear

        case encourageAccountCreation = "encourage_account_creation"

        var analyticsDescription: String { rawValue }

        /// If after a successful sign in or sign up the onboarding flow
        /// should be dismissed right away
        var shouldDismiss: Bool {
            switch self {
            case .forcedLoggedOut:
                return true
            default:
                return false
            }
        }
    }

    var analyticsSource: AnalyticsSource {
        .onboarding
    }
}
