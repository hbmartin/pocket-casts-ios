import AppIntents
import PocketCastsDataModel

/// App Intents entity representing a subscribed podcast, backed by `DataManager`.
struct PodcastAppEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Podcast")
    }

    static var defaultQuery = PodcastEntityQuery()

    var id: String
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    init(podcast: Podcast) {
        self.id = podcast.uuid
        self.title = podcast.title ?? ""
    }
}

struct PodcastEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [PodcastAppEntity] {
        identifiers.compactMap { uuid in
            DataManager.sharedManager.findPodcast(uuid: uuid).map(PodcastAppEntity.init(podcast:))
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [PodcastAppEntity] {
        DataManager.sharedManager.allPodcastsOrderedByTitle().map(PodcastAppEntity.init(podcast:))
    }
}

struct PlayPodcastIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play Podcast"
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Podcast")
    var podcast: PodcastAppEntity

    init() {
        // Required by AppIntents for parameter decoding.
    }

    init(podcast: PodcastAppEntity) {
        self.podcast = podcast
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.playPodcast(uuid: podcast.id))
        return .result()
    }
}
