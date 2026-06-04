import Foundation

class DeselectChaptersAnnouncementViewModel {
    var isPatronAnnouncementEnabled: Bool {
        false
    }

    var isPlusAnnouncementEnabled: Bool {
        false
    }

    var isPlusFreeAnnouncementEnabled: Bool {
        false
    }

    var plusFreeMessage: String {
        ""
    }

    var plusFreeButtonTitle: String {
        L10n.gotIt
    }

    func buttonAction() {
        // The feature is free for everyone now, so just dismiss What's New.
        SceneHelper.rootViewController()?.dismiss(animated: true)
    }
}
