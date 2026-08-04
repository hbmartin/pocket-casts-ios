import Foundation
import PocketCastsServer

/// Drives the Explore tab: Apple top charts (optionally by genre), directory
/// search, and subscribing through the standard server pipeline.
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

    /// Resolves the entry through the Pocket Casts catalog by its Apple id,
    /// subscribes via the standard server pipeline, and returns the resolved
    /// podcast uuid for navigation, or nil on failure.
    func subscribe(to podcast: ExplorePodcast) async -> String? {
        guard subscribingPodcastId == nil, let itunesId = Int(podcast.id) else { return nil }

        subscribingPodcastId = podcast.id
        defer { subscribingPodcastId = nil }

        let (added, uuid) = await withCheckedContinuation { continuation in
            ServerPodcastManager.shared.subscribeFromItunesId(itunesId) { added, uuid in
                continuation.resume(returning: (added, uuid))
            }
        }
        return added ? uuid : nil
    }
}
