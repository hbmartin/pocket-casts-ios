import Foundation

/// Legacy string-notification names for the server domain. Each remaining
/// constant still has string-based observers in files owned by other Phase 5
/// sweeps; it is deleted once those observers move to the typed message in
/// `ServerMessages.swift` (which references the constant while it exists).
/// The raw strings are effectively ABI — never change them.
public enum ServerNotifications {
    // Sync
    public static let syncCompleted = NSNotification.Name(rawValue: "PCSyncDone")
    public static let podcastsRefreshed = NSNotification.Name(rawValue: "PCRefreshed")
    public static let episodeTypeOrLengthChanged = NSNotification.Name(rawValue: "SJEpisodeTypeChanged")

    // Account state
    public static let subscriptionStatusChanged = NSNotification.Name(rawValue: "SJSubscriptionStatusChanged")
}
