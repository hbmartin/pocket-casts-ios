import Foundation

/// Coordinates one-time feature-highlight flows.
///
/// The What's New surfaces that used to *start* these flows have been removed,
/// so `current` now stays `.none` for the app's lifetime. The type is retained
/// because player, profile and settings code still reads it to decide whether a
/// highlight is in progress — with What's New gone those checks simply no-op.
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
