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

/// Provides the current play/pause state for the play/pause control by reading
/// the shared app-group value the main app keeps up to date.
struct PlaybackStateControlProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        CommonWidgetHelper.loadPlayingStatus()
    }
}
