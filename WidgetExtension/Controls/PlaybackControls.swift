import AppIntents
import PocketCastsUtils
import SwiftUI
import WidgetKit

private enum PlaybackControlLocalization {
    static let playPauseDisplayName = LocalizedStringResource(
        "widget_playback_control_play_pause_display_name",
        defaultValue: "Play / Pause",
        table: "Localizable"
    )
    static let playPauseDescription = LocalizedStringResource(
        "widget_playback_control_play_pause_description",
        defaultValue: "Play or pause the current episode.",
        table: "Localizable"
    )
    static let skipBackDisplayName = LocalizedStringResource(
        "widget_playback_control_skip_back_display_name",
        defaultValue: "Skip Back",
        table: "Localizable"
    )
    static let skipBackDescription = LocalizedStringResource(
        "widget_playback_control_skip_back_description",
        defaultValue: "Skip back in the current episode.",
        table: "Localizable"
    )
    static let skipForwardDisplayName = LocalizedStringResource(
        "widget_playback_control_skip_forward_display_name",
        defaultValue: "Skip Forward",
        table: "Localizable"
    )
    static let skipForwardDescription = LocalizedStringResource(
        "widget_playback_control_skip_forward_description",
        defaultValue: "Skip forward in the current episode.",
        table: "Localizable"
    )
    static let nextChapterDisplayName = LocalizedStringResource(
        "widget_playback_control_next_chapter_display_name",
        defaultValue: "Next Chapter",
        table: "Localizable"
    )
    static let nextChapterDescription = LocalizedStringResource(
        "widget_playback_control_next_chapter_description",
        defaultValue: "Skip to the next chapter of the current episode.",
        table: "Localizable"
    )
    static let playUpNextDisplayName = LocalizedStringResource(
        "widget_playback_control_play_up_next_display_name",
        defaultValue: "Play Next Episode",
        table: "Localizable"
    )
    static let playUpNextDescription = LocalizedStringResource(
        "widget_playback_control_play_up_next_description",
        defaultValue: "Skip to the next episode in Up Next.",
        table: "Localizable"
    )
    static let sleepTimerDisplayName = LocalizedStringResource(
        "widget_playback_control_sleep_timer_display_name",
        defaultValue: "Sleep Timer",
        table: "Localizable"
    )
    static let sleepTimerDescription = LocalizedStringResource(
        "widget_playback_control_sleep_timer_description",
        defaultValue: "Start a 15 minute sleep timer, or extend the running one.",
        table: "Localizable"
    )
}

/// Control Center / Lock Screen control that toggles play/pause. It reads the
/// shared app-group playback state to show the correct label and icon.
struct PlaybackPlayPauseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PlaybackControlKind.playPause, provider: PlaybackStateControlProvider()) { isPlaying in
            ControlWidgetButton(action: PlaybackControlIntent(.playPause)) {
                Label(isPlaying ? L10n.pause : L10n.play, systemImage: isPlaying ? "pause.fill" : "play.fill")
            }
        }
        .displayName(PlaybackControlLocalization.playPauseDisplayName)
        .description(PlaybackControlLocalization.playPauseDescription)
    }
}

/// Control Center / Lock Screen control that skips back in the current episode.
struct PlaybackSkipBackControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PlaybackControlKind.skipBack) {
            ControlWidgetButton(action: PlaybackControlIntent(.skipBack)) {
                Label(L10n.skipBack, systemImage: "gobackward")
            }
        }
        .displayName(PlaybackControlLocalization.skipBackDisplayName)
        .description(PlaybackControlLocalization.skipBackDescription)
    }
}

/// Control Center / Lock Screen control that skips forward in the current episode.
struct PlaybackSkipForwardControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PlaybackControlKind.skipForward) {
            ControlWidgetButton(action: PlaybackControlIntent(.skipForward)) {
                Label(L10n.skipForward, systemImage: "goforward")
            }
        }
        .displayName(PlaybackControlLocalization.skipForwardDisplayName)
        .description(PlaybackControlLocalization.skipForwardDescription)
    }
}

/// Control Center / Lock Screen control that skips to the next chapter.
struct PlaybackNextChapterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PlaybackControlKind.nextChapter) {
            ControlWidgetButton(action: PlaybackControlIntent(.nextChapter)) {
                Label(L10n.siriShortcutNextChapter, systemImage: "forward.end.alt.fill")
            }
        }
        .displayName(PlaybackControlLocalization.nextChapterDisplayName)
        .description(PlaybackControlLocalization.nextChapterDescription)
    }
}

/// Control Center / Lock Screen control that jumps to the next Up Next episode.
struct PlaybackPlayUpNextControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PlaybackControlKind.playUpNext) {
            ControlWidgetButton(action: PlaybackControlIntent(.playUpNext)) {
                Label(L10n.nextEpisode, systemImage: "forward.end.fill")
            }
        }
        .displayName(PlaybackControlLocalization.playUpNextDisplayName)
        .description(PlaybackControlLocalization.playUpNextDescription)
    }
}

/// Control Center / Lock Screen control that starts (or extends) the sleep timer.
struct PlaybackSleepTimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PlaybackControlKind.sleepTimer) {
            ControlWidgetButton(action: PlaybackControlIntent(.sleepTimer)) {
                Label(L10n.sleepTimer, systemImage: "moon.zzz.fill")
            }
        }
        .displayName(PlaybackControlLocalization.sleepTimerDisplayName)
        .description(PlaybackControlLocalization.sleepTimerDescription)
    }
}

/// Provides the current play/pause state for the play/pause control by reading
/// the shared app-group value the main app keeps up to date.
struct PlaybackStateControlProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        CommonWidgetHelper.loadPlayingStatus()
    }
}
