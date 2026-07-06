import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

actor ShowInfoCoordinator: ShowInfoCoordinating {
    nonisolated static let shared = makeShared()

    /// Explicitly nonisolated factory: the init's default-argument thunks (and
    /// closure literals) are @MainActor-inferred under default isolation, but the
    /// static above initializes in a nonisolated context.
    nonisolated private static func makeShared() -> ShowInfoCoordinator {
        ShowInfoCoordinator(
            dataRetriever: ShowInfoDataRetriever(),
            podcastIndexChapterRetriever: PodcastIndexChapterDataRetriever(),
            generatedEpisodeMetadataRetriever: GeneratedEpisodeMetadataRetriever(),
            dataManager: .sharedManager,
            transcriptDataRetriever: TranscriptsDataRetriever()
        )
    }

    private let dataRetriever: ShowInfoDataRetriever
    private let podcastIndexChapterRetriever: PodcastIndexChapterDataRetriever
    private let generatedEpisodeMetadataRetriever: GeneratedEpisodeMetadataRetriever
    private let dataManager: DataManager
    private let transcriptDataRetriever: TranscriptsDataRetriever

    private var requestingShowInfo: [String: Task<Episode.Metadata?, Error>] = [:]
    private var requestingRawMetadata: [String: Task<String?, Error>] = [:]

    // No default arguments: their thunks are @MainActor-inferred under default
    // isolation, which would isolate this init away from nonisolated callers
    init(
        dataRetriever: ShowInfoDataRetriever,
        podcastIndexChapterRetriever: PodcastIndexChapterDataRetriever,
        generatedEpisodeMetadataRetriever: GeneratedEpisodeMetadataRetriever,
        dataManager: DataManager,
        transcriptDataRetriever: TranscriptsDataRetriever
    ) {
        self.dataRetriever = dataRetriever
        self.podcastIndexChapterRetriever = podcastIndexChapterRetriever
        self.generatedEpisodeMetadataRetriever = generatedEpisodeMetadataRetriever
        self.dataManager = dataManager
        self.transcriptDataRetriever = transcriptDataRetriever
    }

    func loadShowNotes(
        podcastUuid: String,
        episodeUuid: String
    ) async throws -> String {
        let metadata = try await loadShowInfo(podcastUuid: podcastUuid, episodeUuid: episodeUuid)
        return metadata?.showNotes ?? CacheServerHandler.noShowNotesMessage
    }

    func loadEpisodeArtworkUrl(
        podcastUuid: String,
        episodeUuid: String
    ) async throws -> URL? {
        let metadata = try await loadShowInfo(podcastUuid: podcastUuid, episodeUuid: episodeUuid)
        return metadata?.image.flatMap(URL.init(string:))
    }

    public func loadChapters(
        podcastUuid: String,
        episodeUuid: String
    ) async throws -> (metadata: [Episode.Metadata.EpisodeChapter]?, podcastIndex: [PodcastIndexChapter]?, generated: [GeneratedChapter]?) {
        let metadata = try await loadShowInfo(podcastUuid: podcastUuid, episodeUuid: episodeUuid)

        if let podcastIndexChapterUrl = metadata?.chaptersUrl,
           let chapters = try? await podcastIndexChapterRetriever.loadChapters(podcastIndexChapterUrl) {
            return (metadata: nil, podcastIndex: chapters.chapters, generated: nil)
        }

        if let chapters = metadata?.chapters, !chapters.isEmpty {
            return (metadata: chapters, podcastIndex: nil, generated: nil)
        }

        if FeatureFlag.generatedChapters.enabled,
           let chapters = try? await generatedEpisodeMetadataRetriever.loadMetadata(podcastUuid: podcastUuid, episodeUuid: episodeUuid).chapters,
           !chapters.isEmpty {
            return (metadata: nil, podcastIndex: nil, generated: chapters)
        }

        return (metadata: nil, podcastIndex: nil, generated: nil)
    }

    private func buildGeneratedTranscript(podcastUuid: String, episodeUuid: String) -> Episode.Metadata.Transcript {
        let format = TranscriptFormat.vtt
        let urlString = "\(ServerConstants.Urls.generatedTranscripts)\(podcastUuid)/\(episodeUuid).\(format.fileExtension)"
        return Episode.Metadata.Transcript(url: urlString, type: format.rawValue, language: nil)
    }

    public func loadTranscriptsMetadata(podcastUuid: String, episodeUuid: String) async throws -> EpisodeTranscriptData {
        let metadata = try await loadShowInfo(podcastUuid: podcastUuid, episodeUuid: episodeUuid)

        if FeatureFlag.generatedTranscripts.enabled {
            let externalTranscripts = metadata?.transcripts ?? []
            var pocketCastsTranscripts: [Episode.Metadata.Transcript] = []
            if let episode = dataManager.findEpisode(uuid: episodeUuid),
               let hasTranscript = episode.hasGeneratedTranscript {
                if hasTranscript {
                    let transcript = buildGeneratedTranscript(podcastUuid: podcastUuid, episodeUuid: episodeUuid)
                    pocketCastsTranscripts = [transcript]
                }
            } else {
                pocketCastsTranscripts = metadata?.pocketCastsTranscripts ?? []
            }

            let isDisplayingGenerated = externalTranscripts.isEmpty && !pocketCastsTranscripts.isEmpty
            let transcripts = externalTranscripts.isEmpty ? pocketCastsTranscripts : externalTranscripts
            return (transcripts: transcripts, hasGeneratedTranscripts: !pocketCastsTranscripts.isEmpty, isDisplayingGeneratedTranscript: isDisplayingGenerated)
        }

        guard let transcripts = metadata?.transcripts else {
            return (transcripts: [], hasGeneratedTranscripts: false, isDisplayingGeneratedTranscript: false)
        }
        return (transcripts: transcripts, hasGeneratedTranscripts: false, isDisplayingGeneratedTranscript: false)
    }

    @discardableResult
    func loadShowInfo(
        podcastUuid: String,
        episodeUuid: String
    ) async throws -> Episode.Metadata? {
        try await requestShowInfo(podcastUuid: podcastUuid, episodeUuid: episodeUuid)
    }

    @discardableResult
    func requestShowInfo(
        podcastUuid: String,
        episodeUuid: String
    ) async throws -> Episode.Metadata? {
        if let task = requestingShowInfo[episodeUuid] {
            return try await task.value
        }

        let task = Task<Episode.Metadata?, Error> { [weak self] in
            guard let self else { throw TaskError.nilSelf }

            do {
                let data = try await dataRetriever.loadEpisodeDataFromCache(for: podcastUuid, episodeUuid: episodeUuid)
                await setRequestingShowInfoToNil(for: episodeUuid)
                return await getShowInfo(for: data?.data(using: .utf8))
            } catch {
                await setRequestingShowInfoToNil(for: episodeUuid)
                throw error
            }
        }

        requestingShowInfo[episodeUuid] = task

        return try await task.value
    }

    private func setRequestingShowInfoToNil(for episodeUuid: String) {
        requestingShowInfo[episodeUuid] = nil
    }

    private func getShowInfo(for data: Data?) async -> Episode.Metadata? {
        guard let data else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(Episode.Metadata.self, from: data)
        } catch {
            return nil
        }
    }
}
