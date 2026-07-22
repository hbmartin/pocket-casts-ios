import SwiftUI
import PocketCastsServer
import PocketCastsDataModel
import PocketCastsUtils

class SearchResultsModel: ObservableObject {
    private let podcastSearch = PodcastSearchTask()
    private let episodeSearch = EpisodeSearchTask()
    private let predictiveSearch = PredictiveSearchTask()
    private let combinedSearch = CombinedSearchTask()

    private let analyticsHelper: SearchAnalyticsHelper

    @Published var isShowingPredictiveSearch = false
    @Published var isSearchingPredictive = false

    @Published var isSearchingForPodcasts = false
    @Published var isSearchingForEpisodes = false

    @Published var episodeSearchError: Error?
    @Published var podcastSearchError: Error?
    @Published var predictiveSearchError: Error?

    @Published var podcasts: [PodcastFolderSearchResult] = []
    @Published var episodes: [EpisodeSearchResult] = []
    @Published var predictive: [PredictiveSearchResult] = []
    @Published var combinedResults: [CombinedSearchResultType] = []

    /// Matches from the on-device transcript index (AI UX plan Phase 4), resolved
    /// into display rows off the main actor. Always empty while the
    /// `transcriptSearch` flag is off or the FTS index is unavailable.
    @Published var transcriptHits: [TranscriptSearchHitDisplay] = []

    @Published var isShowingLocalResultsOnly = false
    @Published var resultsContainLocalPodcasts = false

    @Published var hideEpisodes = false

    private(set) var currentSearchTerm: String = ""
    private(set) var currentPredictiveSearchTerm: String = ""

    /// Invalidates in-flight transcript-index queries: bumped by every new query
    /// and by `clearSearch()`. The publish guard compares against this rather than
    /// `currentSearchTerm`, which `clearSearch()` resets to "" mid-search.
    private var transcriptSearchGeneration = 0

    private(set) var playedEpisodesUUIDs = Set<String>()
    private let dataMangager: DataManager
    private let beforeTranscriptSearch: @Sendable () async -> Void

    let showLocalResults: Bool

    init(
        analyticsHelper: SearchAnalyticsHelper = SearchAnalyticsHelper(source: .unknown),
        showLocalResults: Bool = false,
        dataManager: DataManager = DataManager.sharedManager,
        beforeTranscriptSearch: @escaping @Sendable () async -> Void = {}
    ) {
        self.analyticsHelper = analyticsHelper
        self.dataMangager = dataManager
        self.showLocalResults = showLocalResults
        self.beforeTranscriptSearch = beforeTranscriptSearch
    }

    var noResults: Bool {
        return podcasts.isEmpty && episodes.isEmpty && predictive.isEmpty && combinedResults.isEmpty && transcriptHits.isEmpty
    }

    func clearSearch() {
        transcriptSearchGeneration += 1
        podcasts = []
        episodes = []
        combinedResults = []
        transcriptHits = []
        allTranscriptHits = []
        playedEpisodesUUIDs = []
        resultsContainLocalPodcasts = false
        currentSearchTerm = ""
    }

    func clearErrors() {
        episodeSearchError = nil
        podcastSearchError = nil
        predictiveSearchError = nil
    }

    @MainActor
    func predictiveSearch(term: String) {
        currentSearchTerm = term
        clearErrors()

        guard !term.trim().isEmpty, !isTermAnURL(term) else {
            return
        }

        Task {
            isSearchingPredictive = true
            do {
                let results = try await predictiveSearch.search(term: term)
                show(predictiveResults: results)
                currentPredictiveSearchTerm = term
            } catch {
                predictiveSearchError = error
                isShowingPredictiveSearch = true
                predictive = []
                analyticsHelper.trackPredictiveFailed(error)
            }
            isSearchingPredictive = false
        }
    }

    private func isTermAnURL(_ term: String) -> Bool {
        return term.lowercased().startsWith(string: "http://") || term.lowercased().startsWith(string: "https://")
    }

