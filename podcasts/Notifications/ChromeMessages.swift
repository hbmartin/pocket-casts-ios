import Foundation
import PocketCastsUtils

/// Typed messages for the UI chrome + account domain (migration Phase 5.6; one
/// struct per legacy name, past tense, no suffix). The bridged raw names are
/// effectively ABI — never change them.
///
/// The no-payload messages implement `makeMessage`/`makeNotification` explicitly
/// (rather than relying on SDK defaults) so string-based posts from unconverted
/// files — e.g. `MainTabBarController` — keep reaching typed observers, and typed
/// posts keep reaching string-based observers, throughout the migration.

/// The app theme changed (user selection, system flip, or theme toggle). The
/// single most-observed notification in the app; listeners re-style themselves
/// from `Theme.sharedTheme`/`AppTheme`. No payload.
nonisolated struct ThemeChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.themeChanged }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The user turned on "follow system theme" in Appearance settings. No payload.
nonisolated struct FollowSystemThemeTurnedOn: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.followSystemThemeTurnedOn }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// A text field/view somewhere in the app began editing; chrome (the tab bar)
/// hides while editing is active. No payload.
nonisolated struct TextEditingDidStart: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.textEditingDidStart }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// A text field/view somewhere in the app ended editing; chrome (the tab bar)
/// becomes visible again. No payload.
nonisolated struct TextEditingDidEnd: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.textEditingDidEnd }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The user tapped the already-selected tab bar item (scroll-to-top gesture).
/// `tabIndex` is the tapped tab's index; nil when a string-based post carried
/// none. The bridged representation is frozen during the migration: the index
/// rides in `Notification.object`.
nonisolated struct TappedOnSelectedTab: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.tappedOnSelectedTab }

    let tabIndex: Int?

    static func makeMessage(_ notification: Notification) -> Self? {
        Self(tabIndex: notification.object as? Int)
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name, object: message.tabIndex)
    }
}

/// A search was requested from chrome (home-screen quick action / shortcut);
/// the visible list scrolls to and focuses its search field. No payload.
nonisolated struct SearchRequested: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.searchRequested }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The mini player became visible; lists adjust bottom insets. No payload.
nonisolated struct MiniPlayerDidAppear: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.miniPlayerDidAppear }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The mini player was hidden; lists adjust bottom insets. No payload.
nonisolated struct MiniPlayerDidDisappear: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.miniPlayerDidDisappear }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The user signed in, signed out, or was signed in during account creation;
/// account-dependent UI reloads. No payload.
nonisolated struct UserLoginDidChange: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { .userLoginDidChange }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The user signed in via login or account creation. No payload.
nonisolated struct UserSignedIn: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { .userSignedIn }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The onboarding flow was dismissed. No payload.
nonisolated struct OnboardingFlowDidDismiss: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { .onboardingFlowDidDismiss }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// Artwork embedded in the current episode's file finished loading; now-playing
/// UI refreshes its artwork. No payload.
nonisolated struct EpisodeEmbeddedArtworkLoaded: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { .episodeEmbeddedArtworkLoaded }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// A table view drag-reorder began (Up Next queue); other chrome pauses
/// updates while the drag is active. No payload.
nonisolated struct TableViewReorderWillBegin: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { .tableViewReorderWillBegin }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// A table view drag-reorder ended. No payload.
nonisolated struct TableViewReorderDidEnd: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { .tableViewReorderDidEnd }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}
