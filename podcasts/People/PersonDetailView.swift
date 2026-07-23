import PocketCastsDataModel
import PocketCastsUtils
import SwiftUI

/// One person's page: the episodes they appear in, plus a transcript search
/// scoped to what *they* said (their (episode, canonical-speaker) pairs).
struct PersonDetailView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model: PersonDetailModel

    init(entry: PersonDirectoryEntry) {
        _model = StateObject(wrappedValue: PersonDetailModel(entry: entry))
    }

    var body: some View {
        List {
            Section {
                TextField(L10n.peopleDetailSearchPlaceholder, text: $model.searchTerm)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
                    .listRowSeparator(.hidden)
            }

            if !model.searchTerm.isEmpty {
                Section {
                    if model.searchHits.isEmpty {
                        Text(L10n.searchTranscriptsEmptyTitle)
                            .font(style: .footnote)
                            .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                            .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
                    } else {
                        ForEach(Array(model.searchHits.enumerated()), id: \.element) { position, hit in
                            TranscriptSearchResultRow(display: hit, position: position)
                                .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
                        }
                    }
                }
            }

            Section {
                ForEach(model.episodes, id: \.uuid) { episode in
                    Button {
                        model.open(episodeUuid: episode.uuid, podcastUuid: episode.podcastUuid)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(episode.title)
                                .font(style: .body, weight: .medium)
                                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                                .lineLimit(2)
                            if let podcastTitle = episode.podcastTitle {
                                Text(podcastTitle)
                                    .font(style: .footnote)
                                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
                }
            } header: {
                Text(L10n.peopleDetailEpisodesHeader)
                    .font(style: .footnote, weight: .semibold)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi01, theme: theme).ignoresSafeArea())
        .navigationTitle(model.entry.displayName)
        .onAppear { model.load() }
    }
}

/// Drives one person's page: episode rows resolved off-main, and a debounced
/// speaker-scoped transcript search.
@MainActor
final class PersonDetailModel: ObservableObject {
    nonisolated struct EpisodeRow: Hashable, Sendable {
        let uuid: String
        let podcastUuid: String?
        let title: String
        let podcastTitle: String?
    }

    let entry: PersonDirectoryEntry
    @Published private(set) var episodes: [EpisodeRow] = []
    @Published private(set) var searchHits: [TranscriptSearchHitDisplay] = []
    @Published var searchTerm = "" {
        didSet {
            guard searchTerm != oldValue else { return }
            search()
        }
    }

    private let episodesProvider: @Sendable ([PersonAppearance]) async -> [EpisodeRow]
    private let searchProvider: @Sendable (String, [TranscriptSearchDataManager.SpeakerScope]) async -> [TranscriptSearchHitDisplay]
    private let searchTracker: @MainActor @Sendable (Int) -> Void
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    /// Gates load() to once per model lifetime. Trade-off: a speaker rename
    /// elsewhere leaves this screen stale until it's re-pushed — no rename
    /// notification exists to observe (SpeakerRenameView signals only its
    /// presenter via onSaved).
    private var hasStartedLoading = false
    private var searchGeneration = 0

    init(entry: PersonDirectoryEntry,
         episodesProvider: @escaping @Sendable ([PersonAppearance]) async -> [EpisodeRow] = { appearances in
             let dataManager = DataManager.sharedManager
             var seen = Set<String>()
             var rows: [EpisodeRow] = []
             for appearance in appearances where !seen.contains(appearance.episodeUuid) {
                 guard !Task.isCancelled else { return [] }
                 seen.insert(appearance.episodeUuid)
                 guard let episode = dataManager.findBaseEpisode(uuid: appearance.episodeUuid) else { continue }
                 let podcastUuid = appearance.podcastUuid ?? (episode as? Episode)?.podcastUuid
                 rows.append(EpisodeRow(
                     uuid: appearance.episodeUuid,
                     podcastUuid: podcastUuid,
                     title: episode.displayableTitle(),
                     podcastTitle: podcastUuid.flatMap { dataManager.findPodcast(uuid: $0, includeUnsubscribed: true)?.title }
                 ))
             }
             return rows
         },
         searchProvider: @escaping @Sendable (String, [TranscriptSearchDataManager.SpeakerScope]) async -> [TranscriptSearchHitDisplay] = { term, scopes in
             guard !Task.isCancelled else { return [] }
             return TranscriptSearchHitDisplay.displays(
                 for: DataManager.sharedManager.transcriptSearch.search(term: term, speakerScopes: scopes)
             )
         },
         searchTracker: @escaping @MainActor @Sendable (Int) -> Void = {
             Analytics.track(.peopleDirectorySegmentSearchPerformed, properties: ["hit_count": $0])
         }) {
        self.entry = entry
        self.episodesProvider = episodesProvider
        self.searchProvider = searchProvider
        self.searchTracker = searchTracker
    }

    func load() {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true

        let appearances = entry.appearances
        let episodesProvider = episodesProvider
        loadTask = Task { @concurrent [weak self] in
            let rows = await episodesProvider(appearances)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard !Task.isCancelled, let self else { return }
                self.episodes = rows
                self.loadTask = nil
            }
        }
    }

    private func search() {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration &+= 1
        let generation = searchGeneration
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            searchHits = []
            return
        }
        let scopes = entry.appearances.map {
            TranscriptSearchDataManager.SpeakerScope(episodeUuid: $0.episodeUuid, speaker: $0.canonicalSpeaker)
        }
        let searchProvider = searchProvider
        let searchTracker = searchTracker
        searchTask = Task { @concurrent [weak self] in
            let hits = await searchProvider(term, scopes)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard !Task.isCancelled,
                      let self,
                      generation == self.searchGeneration else { return }
                self.searchHits = hits
                self.searchTask = nil
                searchTracker(hits.count)
            }
        }
    }

    func open(episodeUuid: String, podcastUuid: String?) {
        Analytics.track(.peopleDirectoryPersonEpisodeTapped)
        var data: [String: Any] = [NavigationManager.episodeUuidKey: episodeUuid]
        if let podcastUuid {
            data[NavigationManager.podcastKey] = podcastUuid
        }
        NavigationManager.sharedManager.navigateTo(NavigationManager.episodePageKey, data: data as NSDictionary)
    }

    // isolated deinit: the SwiftUI-owned model and its task state live on MainActor.
    isolated deinit {
        loadTask?.cancel()
        searchTask?.cancel()
    }
}
