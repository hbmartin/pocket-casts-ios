import AppIntents
import PocketCastsUtils

/// Background playback actions surfaced by the WidgetKit controls.
enum PlaybackControlAction: String, AppEnum, CaseIterable {
    case playPause
    case skipBack
    case skipForward

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Playback Action")
    }

    static var caseDisplayRepresentations: [PlaybackControlAction: DisplayRepresentation] {
        [
            .playPause: DisplayRepresentation(title: "Play / Pause"),
            .skipBack: DisplayRepresentation(title: "Skip Back"),
            .skipForward: DisplayRepresentation(title: "Skip Forward")
        ]
    }
}

/// Kinds for the playback `ControlWidget`s, shared between the widget extension
/// (which declares the controls) and the app (which reloads them).
enum PlaybackControlKind {
    static let playPause = "au.com.shiftyjelly.pocketcasts.control.playPause"
    static let skipBack = "au.com.shiftyjelly.pocketcasts.control.skipBack"
    static let skipForward = "au.com.shiftyjelly.pocketcasts.control.skipForward"
}

/// Drives the Control Center / Lock Screen playback controls. As an
/// `AudioPlaybackIntent`, `perform()` always runs in the main app process, so
/// the real work lives in `performPlaybackControlAction(_:)` (app target) while
/// the widget extension links only a stub — mirroring `PlayEpisodeIntent`.
struct PlaybackControlIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Control Playback"
    static var isDiscoverable = false

    @Parameter(title: "Action")
    var action: PlaybackControlAction

    init() {
        // Required by AppIntents for parameter decoding.
    }

    init(_ action: PlaybackControlAction) {
        self.action = action
    }

    static var openAppWhenRun: Bool { false }

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background] }

    @MainActor
    func perform() async throws -> some IntentResult {
        FileLog.shared.addMessage("PlaybackControlIntent perform called for \(action.rawValue)")
        performPlaybackControlAction(action)
        return .result()
    }
}
