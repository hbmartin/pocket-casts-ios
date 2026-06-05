import AppIntents
import PocketCastsUtils
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen control that toggles play/pause. It reads the
/// shared app-group playback state to show the correct label and icon.
struct PlaybackPlayPauseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: PlaybackControlKind.playPause, provider: PlaybackStateControlProvider()) { isPlaying in
            ControlWidgetButton(action: PlaybackControlIntent(.playPause)) {
                Label(isPlaying ? L10n.pause : L10n.play, systemImage: isPlaying ? "pause.fill" : "play.fill")
            }
        }
        .displayName("Play / Pause")
        .description("Play or pause the current episode.")
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
        .displayName("Skip Back")
        .description("Skip back in the current episode.")
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
        .displayName("Skip Forward")
        .description("Skip forward in the current episode.")
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
