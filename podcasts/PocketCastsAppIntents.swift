import AppIntents
import Foundation

// MARK: - Playback control App Intents
//
// These replace the SiriKit `INPlayMediaIntent`/`SJ*` shortcut flows with the
// modern App Intents framework. They run in the app process and route through
// the shared `PlaybackIntentActionHandler`.

enum PlaybackIntentError: LocalizedError {
    case actionFailed

    var errorDescription: String? {
        L10n.playbackFailed
    }
}

func requireSuccessfulPlaybackAction(_ actionSucceeded: Bool) throws {
    guard actionSucceeded else {
        throw PlaybackIntentError.actionFailed
    }
}

struct ResumePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Resume"
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.resume())
        return .result()
    }
}

struct PausePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Pause"
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        PlaybackIntentActionHandler.shared.pausePlayback()
        return .result()
    }
}

struct PlayUpNextIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play Up Next"
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.playUpNext())
        return .result()
    }
}

struct PlaySuggestedEpisodeIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play a Suggested Episode"
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.playSuggested())
        return .result()
    }
}

enum ChapterNavigationAction: String, AppEnum {
    case previous
    case next

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Chapter")
    static var caseDisplayRepresentations: [ChapterNavigationAction: DisplayRepresentation] = [
        .previous: DisplayRepresentation(title: "Previous Chapter"),
        .next: DisplayRepresentation(title: "Next Chapter")
    ]
}

struct ChapterNavigationIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Skip Chapter"
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Direction")
    var action: ChapterNavigationAction

    init(action: ChapterNavigationAction) {
        self.action = action
    }

    init() {
        action = .next
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        switch action {
        case .previous:
            PlaybackIntentActionHandler.shared.previousChapter()
        case .next:
            PlaybackIntentActionHandler.shared.nextChapter()
        }
        return .result()
    }
}

struct SetSleepTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Sleep Timer"
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Minutes")
    var minutes: Int

    init(minutes: Int) {
        self.minutes = minutes
    }

    init() {
        self.minutes = Int(Settings.customSleepTime() / 60)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.setSleepTimer(minutes: minutes))
        return .result()
    }
}

struct ExtendSleepTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Extend Sleep Timer"
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Minutes", default: 5)
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.extendSleepTimer(minutes: minutes))
        return .result()
    }
}

// MARK: - App Shortcuts

/// Surfaces the default shortcuts previously suggested by `SiriShortcutsManager`
/// as App Shortcuts so they appear in the Shortcuts app and Spotlight.
struct PocketCastsAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumePlaybackIntent(),
            phrases: ["Resume \(.applicationName)", "Resume playback in \(.applicationName)"],
            shortTitle: "Resume",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PausePlaybackIntent(),
            phrases: ["Pause \(.applicationName)"],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: PlayUpNextIntent(),
            phrases: ["Play Up Next in \(.applicationName)", "Play the next episode in \(.applicationName)"],
            shortTitle: "Play Up Next",
            systemImageName: "text.line.first.and.arrowtriangle.forward"
        )
        AppShortcut(
            intent: PlaySuggestedEpisodeIntent(),
            phrases: ["Surprise me in \(.applicationName)", "Play a suggested episode in \(.applicationName)"],
            shortTitle: "Surprise Me",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: ChapterNavigationIntent(action: .next),
            phrases: ["Next chapter in \(.applicationName)"],
            shortTitle: "Next Chapter",
            systemImageName: "forward.end.fill"
        )
        AppShortcut(
            intent: ChapterNavigationIntent(action: .previous),
            phrases: ["Previous chapter in \(.applicationName)"],
            shortTitle: "Previous Chapter",
            systemImageName: "backward.end.fill"
        )
        AppShortcut(
            intent: SetSleepTimerIntent(),
            phrases: ["Set a sleep timer in \(.applicationName)"],
            shortTitle: "Set Sleep Timer",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: ExtendSleepTimerIntent(),
            phrases: ["Extend the sleep timer in \(.applicationName)"],
            shortTitle: "Extend Sleep Timer",
            systemImageName: "moon.zzz"
        )
    }
}
