import AppIntents
import Foundation
import PocketCastsDataModel

// MARK: - Playback control App Intents
//
// These replaced the app's legacy SiriKit shortcut flows (removed) with the
// modern App Intents framework. They run in the app process and route through
// the shared `PlaybackIntentActionHandler`.

enum PlaybackIntentError: LocalizedError {
    case actionFailed
    case invalidDuration

    var errorDescription: String? {
        switch self {
        case .actionFailed:
            return L10n.playbackFailed
        case .invalidDuration:
            return L10n.sleepTimerInvalidDuration
        }
    }
}

func requireSuccessfulPlaybackAction(_ actionSucceeded: Bool) throws {
    guard actionSucceeded else {
        throw PlaybackIntentError.actionFailed
    }
}

func requireValidSleepTimerDuration(_ minutes: Int) throws {
    guard (1...300).contains(minutes) else {
        throw PlaybackIntentError.invalidDuration
    }
}

struct ResumePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Resume"
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.resume())
        return .result()
    }
}

struct PausePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Pause"
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        PlaybackIntentActionHandler.shared.pausePlayback()
        return .result()
    }
}

struct PlayUpNextIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Up Next"
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.playUpNext())
        return .result()
    }
}

struct PlaySuggestedEpisodeIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play a Suggested Episode"
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireSuccessfulPlaybackAction(await PlaybackIntentActionHandler.shared.playSuggested())
        return .result()
    }
}

struct NextChapterIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Next Chapter"
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        PlaybackIntentActionHandler.shared.nextChapter()
        return .result()
    }
}

struct PreviousChapterIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Previous Chapter"
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        PlaybackIntentActionHandler.shared.previousChapter()
        return .result()
    }
}

struct SetSleepTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Sleep Timer"
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Minutes", inclusiveRange: (lowerBound: 1, upperBound: 300))
    var minutes: Int

    init(minutes: Int) {
        self.minutes = minutes
    }

    init() {
        self.minutes = Int(Settings.customSleepTime() / 60)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireValidSleepTimerDuration(minutes)
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.setSleepTimer(minutes: minutes))
        return .result()
    }
}

struct ExtendSleepTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Extend Sleep Timer"
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Minutes", default: 5, inclusiveRange: (lowerBound: 1, upperBound: 300))
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireValidSleepTimerDuration(minutes)
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.extendSleepTimer(minutes: minutes))
        return .result()
    }
}

/// Saves a highlight at the current playback position (Highlights program S3).
/// Powers the Siri phrase, the Action Button, and Shortcuts; fails with a
/// dialog when nothing is playing.
struct SaveHighlightIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Save Highlight"
    static var openAppWhenRun: Bool { false }
    static var supportedModes: IntentModes { [.background] }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.saveHighlight())
        return .result()
    }
}

// MARK: - App Shortcuts

/// Surfaces the default shortcuts previously suggested by the legacy SiriKit
/// stack as App Shortcuts so they appear in the Shortcuts app and Spotlight.
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
            intent: PlayPodcastIntent(),
            phrases: ["Play \(\.$podcast) in \(.applicationName)", "Play the podcast \(\.$podcast) in \(.applicationName)"],
            shortTitle: "Play Podcast",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: PlayFilterIntent(),
            phrases: ["Play \(\.$filter) in \(.applicationName)", "Play the filter \(\.$filter) in \(.applicationName)"],
            shortTitle: "Play Filter",
            systemImageName: "play.square.stack"
        )
        // Highlights program S3: Save Highlight took Open Filter's slot —
        // Apple caps AppShortcutsProvider at 10 and Open Filter had the lowest
        // eyes-free value (Play Filter keeps filters voice-reachable).
        AppShortcut(
            intent: SaveHighlightIntent(),
            phrases: ["Save a highlight in \(.applicationName)", "Save highlight in \(.applicationName)", "Highlight that in \(.applicationName)"],
            shortTitle: "Save Highlight",
            systemImageName: "bookmark.fill"
        )
        AppShortcut(
            intent: NextChapterIntent(),
            phrases: ["Next chapter in \(.applicationName)"],
            shortTitle: "Next Chapter",
            systemImageName: "forward.end.fill"
        )
        AppShortcut(
            intent: SetSleepTimerIntent(),
            phrases: ["Set a sleep timer in \(.applicationName)"],
            shortTitle: "Set Sleep Timer",
            systemImageName: "moon.zzz.fill"
        )
        // Apple caps AppShortcutsProvider at 10 shortcuts. Search Transcripts
        // took Extend Sleep Timer's slot (extending is a follow-on action almost
        // always done right after setting the timer, whose shortcut stays); the
        // ExtendSleepTimerIntent itself remains available in the Shortcuts app.
        AppShortcut(
            intent: SearchTranscriptsIntent(),
            phrases: [
                "Search transcripts in \(.applicationName)",
                "Find where they talked about something in \(.applicationName)"
            ],
            shortTitle: "Search Transcripts",
            systemImageName: "text.magnifyingglass"
        )
    }
}
