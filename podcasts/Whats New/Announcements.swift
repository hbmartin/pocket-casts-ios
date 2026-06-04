import Foundation
import SwiftUI
import PocketCastsUtils

struct Announcements {
    // Order is important.
    // In the case a user migrates to, let's say, 7.10 to 7.15 and
    // there were two announcements, the last one will be picked.
    var announcements: [WhatsNew.Announcement] = [
        // Autoplay
        .init(
            version: "7.43",
            header: AnyView(AutoplayWhatsNewHeader()),
            title: L10n.announcementAutoplayTitle,
            message: L10n.announcementAutoplayDescription,
            buttonTitle: L10n.enableItNow,
            action: {
                AnnouncementFlow.current = .autoPlay

                NavigationManager.sharedManager.navigateTo(NavigationManager.settingsProfileKey, data: nil)
            },
            isEnabled: true
        ),

        // Slumber Studios partnership
        .init(
            version: "7.57",
            header: AnyView(SlumberWhatsNewHeader()),
            title: "",
            message: "",
            buttonTitle: "",
            action: {},
            isEnabled: FeatureFlag.slumber.enabled,
            fullModal: true,
            customBody: AnyView(SlumberCustomBody())
        ),

        // Give Ratings
        .init(
            version: "7.70",
            header: AnyView(GiveRatingsWhatsNewHeader()),
            title: L10n.ratingWhatsNewTitle,
            message: L10n.ratingWhatsNewMessage,
            buttonTitle: L10n.ratingWhatsNewButtonTitle,
            action: {
                SceneHelper.rootViewController()?.dismiss(animated: true)
            },
            isEnabled: true,
            fullModal: true
        ),
        .init(
            version: "7.72",
            header: AnyView(ClipsWhatsNewView()),
            title: L10n.clipsWhatsNewTitle,
            message: L10n.clipsWhatsNewMessage,
            buttonTitle: L10n.clipsWhatsNewButtonTitle,
            action: {
                SceneHelper.rootViewController()?.dismiss(animated: true)
            },
            isEnabled: true,
            fullModal: true
        ),
        .init(
            version: "7.77",
            header: AnyView(UpNextAnnouncementView().setupDefaultEnvironment()),
            title: L10n.upNextShuffleAnnouncementTitle,
            message: L10n.upNextShuffleAnnouncementText,
            buttonTitle: L10n.upNextShuffleAnnouncementButton,
            action: {
                SceneHelper.rootViewController()?.dismiss(animated: true)
            },
            isEnabled: FeatureFlag.upNextShuffle.enabled,
            fullModal: true
        )
    ]
}

// MARK: - AnnouncementFlow

enum AnnouncementFlow {
    static var current: Self = .none

    /// No active flow
    case none

    /// Show the autoplay settings
    case autoPlay

    /// Show the player and highlight the Add Bookmark item
    case bookmarksPlayer

    /// Show the headphone controls action for Bookmarks
    case bookmarksProfile
}
