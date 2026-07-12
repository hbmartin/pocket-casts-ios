import AppIntents
import Foundation
import PocketCastsDataModel

// MARK: - Playback control App Intents
//
// These replace the SiriKit `INPlayMediaIntent`/`SJ*` shortcut flows with the
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
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.playSuggested())
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

// MARK: - Podcast / filter entities (SiriKit INPlayMediaIntent replacement)

/// A followed podcast, exposed to Siri/Shortcuts so "Play <podcast name>"
/// resolves through App Intents instead of the retired SiriKit media intents.
struct PodcastAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Podcast"
    static let defaultQuery = PodcastEntityQuery()

    /// The podcast uuid.
    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct PodcastEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [PodcastAppEntity] {
        identifiers.compactMap { uuid in
            DataManager.sharedManager.findPodcast(uuid: uuid, includeUnsubscribed: false).map {
                PodcastAppEntity(id: $0.uuid, title: $0.title ?? "")
            }
        }
    }

    @MainActor
    func entities(matching string: String) async throws -> [PodcastAppEntity] {
        allEntities().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PodcastAppEntity] {
        Array(allEntities().prefix(12))
    }

    @MainActor
    private func allEntities() -> [PodcastAppEntity] {
        DataManager.sharedManager.allPodcastsOrderedByTitle().compactMap { podcast in
            guard podcast.isSubscribed() else { return nil }
            return PodcastAppEntity(id: podcast.uuid, title: podcast.title ?? "")
        }
    }
}

/// A playlist (filter), exposed so shortcuts can open or play one by name —
/// replacing the generated SJOpenFilterIntent.
struct FilterAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Filter"
    static let defaultQuery = FilterEntityQuery()

    /// The filter uuid.
    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct FilterEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [FilterAppEntity] {
        identifiers.compactMap { uuid in
            DataManager.sharedManager.findPlaylist(uuid: uuid).map {
                FilterAppEntity(id: $0.uuid, title: $0.playlistName)
            }
        }
    }

    @MainActor
    func entities(matching string: String) async throws -> [FilterAppEntity] {
        allEntities().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [FilterAppEntity] {
        allEntities()
    }

    @MainActor
    private func allEntities() -> [FilterAppEntity] {
        DataManager.sharedManager.allPlaylists(includeDeleted: false).map {
            FilterAppEntity(id: $0.uuid, title: $0.playlistName)
        }
    }
}

/// "Play <podcast>": loads the podcast's top unplayed episode, matching the
/// behavior the SiriKit play-media flow provided.
struct PlayPodcastIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play a Podcast"
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Podcast")
    var podcast: PodcastAppEntity

    init() {}

    init(podcast: PodcastAppEntity) {
        self.podcast = podcast
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.playPodcast(uuid: podcast.id))
        return .result()
    }
}

/// "Play <filter>": plays the filter's top episode.
struct PlayFilterIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play a Filter"
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Filter")
    var filter: FilterAppEntity

    init() {}

    init(filter: FilterAppEntity) {
        self.filter = filter
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.playFilter(uuid: filter.id))
        return .result()
    }
}

/// Opens a filter in the app — the SJOpenFilterIntent replacement.
struct OpenFilterIntent: AppIntent {
    static let title: LocalizedStringResource = "Open a Filter"
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Filter")
    var filter: FilterAppEntity

    init() {}

    init(filter: FilterAppEntity) {
        self.filter = filter
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        NavigationManager.sharedManager.navigateTo(NavigationManager.filterPageKey, data: [NavigationManager.filterUuidKey: filter.id])
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
        AppShortcut(
            intent: OpenFilterIntent(),
            phrases: ["Open \(\.$filter) in \(.applicationName)", "Show my \(\.$filter) filter in \(.applicationName)"],
            shortTitle: "Open Filter",
            systemImageName: "line.3.horizontal.decrease.circle"
        )
        AppShortcut(
            intent: NextChapterIntent(),
            phrases: ["Next chapter in \(.applicationName)"],
            shortTitle: "Next Chapter",
            systemImageName: "forward.end.fill"
        )
        AppShortcut(
            intent: PreviousChapterIntent(),
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
