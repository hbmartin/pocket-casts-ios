import Foundation

/// Tracks a transient in-app "announcement" hand-off between screens — e.g. highlighting
/// the Add Bookmark control on the player after a prompt, or the autoplay setting in Profile.
///
/// The What's New / announcements feature was removed in the "fast & light" build, so nothing
/// sets `current` to anything other than `.none` anymore. The enum is retained because player,
/// profile, settings and shelf code still coordinate against these cases; their branches simply
/// no longer trigger.
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
