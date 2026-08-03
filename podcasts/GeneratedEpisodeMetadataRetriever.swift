import Foundation
import PocketCastsServer
import PocketCastsUtils

nonisolated public struct GeneratedMetadataEnvelope: Decodable, Sendable {
    let summary: String?
    let chapters: [GeneratedChapter]?
}

struct GeneratedChapter: Decodable, Sendable {
    let title: String
    let timestamp: String
    let startTime: TimeInterval
}

/// Fetches AI-generated episode metadata and caches/coalesces in-flight requests.
public actor GeneratedEpisodeMetadataRetriever {
    private var dataRequestMap: [String: Task<GeneratedMetadataEnvelope, Error>] = [:]

    public init() {}

    public func loadMetadata(podcastUuid: String, episodeUuid: String) async throws -> GeneratedMetadataEnvelope {
        let cacheKey = "corpus:\(episodeUuid)"

        if let task = dataRequestMap[cacheKey] {
            return try await task.value
        }

        defer {
            dataRequestMap[cacheKey] = nil
        }

        let task = Task<GeneratedMetadataEnvelope, Error> { [weak self] in
            guard let self else { throw TaskError.nilSelf }
            guard let manifest = try await CorpusManifestClient.shared.availableManifest(episodeUUID: episodeUuid) else {
                throw Errors.corpusUnavailable
            }
            let chapters = manifest.chapters?.map {
                GeneratedChapter(
                    title: $0.title,
                    timestamp: $0.timestamp ?? Self.timestamp($0.startTime),
                    startTime: $0.startTime
                )
            }
            return GeneratedMetadataEnvelope(summary: manifest.summary, chapters: chapters)
        }
        dataRequestMap[cacheKey] = task

        return try await task.value
    }

    nonisolated private static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    enum Errors: Error {
        case corpusUnavailable
    }
}
