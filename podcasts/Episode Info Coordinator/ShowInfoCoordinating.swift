import Foundation
import PocketCastsDataModel
import PocketCastsServer

nonisolated protocol ShowInfoCoordinating {
    typealias EpisodeTranscriptData = (transcripts: [Episode.Metadata.Transcript], hasGeneratedTranscripts: Bool, isDisplayingGeneratedTranscript: Bool)

    func loadShowNotes(
        podcastUuid: String,
        episodeUuid: String
    ) async throws -> String

    func loadEpisodeArtworkUrl(
        podcastUuid: String,
        episodeUuid: String
    ) async throws -> URL?

    func loadChapters(
        podcastUuid: String,
        episodeUuid: String
    ) async throws -> (metadata: [Episode.Metadata.EpisodeChapter]?, podcastIndex: [PodcastIndexChapter]?, generated: [GeneratedChapter]?)

    func loadTranscriptsMetadata(
        podcastUuid: String,
        episodeUuid: String
    ) async throws -> EpisodeTranscriptData

    /// The AI-generated episode summary from the generated-metadata envelope,
    /// or nil when the backend has none for this episode.
    func loadEpisodeSummary(
        podcastUuid: String,
        episodeUuid: String
    ) async throws -> String?
}
