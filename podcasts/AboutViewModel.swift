import Foundation

class AboutViewModel: ObservableObject {
    func track(action: AboutAction) {
        switch action {
        case .shareWithFriends:
            Analytics.track(.settingsAboutShareWithFriendsTapped)
        case .website:
            Analytics.track(.settingsAboutWebsiteTapped)
        case .twitter:
            Analytics.track(.settingsAboutTwitterTapped)
        case .automatticFamily:
            Analytics.track(.settingsAboutAutomatticFamilyTapped)
        case .workWithUs:
            Analytics.track(.settingsAboutWorkWithUsTapped)
        }
    }

    enum AboutAction {
        case shareWithFriends
        case website
        case twitter
        case automatticFamily
        case workWithUs
    }
}
