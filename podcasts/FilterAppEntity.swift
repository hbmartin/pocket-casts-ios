import AppIntents
import PocketCastsDataModel

/// App Intents entity representing a filter / playlist, backed by `DataManager`.
struct FilterAppEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Filter")
    }

    static let defaultQuery = FilterEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(filter: EpisodeFilter) {
        self.id = filter.uuid
        self.name = filter.playlistName
    }
}

struct FilterEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [FilterAppEntity] {
        identifiers.compactMap { uuid in
            DataManager.sharedManager.findPlaylist(uuid: uuid).map(FilterAppEntity.init(filter:))
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [FilterAppEntity] {
        DataManager.sharedManager.allPlaylists(includeDeleted: false).map(FilterAppEntity.init(filter:))
    }
}

struct PlayFilterIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Filter"
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Filter")
    var filter: FilterAppEntity

    init() {
        // Required by AppIntents for parameter decoding.
    }

    init(filter: FilterAppEntity) {
        self.filter = filter
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.playFilter(uuid: filter.id))
        return .result()
    }
}

struct PlayAllInFilterIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play All in Filter"
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Filter")
    var filter: FilterAppEntity

    init() {
        // Required by AppIntents for parameter decoding.
    }

    init(filter: FilterAppEntity) {
        self.filter = filter
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try requireSuccessfulPlaybackAction(PlaybackIntentActionHandler.shared.playAllFilter(uuid: filter.id))
        return .result()
    }
}

struct OpenFilterIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Filter"
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Filter")
    var filter: FilterAppEntity

    init() {
        // Required by AppIntents for parameter decoding.
    }

    init(filter: FilterAppEntity) {
        self.filter = filter
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let episodeFilter = DataManager.sharedManager.findPlaylist(uuid: filter.id) {
            NavigationManager.sharedManager.navigateTo(NavigationManager.filterPageKey,
                                                       data: [NavigationManager.filterUuidKey: episodeFilter.uuid])
        }
        return .result()
    }
}
