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

/// The system light/dark appearance may have flipped (scene trait change,
/// foregrounding, or first appearance). `isDark` is `true` when the system is
/// now dark; nil when a string-based post carried none. The bridged
/// representation is frozen during the migration: the `Bool` rides in
/// `Notification.object`.
nonisolated struct SystemThemeMayHaveChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("SystemThemeChanged") }

    let isDark: Bool?

    static func makeMessage(_ notification: Notification) -> Self? {
        Self(isDark: notification.object as? Bool)
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name, object: message.isDark)
    }
}

/// The user turned on "follow system theme" in Appearance settings. No payload.
nonisolated struct FollowSystemThemeTurnedOn: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("FollowSystemThemeTurnedOn") }

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
    static var name: Notification.Name { Notification.Name("SJTextEditingStarted") }

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
    static var name: Notification.Name { Notification.Name("SJTextEditingEnded") }

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
    static var name: Notification.Name { Notification.Name("SJTappedOnSelectedTab") }

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
    static var name: Notification.Name { Notification.Name("SJTriggerSearch") }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// A catalog search for `term` was requested from outside the search UI (e.g.
/// tapping a person chip on the episode-detail credits card). The Podcasts tab
/// opens its search UI and runs the search
/// (`SearchResultsViewController.startExternalSearch(term:)`).
nonisolated struct ExternalSearchRequested: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("SJExternalSearchRequested") }

    let term: String

    static func makeMessage(_ notification: Notification) -> Self? {
        (notification.object as? String).map(Self.init)
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name, object: message.term)
    }
}

/// The mini player became visible; lists adjust bottom insets. No payload.
nonisolated struct MiniPlayerDidAppear: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("SJMiniPlayerAppeared") }

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
    static var name: Notification.Name { Notification.Name("SJMiniPlayerDisappeared") }

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
