import AppIntents
import PocketCastsUtils

private enum PlaybackControlIntentError: Error {
    case featureUnavailable
}

/// Background playback actions surfaced by the WidgetKit controls.
enum PlaybackControlAction: String, AppEnum, CaseIterable {
    case playPause
    case skipBack
    case skipForward
    case nextChapter
    case playUpNext
    /// Starts a 15-minute sleep timer when none is running; extends the
    /// running one by 15 minutes otherwise.
    case sleepTimer
    /// Saves a highlight at the current playback position (Highlights S3).
    case saveHighlight

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Playback Action")
    }

    static var caseDisplayRepresentations: [PlaybackControlAction: DisplayRepresentation] {
        [
            .playPause: DisplayRepresentation(title: "Play / Pause"),
            .skipBack: DisplayRepresentation(title: "Skip Back"),
            .skipForward: DisplayRepresentation(title: "Skip Forward"),
            .nextChapter: DisplayRepresentation(title: "Next Chapter"),
            .playUpNext: DisplayRepresentation(title: "Play Next Episode"),
            .sleepTimer: DisplayRepresentation(title: "Sleep Timer"),
            .saveHighlight: DisplayRepresentation(title: "Save Highlight")
        ]
    }
}

/// Kinds for the playback `ControlWidget`s, shared between the widget extension
/// (which declares the controls) and the app (which reloads them).
nonisolated enum PlaybackControlKind {
    static let playPause = "au.com.shiftyjelly.pocketcasts.control.playPause"
    static let skipBack = "au.com.shiftyjelly.pocketcasts.control.skipBack"
    static let skipForward = "au.com.shiftyjelly.pocketcasts.control.skipForward"
    static let nextChapter = "au.com.shiftyjelly.pocketcasts.control.nextChapter"
    static let playUpNext = "au.com.shiftyjelly.pocketcasts.control.playUpNext"
    static let sleepTimer = "au.com.shiftyjelly.pocketcasts.control.sleepTimer"
    static let saveHighlight = "au.com.shiftyjelly.pocketcasts.control.saveHighlight"

    static let all = [playPause, skipBack, skipForward, nextChapter, playUpNext, sleepTimer, saveHighlight]
}

/// Drives the Control Center / Lock Screen playback controls. As an
/// `AudioPlaybackIntent`, `perform()` always runs in the main app process, so
/// the real work lives in `performPlaybackControlAction(_:)` (app target) while
/// the widget extension links only a stub — mirroring `PlayEpisodeIntent`.
struct PlaybackControlIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Control Playback"
    static let isDiscoverable = false

    @Parameter(title: "Action")
    var action: PlaybackControlAction

    init() {
        // Required by AppIntents for parameter decoding.
    }

    init(_ action: PlaybackControlAction) {
        self.action = action
    }

    static var openAppWhenRun: Bool { false }

    static var supportedModes: IntentModes { [.background] }

    @MainActor
    func perform() async throws -> some IntentResult {
        FileLog.shared.addMessage("PlaybackControlIntent perform called for \(action.rawValue)")
        guard action != .saveHighlight || FeatureFlag.highlightCapture.enabled else {
            throw PlaybackControlIntentError.featureUnavailable
        }
        performPlaybackControlAction(action)
        return .result()
    }
}
