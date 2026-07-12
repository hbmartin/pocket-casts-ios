import Foundation
import PocketCastsUtils

/// Typed messages for the playback domain (migration Phase 5.2; one struct per
/// legacy `Constants.Notifications` name, past tense, no suffix). The bridged
/// raw names are effectively ABI — never change them.
///
/// The no-payload messages implement `makeMessage`/`makeNotification` explicitly
/// (rather than relying on SDK defaults) so string-based posts from unconverted
/// files — e.g. `Settings`, `PlaylistDetailViewController+PlayAll` — keep reaching
/// typed observers, and typed posts keep reaching string-based observers,
/// throughout the migration.

/// Playback is about to start (an episode was handed to a player but audio has
/// not begun yet); loading UI shows a buffering state. No payload.
nonisolated struct PlaybackStarting: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.playbackStarting }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// Playback started (or resumed) for the current episode. No payload;
/// listeners re-query `PlaybackManager`.
nonisolated struct PlaybackStarted: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.playbackStarted }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// Playback was paused. No payload.
nonisolated struct PlaybackPaused: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.playbackPaused }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// Playback ended (the player stopped; queue may move to the next episode).
/// No payload.
nonisolated struct PlaybackEnded: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.playbackEnded }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// Playback failed; the failure details live in
/// `PlaybackManager.shared.activeError`. No payload.
nonisolated struct PlaybackFailed: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.playbackFailed }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The playhead progressed during normal playback (fires roughly once per
/// second while playing). No payload; listeners re-query the current time.
nonisolated struct PlaybackProgressed: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.playbackProgress }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The playing track changed (a different episode was loaded into the player).
/// No payload.
nonisolated struct PlaybackTrackChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.playbackTrackChanged }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The playback position for an episode was persisted to the database. `uuid`
/// is the episode uuid.
nonisolated struct PlaybackPositionSaved: UuidBridgedMessage {
    static var name: Notification.Name { Constants.Notifications.playbackPositionSaved }

    let uuid: String?

    init(uuid: String?) {
        self.uuid = uuid
    }
}

/// The playback effects (speed, trim silence, volume boost) changed for the
/// current episode. No payload; listeners re-query `PlaybackManager.effects()`.
nonisolated struct PlaybackEffectsChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.playbackEffectsChanged }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The chapter list for the current episode was (re)loaded or cleared. No
/// payload; listeners re-query `PlaybackManager.currentChapters()`.
nonisolated struct PodcastChaptersDidUpdate: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.podcastChaptersDidUpdate }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// Playback crossed into a different chapter of the current episode. No
/// payload.
nonisolated struct PodcastChapterChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.podcastChapterChanged }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The cached copy of the currently playing episode was refreshed (e.g. its
/// database row changed). No payload.
nonisolated struct CurrentlyPlayingEpisodeUpdated: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.currentlyPlayingEpisodeUpdated }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The sleep timer was started, extended, or cancelled; state lives on
/// `PlaybackManager`. No payload.
nonisolated struct SleepTimerChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.sleepTimerChanged }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The video playback engine switched (e.g. the playing episode's downloaded
/// file replaced its stream); video UI re-attaches its player. No payload.
nonisolated struct VideoPlaybackEngineSwitched: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.videoPlaybackEngineSwitched }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The Advanced Audio tuning values changed; the new snapshot lives in
/// `Settings.audioTuning`. No payload.
nonisolated struct AudioTuningDidChange: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.audioTuningDidChange }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The skip forward/back durations changed in settings. No payload; listeners
/// re-read `Settings.skipForwardTime`/`Settings.skipBackTime`.
nonisolated struct SkipTimesChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.skipTimesChanged }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The "extra media session actions" setting changed (extra actions on the
/// lock screen / CarPlay). No payload.
nonisolated struct ExtraMediaSessionActionsChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.extraMediaSessionActionsChanged }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The remote-command (headphone/lock screen controls) settings changed. No
/// payload.
nonisolated struct RemoteCommandSettingsChanged: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.remoteCommandSettingsChanged }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}

/// The player shelf actions were reordered or toggled; the full player
/// rebuilds its shelf. No payload.
nonisolated struct PlayerActionsUpdated: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Constants.Notifications.playerActionsUpdated }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: Self.name)
    }
}
