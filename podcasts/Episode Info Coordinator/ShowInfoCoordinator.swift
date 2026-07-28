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

        if let chapters = try? await generatedEpisodeMetadataRetriever.loadMetadata(podcastUuid: podcastUuid, episodeUuid: episodeUuid).chapters,
           !chapters.isEmpty {
            return (metadata: nil, podcastIndex: nil, generated: chapters)
        }

        return (metadata: nil, podcastIndex: nil, generated: nil)
    }

    /// Reuses the generated-metadata retriever's request coalescing and URL
    /// cache — callers displaying both AI chapters and the summary trigger a
    /// single `-meta.json` fetch.
    public func loadEpisodeSummary(
        podcastUuid: String,
        episodeUuid: String
    ) async throws -> String? {
        try await generatedEpisodeMetadataRetriever.loadMetadata(podcastUuid: podcastUuid, episodeUuid: episodeUuid).summary
    }

    public func loadTranscriptsMetadata(podcastUuid: String, episodeUuid: String) async throws -> EpisodeTranscriptData {
        let metadata = try await loadShowInfo(podcastUuid: podcastUuid, episodeUuid: episodeUuid)

        if FeatureFlag.generatedTranscripts.enabled {
            let externalTranscripts = metadata?.transcripts ?? []
            var pocketCastsTranscripts: [Episode.Metadata.Transcript] = []
            if await ServerCapabilitiesClient.shared.load()?.features.corpus == true,
               let manifest = try? await CorpusManifestClient.shared.manifest(
                   episodeUUID: episodeUuid,
                   acceptLanguage: Locale.preferredLanguages.joined(separator: ",")
               ) {
                pocketCastsTranscripts = manifest.transcripts.compactMap {
                    // A manifest URL must stay on the pinned backend origin: a
                    // compromised manifest must not be able to point transcript
                    // rendering at an arbitrary external host.
                    guard ServerOriginPolicy.shared.isSameOrigin($0.url) else { return nil }
                    return Episode.Metadata.Transcript(url: $0.url.absoluteString, type: $0.mediaType, language: $0.language)
                }
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
                // Local-feed podcasts have no cache-server entry; their show info is
                // seeded into the cache from the parsed feed, and no request should
                // leave the device for them.
                let isLocalFeed = dataManager.findPodcast(uuid: podcastUuid, includeUnsubscribed: true)?.isLocalFeedSourced ?? false
                let data = try await dataRetriever.loadEpisodeDataFromCache(for: podcastUuid, episodeUuid: episodeUuid, useCacheOnly: isLocalFeed)
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