    @MainActor
    func search(term: String) {
        if FeatureFlag.searchImprovements.enabled, !isTermAnURL(term) {
            combinedSearch(term: term)
            return
        }

        clearErrors()

        if !isShowingLocalResultsOnly {
            clearSearch()
        }
        // Assigned after clearSearch(), which resets it to "".
        currentSearchTerm = term

        Task {
            isSearchingForPodcasts = true
            do {
                let results = try await podcastSearch.search(term: term)
                show(podcastResults: results)
            } catch {
                podcastSearchError = error
                analyticsHelper.trackFailed(error)
            }

            isSearchingForPodcasts = false
        }

        searchTranscriptIndex(term: term)

        if !isTermAnURL(term) {
            hideEpisodes = false
            Task {
                isSearchingForEpisodes = true
                do {
                    let results = try await episodeSearch.search(term: term)
                    playedEpisodesUUIDs = buildPlayedEpisodesUUIDs(results)
                    episodes = results
                } catch {
                    episodeSearchError = error
                    analyticsHelper.trackFailed(error)
                }

                isSearchingForEpisodes = false
            }
        } else {
            hideEpisodes = true
        }

        analyticsHelper.trackSearchPerformed()
    }

    @MainActor
    func combinedSearch(term: String) {
        clearErrors()

        if !isShowingLocalResultsOnly {
            clearSearch()
        }
        // Assigned after clearSearch(), which resets it to "".
        currentSearchTerm = term

        Task {
            isSearchingForPodcasts = true
            do {
                let results = try await combinedSearch.search(term: term)
                if results.isEmpty {
                    analyticsHelper.trackEmptyResults(for: term)
                }
                showCombinedResults(results)
            } catch {
                isShowingPredictiveSearch = false
                podcastSearchError = error
                analyticsHelper.trackFailed(error)
            }

            isSearchingForPodcasts = false
        }

        searchTranscriptIndex(term: term)

        analyticsHelper.trackSearchPerformed()
    }

    /// Queries the on-device transcript FTS index (flag-gated), fuses in vector
    /// matches when semantic search is on, and publishes the resolved display
    /// rows. The database and scoring work runs off the main actor.
    @MainActor
    private func searchTranscriptIndex(term: String) {
        // Every invocation supersedes the previous query, including calls that
        // cannot start a replacement because the feature is off or the term is
        // not searchable.
        transcriptSearchGeneration += 1
        guard FeatureFlag.transcriptSearch.enabled else { return }

        let transcriptSearch = dataMangager.transcriptSearch
        guard transcriptSearch.isAvailable, !isTermAnURL(term) else {
            allTranscriptHits = []
            transcriptHits = []
            return
        }

        let generation = transcriptSearchGeneration
        let dataManager = dataMangager
        let beforeTranscriptSearch = beforeTranscriptSearch
        let semanticEnabled = FeatureFlag.semanticTranscriptSearch.enabled && dataManager.transcriptEmbeddings.isAvailable

        Task {
            let hits = await Task.detached(priority: .userInitiated) {
                await beforeTranscriptSearch()
                let ftsHits = transcriptSearch.search(term: term)
                guard semanticEnabled else {
                    return TranscriptSearchHitDisplay.displays(for: ftsHits)
                }

                let semanticHits = await SemanticTranscriptSearch().search(term: term)
                var fused = TranscriptSearchFusion.fused(ftsHits: ftsHits, semanticHits: semanticHits)

                // Mild recency boost: "I know I heard this somewhere last month".
                var recencyAgeCache = TranscriptSearchRecencyAgeCache()
                let now = Date()
                fused = TranscriptSearchFusion.recencyBoosted(fused) { episodeUuid in
                    recencyAgeCache.ageDays(for: episodeUuid, now: now) {
                        let episode = dataManager.findEpisode(uuid: episodeUuid)
                        return [episode?.lastPlaybackInteractionDate, episode?.publishedDate].compactMap { $0 }.max()
                    }
                }

                return TranscriptSearchHitDisplay.displays(forFused: fused)
            }.value

            // A newer search (or a clear) superseded this one while the query ran.
            guard generation == transcriptSearchGeneration else { return }
            allTranscriptHits = hits
            applyTranscriptPlayedFilter()
        }
    }

