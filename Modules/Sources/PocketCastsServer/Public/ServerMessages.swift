import Foundation
import PocketCastsUtils

/// Typed messages for the server domain (migration Phase 5.5; one struct per
/// legacy `ServerNotifications` name, past tense, no suffix). The bridged raw
/// names are effectively ABI — never change them.
///
/// Every message implements `makeMessage`/`makeNotification` explicitly (or via
/// `UuidBridgedMessage`) so string-based posts from unconverted files keep
/// reaching typed observers, and typed posts keep reaching string-based
/// observers, throughout the migration. Post via
/// `NotificationCenter.postOnMainThread(_:)` (PocketCastsUtils) — never the
/// SDK's typed `post(_:)`, which drops the bridged payload for legacy
/// observers.
///
/// Where the legacy `ServerNotifications` constant still has string-based
/// observers in unconverted files, the message references it; where the
/// constant has been deleted (zero refs), the raw name lives here.

// MARK: - Sync lifecycle

/// A sync pass is about to be scheduled after a successful refresh. No payload.
public struct SyncStarted: NotificationCenter.MainActorMessage, Sendable {
    public typealias Subject = AnyObject
    public static var name: Notification.Name { Notification.Name(rawValue: "PCSyncStarted") }

    public init() {}

    public static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    public static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// A sync pass finished successfully. No payload.
public struct SyncCompleted: NotificationCenter.MainActorMessage, Sendable {
    public typealias Subject = AnyObject
    public static var name: Notification.Name { ServerNotifications.syncCompleted }

    public init() {}

    public static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    public static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// A sync pass failed. No payload.
public struct SyncFailed: NotificationCenter.MainActorMessage, Sendable {
    public typealias Subject = AnyObject
    public static var name: Notification.Name { Notification.Name(rawValue: "PCSyncFailed") }

    public init() {}

    public static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    public static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

// MARK: - Sync progress

/// The total number of podcasts a full sync will import became known. The
/// bridged representation is frozen during the migration: the count rides in
/// `Notification.object` as an `Int`/`NSNumber`.
public struct SyncProgressPodcastCountKnown: NotificationCenter.MainActorMessage, Sendable {
    public typealias Subject = AnyObject
    public static var name: Notification.Name { Notification.Name(rawValue: "PCSyncCount") }

    public let count: Int

    public init(count: Int) {
        self.count = count
    }

    public static func makeMessage(_ notification: Notification) -> Self? {
        guard let count = notification.object as? Int else { return nil }

        return Self(count: count)
    }

    public static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name, object: message.count, userInfo: nil)
    }
}

/// A full sync progressed to importing another podcast. `upTo` is the 1-based
/// position within the total from `SyncProgressPodcastCountKnown`. The bridged
/// representation is frozen: the position rides in `Notification.object` as an
/// `Int`/`NSNumber`.
public struct SyncProgressPodcastUptoChanged: NotificationCenter.MainActorMessage, Sendable {
    public typealias Subject = AnyObject
    public static var name: Notification.Name { Notification.Name(rawValue: "PCSyncUpto") }

    public let upTo: Int

    public init(upTo: Int) {
        self.upTo = upTo
    }

    public static func makeMessage(_ notification: Notification) -> Self? {
        guard let upTo = notification.object as? Int else { return nil }

        return Self(upTo: upTo)
    }

    public static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name, object: message.upTo, userInfo: nil)
    }
}

/// A full sync finished importing podcasts (episode-level work may continue).
/// No payload.
public struct SyncProgressPodcastsImported: NotificationCenter.MainActorMessage, Sendable {
    public typealias Subject = AnyObject
    public static var name: Notification.Name { Notification.Name(rawValue: "PCSyncPodcastsDone") }

    public init() {}

    public static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    public static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

// MARK: - Refresh

/// A podcast refresh finished successfully (also fired when server-driven
/// podcast updates land). No payload; listeners re-query.
public struct PodcastsRefreshed: NotificationCenter.MainActorMessage, Sendable {
    public typealias Subject = AnyObject
    public static var name: Notification.Name { ServerNotifications.podcastsRefreshed }

    public init() {}

    public static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    public static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// A podcast refresh failed. No payload.
public struct PodcastRefreshFailed: NotificationCenter.MainActorMessage, Sendable {
    public typealias Subject = AnyObject
    public static var name: Notification.Name { Notification.Name(rawValue: "PCRefFailed") }

    public init() {}

    public static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    public static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// A user-requested refresh was throttled because one ran recently; treated as
/// a successful completion by listeners. No payload.
public struct PodcastRefreshThrottled: NotificationCenter.MainActorMessage, Sendable {
    public typealias Subject = AnyObject
    public static var name: Notification.Name { Notification.Name(rawValue: "PCRefreshedThrottled") }

    public init() {}

    public static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    public static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

// MARK: - Episode metadata

/// An episode's file type or byte size changed after a server metadata probe.
/// `uuid` is the episode uuid.
public struct EpisodeTypeOrLengthChanged: UuidBridgedMessage, Sendable {
    public static var name: Notification.Name { ServerNotifications.episodeTypeOrLengthChanged }

    public let uuid: String?

    public init(uuid: String?) {
        self.uuid = uuid
    }
}

// MARK: - Account state

/// The user's subscription status changed (IAP purchase, restore, expiry, or
/// sign out). No payload; listeners re-query `SubscriptionHelper`.
public struct SubscriptionStatusChanged: NotificationCenter.MainActorMessage, Sendable {
    public typealias Subject = AnyObject
    public static var name: Notification.Name { ServerNotifications.subscriptionStatusChanged }

    public init() {}

    public static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    public static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The user is about to be signed out; fired before tokens and sync state are
/// cleared. `userInitiated` is `false` when the sign-out was forced (e.g. an
/// invalid token). The bridged representation is frozen during the migration:
/// the flag rides in `userInfo` under `UserWillBeSignedOut.userInitiatedKey`.
public struct UserWillBeSignedOut: NotificationCenter.MainActorMessage, Sendable {
    public typealias Subject = AnyObject
    public static var name: Notification.Name { Notification.Name(rawValue: "Server.User.WillBeSignedOut") }

    public static let userInitiatedKey = "user_initiated"

    public let userInitiated: Bool

    public init(userInitiated: Bool) {
        self.userInitiated = userInitiated
    }

    public static func makeMessage(_ notification: Notification) -> Self? {
        guard let userInitiated = notification.userInfo?[Self.userInitiatedKey] as? Bool else { return nil }

        return Self(userInitiated: userInitiated)
    }

    public static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name, object: nil, userInfo: [Self.userInitiatedKey: message.userInitiated])
    }
}
