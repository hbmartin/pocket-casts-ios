import Foundation
import PocketCastsDataModel

/// The database surface the Siri transcript-search intent needs, injectable for
/// tests.
nonisolated protocol TranscriptSearchFacade: Sendable {
    func search(term: String, limit: Int) -> [TranscriptSearchHit]
    func episodeTitle(episodeUuid: String) -> String?
    func hit(episodeUuid: String, segmentIndex: Int) -> TranscriptSearchHit?
}

nonisolated struct LiveTranscriptSearchFacade: TranscriptSearchFacade {
    func search(term: String, limit: Int) -> [TranscriptSearchHit] {
        DataManager.sharedManager.transcriptSearch.search(term: term, limit: limit)
    }

    func episodeTitle(episodeUuid: String) -> String? {
        DataManager.sharedManager.findBaseEpisode(uuid: episodeUuid)?.displayableTitle()
    }

    func hit(episodeUuid: String, segmentIndex: Int) -> TranscriptSearchHit? {
        DataManager.sharedManager.transcriptSearch.segment(episodeUuid: episodeUuid, segmentIndex: segmentIndex)
    }
}

/// Pure-ish core of `SearchTranscriptsIntent`: hit resolution and entity
/// construction, kept out of the intent so it's testable without AppIntents.
nonisolated struct TranscriptSearchIntentHandler: Sendable {
    let facade: any TranscriptSearchFacade

    init(facade: any TranscriptSearchFacade = LiveTranscriptSearchFacade()) {
        self.facade = facade
    }

    /// The top transcript hits as Siri entities, in BM25 order. Hits whose
    /// episode no longer resolves are dropped (nothing to title, nothing to play).
    func topHits(for query: String, limit: Int = 5) -> [TranscriptHitEntity] {
        facade.search(term: query, limit: limit).compactMap { entity(for: $0) }
    }

    /// Re-resolves a persisted entity id (`<episodeUuid>:<segmentIndex>`), e.g.
    /// when a saved Shortcut pinned a specific match.
    func entity(forId id: String) -> TranscriptHitEntity? {
        guard let separator = id.lastIndex(of: ":"),
              let segmentIndex = Int(id[id.index(after: separator)...]) else {
            return nil
        }
        let episodeUuid = String(id[..<separator])
        guard let hit = facade.hit(episodeUuid: episodeUuid, segmentIndex: segmentIndex) else { return nil }
        return entity(for: hit)
    }

    private func entity(for hit: TranscriptSearchHit) -> TranscriptHitEntity? {
        guard let episodeTitle = facade.episodeTitle(episodeUuid: hit.episodeUuid) else { return nil }
        return TranscriptHitEntity(
            episodeUuid: hit.episodeUuid,
            podcastUuid: hit.podcastUuid,
            segmentIndex: hit.segmentIndex,
            episodeTitle: episodeTitle,
            snippet: Self.plainSnippet(hit.snippet),
            startTime: hit.startTime,
            source: hit.source
        )
    }

    /// FTS snippets wrap matches in `<b>`…`</b>`; Siri wants plain text.
    static func plainSnippet(_ snippet: String) -> String {
        snippet
            .replacingOccurrences(of: TranscriptSearchHit.highlightStart, with: "")
            .replacingOccurrences(of: TranscriptSearchHit.highlightEnd, with: "")
    }

    /// mm:ss (or h:mm:ss) without going through the MainActor TimeFormatter.
    static func timeString(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let total = max(0, Int(time.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
