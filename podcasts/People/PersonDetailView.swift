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
    struct EpisodeRow: Hashable, Sendable {
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

    init(entry: PersonDirectoryEntry) {
        self.entry = entry
    }

    func load() {
        let appearances = entry.appearances
        Task.detached(priority: .userInitiated) { [weak self] in
            let dataManager = DataManager.sharedManager
            var seen = Set<String>()
            var rows: [EpisodeRow] = []
            for appearance in appearances where !seen.contains(appearance.episodeUuid) {
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
            await MainActor.run { [weak self] in
                self?.episodes = rows
            }
        }
    }

    private func search() {
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            searchHits = []
            return
        }
        let scopes = entry.appearances.map {
            TranscriptSearchDataManager.SpeakerScope(episodeUuid: $0.episodeUuid, speaker: $0.canonicalSpeaker)
        }
        Task { [weak self] in
            let hits = await Task.detached(priority: .userInitiated) {
                TranscriptSearchHitDisplay.displays(for: DataManager.sharedManager.transcriptSearch.search(term: term, speakerScopes: scopes))
            }.value
            guard let self, term == self.searchTerm.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            self.searchHits = hits
            Analytics.track(.peopleDirectorySegmentSearchPerformed, properties: ["hit_count": hits.count])
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
}
