import Foundation
import PocketCastsDataModel
import PocketCastsServer

/// Drives the Explore tab: Apple top charts (optionally by genre), directory
/// search, and the serverless subscribe pipeline (`addLocalFeed`).
@MainActor
final class ExploreViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded([ExplorePodcast])
        case failed
    }

    @Published private(set) var chartState: LoadState = .idle
    @Published private(set) var searchState: LoadState = .idle

    @Published var selectedGenre: ExploreGenre? {
        didSet {
            guard oldValue != selectedGenre else { return }

            loadCharts()
        }
    }

    @Published var searchTerm = "" {
        didSet {
            guard oldValue != searchTerm else { return }

            scheduleSearch()
        }
    }

    /// The podcast currently shown in the preview sheet.
    @Published var previewedPodcast: ExplorePodcast?

    /// Non-nil while a subscribe is in flight, so the UI can show progress and
    /// avoid double-subscribing.
    @Published private(set) var subscribingPodcastId: String?

    var isSearching: Bool {
        !searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let directory: ITunesDirectory
    private let country: String
    private var chartTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init(directory: ITunesDirectory = ITunesDirectory(), country: String = ITunesDirectory.currentCountry) {
        self.directory = directory
        self.country = country
    }

    func loadChartsIfNeeded() {
        guard chartState == .idle else { return }

        loadCharts()
    }

    func loadCharts() {
        chartTask?.cancel()
        chartState = .loading

        let genre = selectedGenre
        chartTask = Task { [directory, country, weak self] in
            do {
                let podcasts = try await directory.topPodcasts(country: country, genre: genre)
                guard !Task.isCancelled else { return }

                self?.chartState = .loaded(podcasts)
            } catch {
                guard !Task.isCancelled else { return }

                self?.chartState = .failed
            }
        }
    }

    func retry() {
        if isSearching {
            scheduleSearch()
        } else {
            loadCharts()
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()

        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            searchState = .idle
            return
        }

        searchState = .loading
        searchTask = Task { [directory, country, weak self] in
            // Small debounce so we don't hit the API on every keystroke
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            do {
                let podcasts = try await directory.search(term: term, country: country)
                guard !Task.isCancelled else { return }

                self?.searchState = .loaded(podcasts)
            } catch {
                guard !Task.isCancelled else { return }

                self?.searchState = .failed
            }
        }
    }

    /// Resolves the entry to a feed URL (chart entries need an iTunes lookup),
    /// subscribes through the on-device feed pipeline — no Pocket Casts servers —
    /// and returns the resolved podcast uuid for navigation, or nil on failure.
    func subscribe(to podcast: ExplorePodcast) async -> String? {
        guard subscribingPodcastId == nil else { return nil }

        subscribingPodcastId = podcast.id
        defer { subscribingPodcastId = nil }

        var feedURL = podcast.feedURL
        if feedURL == nil {
            feedURL = try? await directory.lookupFeedURL(id: podcast.id)
        }
        guard let feedURL, !feedURL.isEmpty else { return nil }

        let added = await withCheckedContinuation { continuation in
            ServerPodcastManager.shared.addLocalFeed(feedURL: feedURL, subscribe: true) { added in
                continuation.resume(returning: added)
            }
        }
        guard added else { return nil }

        // Dedup can attach to an existing row, so resolve the real uuid
        return DataManager.sharedManager.findPodcast(feedURL: feedURL)?.uuid ?? LocalFeedIdentity.uuid(seed: feedURL)
    }
}