    /// The unfiltered fused hits backing the Transcripts section; `transcriptHits`
    /// is this list after the Played-only filter.
    @Published private(set) var allTranscriptHits: [TranscriptSearchHitDisplay] = []

    /// The Transcripts section's "Played only" chip.
    @Published var transcriptPlayedOnly = false {
        didSet {
            guard transcriptPlayedOnly != oldValue else { return }
            Analytics.track(.librarySearchTranscriptPlayedFilterToggled, properties: ["on": transcriptPlayedOnly])
            applyTranscriptPlayedFilter()
        }
    }

    @MainActor
    private func applyTranscriptPlayedFilter() {
        guard transcriptPlayedOnly, !allTranscriptHits.isEmpty else {
            transcriptHits = allTranscriptHits
            return
        }
        let playedUuids = Set(dataMangager.findPlayedEpisodes(uuids: allTranscriptHits.map(\.episodeUuid)))
        transcriptHits = allTranscriptHits.filter { playedUuids.contains($0.episodeUuid) }
    }

    @MainActor
    func searchLocally(term searchTerm: String) {
        clearSearch()

        let allPodcasts = dataMangager.allPodcasts(includeUnsubscribed: false)

        var results = [PodcastFolderSearchResult?]()
        for podcast in allPodcasts {
            guard let title = podcast.title else { continue }

            if title.localizedCaseInsensitiveContains(searchTerm) {
                results.append(PodcastFolderSearchResult(from: podcast))
            } else if let author = podcast.author, author.localizedCaseInsensitiveContains(searchTerm) {
                results.append(PodcastFolderSearchResult(from: podcast))
            }
        }

        let allFolders = dataMangager.allFolders()
        for folder in allFolders {
            if folder.name.localizedCaseInsensitiveContains(searchTerm) {
                results.append(PodcastFolderSearchResult(from: folder))
            }
        }

        self.podcasts = results.compactMap { $0 }

        resultsContainLocalPodcasts = true
        isShowingLocalResultsOnly = true
    }

    private func buildPlayedEpisodesUUIDs(_ episodes: [EpisodeSearchResult]) -> Set<String> {
        if episodes.isEmpty {
            return []
        }
        let uuids = episodes.map { $0.uuid }
        return dataMangager.findPlayedEpisodes(uuids: uuids)
            .reduce(into: Set<String>()) { list, uuid in
                list.insert(uuid)
            }
    }

    private func show(podcastResults: [PodcastFolderSearchResult]) {
        isShowingPredictiveSearch = false
        if isShowingLocalResultsOnly {
            podcasts.append(contentsOf: podcastResults.filter { !podcasts.contains($0) })
            isShowingLocalResultsOnly = false
        } else {
            podcasts = podcastResults
        }
    }

    private func show(predictiveResults: [PredictiveSearchResult]) {
        isShowingPredictiveSearch = true
        predictive = predictiveResults
    }

    private func showCombinedResults(_ results: [CombinedSearchResultType]) {
        isShowingPredictiveSearch = false
        combinedResults = results
    }
}

/// Per-search cache for the episode lookup used by transcript recency scoring.
/// A negative sentinel distinguishes a cached missing date from an uncached
/// episode because assigning nil to a Dictionary subscript removes the entry.
nonisolated struct TranscriptSearchRecencyAgeCache {
    private static let missingAge = -1.0
    private var ageDaysByEpisode: [String: Double] = [:]

    mutating func ageDays(for episodeUuid: String, now: Date, newestDate: () -> Date?) -> Double? {
        if let cached = ageDaysByEpisode[episodeUuid] {
            return cached >= 0 ? cached : nil
        }

        let age = newestDate().map { max(0, now.timeIntervalSince($0) / 86_400) }
        ageDaysByEpisode[episodeUuid] = age ?? Self.missingAge
        return age
    }
}
