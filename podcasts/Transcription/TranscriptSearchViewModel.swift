import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// View model for the cross-episode transcript search screen: debounces the
/// query, runs the FTS search off the main actor, and groups the flat hits into
/// per-episode sections. Tapping a result seeks-and-plays via the same flow as
/// bookmarks.
@MainActor
final class TranscriptSearchViewModel: ObservableObject {
    // The nested value types are nonisolated: the detached search task builds
    // them off the main actor (default isolation would pin their inits to it).

    /// One styled fragment of a snippet. Consecutive runs concatenate back into
    /// the full snippet text; `isHighlighted` marks the FTS-matched terms (the
    /// `<b>`…`</b>` ranges of the raw snippet).
    nonisolated struct SnippetRun: Equatable {
        let text: String
        let isHighlighted: Bool
    }

    nonisolated struct ResultRow: Identifiable, Equatable {
        /// The FTS segment index — unique within an episode's section.
        let id: Int
        let episodeUuid: String
        let startTime: Double
        let runs: [SnippetRun]
    }

    nonisolated struct EpisodeSection: Identifiable, Equatable {
        var id: String { episodeUuid }
        let episodeUuid: String
        let episodeTitle: String
        let podcastTitle: String?
        let rows: [ResultRow]
    }

    /// Display titles for an episode hit, resolved from the database (injectable
    /// for tests).
    nonisolated struct EpisodeContext {
        let episodeTitle: String
        let podcastTitle: String?
    }

    nonisolated enum Phase: Equatable {
        /// Nothing searched yet (or the field was cleared): show the zero state.
        case idle
        case searching
        case results
        case noResults
    }

    @Published var searchTerm = "" {
        didSet { scheduleSearch() }
    }

    @Published private(set) var sections: [EpisodeSection] = []
    @Published private(set) var phase: Phase = .idle

    // nonisolated: resultLimit is read inside the detached search task.
    nonisolated private static let debounceInterval: Duration = .milliseconds(300)
    nonisolated private static let resultLimit = 100

