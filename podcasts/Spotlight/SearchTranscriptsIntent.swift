import AppIntents
import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// One transcript search match, presented by Siri for disambiguation. The id
/// (`<episodeUuid>:<segmentIndex>`) re-resolves against the transcript index,
/// so a Shortcut that pinned a match keeps working across process restarts.
struct TranscriptHitEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Transcript Match"
    static let defaultQuery = TranscriptHitEntityQuery()

    let episodeUuid: String
    let podcastUuid: String?
    let segmentIndex: Int
    let episodeTitle: String
    let snippet: String
    let startTime: TimeInterval
    let source: PocketCastsDataModel.TranscriptSource

    var id: String { "\(episodeUuid):\(segmentIndex)" }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(episodeTitle)",
            subtitle: "\(TranscriptSearchIntentHandler.timeString(startTime)) — \(snippet)"
        )
    }
}

struct TranscriptHitEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TranscriptHitEntity] {
        let handler = TranscriptSearchIntentHandler()
        return identifiers.compactMap { handler.entity(forId: $0) }
    }

    func suggestedEntities() async throws -> [TranscriptHitEntity] {
        []
    }
}

/// "Find where they talked about X": searches every indexed transcript and
/// plays the chosen match from its timestamp. Zero hits fall back to opening
/// the app with the search pre-seeded.
struct SearchTranscriptsIntent: AppIntent, ForegroundContinuableIntent {
    static let title: LocalizedStringResource = "Search Transcripts"
    static let description = IntentDescription("Find where podcasts in your library talked about something, and play from that moment.")
    static var openAppWhenRun: Bool { false }

    static var parameterSummary: some ParameterSummary {
        Summary("Search transcripts for \(\.$query)")
    }

    @Parameter(title: "Search For", requestValueDialog: "What do you want to find?")
    var query: String

    @Parameter(title: "Match")
    var match: TranscriptHitEntity?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard FeatureFlag.transcriptSearch.enabled else {
            return .result(dialog: "Transcript search isn't enabled.")
        }

        let handler = TranscriptSearchIntentHandler()
        let hits = handler.topHits(for: query)

        guard !hits.isEmpty else {
            // Nothing indexed matches: hand off to the in-app search UI.
            let term = query
            Analytics.track(.searchTranscriptsIntentRan, properties: ["hit_count": 0, "played": false, "opened_search": true])
            throw needsToContinueInForegroundError("Nothing in your transcripts matches — searching in the app.") {
                NotificationCenter.postOnMainThread(SearchRequested())
                NotificationCenter.postOnMainThread(ExternalSearchRequested(term: term))
            }
        }

        let chosen: TranscriptHitEntity
        if let match {
            chosen = match
        } else if hits.count == 1 {
            chosen = hits[0]
        } else {
            chosen = try await $match.requestDisambiguation(among: hits, dialog: "Which match?")
        }

        let seconds = TranscriptHitPlayback.play(
            episodeUuid: chosen.episodeUuid,
            podcastUuid: chosen.podcastUuid,
            startTime: chosen.startTime,
            source: chosen.source
        )
        Analytics.track(.searchTranscriptsIntentRan, properties: ["hit_count": hits.count, "played": true, "opened_search": false])
        return .result(dialog: "Playing \(chosen.episodeTitle) from \(TranscriptSearchIntentHandler.timeString(seconds)).")
    }
}