    private var searchTask: Task<Void, Never>?

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            searchTask = nil
            sections = []
            phase = .idle
            return
        }

        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.debounceInterval)
            } catch {
                return // debounce superseded by newer input
            }
            await self?.performSearch(term: term)
        }
    }

    private func performSearch(term: String) async {
        phase = .searching
        let transcriptSearch = DataManager.sharedManager.transcriptSearch
        let sections = await Task.detached(priority: .userInitiated) {
            let results = transcriptSearch.search(term: term, limit: Self.resultLimit, source: .generated)
            return Self.makeSections(from: results, context: Self.databaseEpisodeContext)
        }.value

        // A newer keystroke cancelled this search while the query ran; its own
        // task owns the published state now.
        guard !Task.isCancelled else { return }
        self.sections = sections
        phase = sections.isEmpty ? .noResults : .results
    }

    // MARK: - Playback

    /// Seek-and-play, cloned from `PlaybackManager.playBookmark`: the now-playing
    /// episode seeks directly; any other episode gets its start position stamped
    /// before the standard play pipeline loads it (which resumes from there).
    /// Returns false when the episode no longer exists.
    @discardableResult
    func play(row: ResultRow) -> Bool {
        Analytics.track(.transcriptionSearchResultTapped, properties: ["episode_uuid": row.episodeUuid])

        let playbackManager = PlaybackManager.shared
        if playbackManager.isNowPlayingEpisode(episodeUuid: row.episodeUuid) {
            playbackManager.seekTo(time: row.startTime, startPlaybackAfterSeek: true)
            return true
        }

        let dataManager = DataManager.sharedManager
        guard let episode = dataManager.findBaseEpisode(uuid: row.episodeUuid) else { return false }
        dataManager.saveEpisode(playedUpTo: row.startTime, episode: episode, updateSyncFlag: false)
        dataManager.saveEpisode(playingStatus: .inProgress, episode: episode, updateSyncFlag: false)
        PlaybackActionHelper.play(episode: episode)
        return true
    }

    // MARK: - Grouping (pure, unit-tested)

    /// Groups flat FTS hits — already ordered by relevance (BM25) — into
    /// per-episode sections. Sections keep the relevance order of each episode's
    /// best hit; rows within a section run in playback order.
    nonisolated static func makeSections(from results: [TranscriptSearchHit],
                                         context: (_ episodeUuid: String, _ podcastUuid: String?) -> EpisodeContext?) -> [EpisodeSection] {
        var order: [String] = []
        var grouped: [String: [TranscriptSearchHit]] = [:]
        for result in results where !result.episodeUuid.isEmpty {
            if grouped[result.episodeUuid] == nil {
                order.append(result.episodeUuid)
            }
            grouped[result.episodeUuid, default: []].append(result)
        }

        return order.map { episodeUuid in
            let hits = (grouped[episodeUuid] ?? []).sorted { $0.startTime < $1.startTime }
            let resolved = context(episodeUuid, hits.first?.podcastUuid)
            let rows = hits.map { hit in
                ResultRow(id: hit.segmentIndex,
                          episodeUuid: episodeUuid,
                          startTime: hit.startTime,
                          runs: snippetRuns(from: hit.snippet))
            }
            return EpisodeSection(episodeUuid: episodeUuid,
                                  episodeTitle: resolved?.episodeTitle ?? L10n.transcriptionSearchUnknownEpisode,
                                  podcastTitle: resolved?.podcastTitle,
                                  rows: rows)
        }
    }

    /// Splits a raw FTS snippet on its `<b>`…`</b>` highlight markers into styled
    /// runs. Degenerate input degrades gracefully: an unterminated start marker
    /// renders the remainder as plain text (markers stripped).
    nonisolated static func snippetRuns(from snippet: String) -> [SnippetRun] {
        let startMarker = TranscriptSearchHit.highlightStart
        let endMarker = TranscriptSearchHit.highlightEnd

        var runs: [SnippetRun] = []
        var remainder = Substring(snippet)
        while let startRange = remainder.range(of: startMarker) {
            guard let endRange = remainder.range(of: endMarker, range: startRange.upperBound ..< remainder.endIndex) else {
                break // unterminated marker: the tail below renders as plain text
            }
            let plain = remainder[..<startRange.lowerBound]
            if !plain.isEmpty {
                runs.append(SnippetRun(text: String(plain), isHighlighted: false))
            }
            let highlighted = remainder[startRange.upperBound ..< endRange.lowerBound]
            if !highlighted.isEmpty {
                runs.append(SnippetRun(text: String(highlighted), isHighlighted: true))
            }
            remainder = remainder[endRange.upperBound...]
        }
        if !remainder.isEmpty {
            let tail = String(remainder)
                .replacingOccurrences(of: startMarker, with: "")
                .replacingOccurrences(of: endMarker, with: "")
            if !tail.isEmpty {
                runs.append(SnippetRun(text: tail, isHighlighted: false))
            }
        }
        return runs
    }

    // MARK: - Title resolution

    /// Resolves display titles from the database. Returns nil when the episode
    /// row no longer exists (the snippet still shows, under a placeholder title —
    /// generated transcripts outlive their audio, and can outlive the episode row).
    nonisolated private static func databaseEpisodeContext(episodeUuid: String, podcastUuid: String?) -> EpisodeContext? {
        let dataManager = DataManager.sharedManager
        guard let episode = dataManager.findBaseEpisode(uuid: episodeUuid) else { return nil }
        let podcastTitle = (episode as? Episode).flatMap { dataManager.findPodcast(uuid: $0.podcastUuid)?.title }
        return EpisodeContext(episodeTitle: episode.displayableTitle(), podcastTitle: podcastTitle)
    }
}
