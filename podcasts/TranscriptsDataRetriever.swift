import Foundation
import PocketCastsUtils
import PocketCastsServer
import PocketCastsDataModel

actor TranscriptsDataRetriever {

    typealias Transcript = Episode.Metadata.Transcript

    private var dataRequestMap: [URL: Task<Data, Error>] = [:]

    private let cache: URLCache
    private let connection: URLConnection

    /// External publisher transcripts stay off the shared session so third-party
    /// hosts never see the app's cookie jar, and they bypass `URLConnection` so
    /// backend origin blocking cannot break URLs that were never on the backend.
    private let externalSession: URLSession

    public init(connection: URLConnection? = nil, cache: URLCache? = nil, externalSession: URLSession? = nil) {
        let transcriptCache = cache ?? URLCache(memoryCapacity: 1.megabytes, diskCapacity: 100.megabytes, diskPath: "transcripts")
        self.cache = transcriptCache

        if let connection {
            self.connection = connection
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = transcriptCache
            configuration.requestCachePolicy = .reloadRevalidatingCacheData
            self.connection = URLConnection(handler: URLSession(configuration: configuration))
        }

        if let externalSession {
            self.externalSession = externalSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = transcriptCache
            configuration.requestCachePolicy = .reloadRevalidatingCacheData
            self.externalSession = URLSession(configuration: configuration)
        }
    }

    public func loadTranscript(url: URL) async throws -> String? {
        let request = URLRequest(url: url)

        if let cachedResponse = cache.cachedResponse(for: request),
           let result = String(data: cachedResponse.data, encoding: .utf8),
           !result.trim().isEmpty {
            FileLog.shared.addMessage("Transcripts Data Retriever: returning cached data for transcript")
            Task {
                // trigger a background refresh to force cache update
                try? await loadTranscriptFromServer(url, previousResponse: cachedResponse)
            }
            return result
        }

        return try await loadTranscriptFromServer(url)
    }

    private func loadTranscriptFromServer(_ url: URL, previousResponse: CachedURLResponse? = nil) async throws -> String? {
        if let task = dataRequestMap[url] {
            return try await String(data: task.value, encoding: .utf8)
        }
        FileLog.shared.addMessage("Transcripts Data Retriever: requesting transcript data \(url)")

        let task = Task<Data, Error> {
            do {
                var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)
                if let previousResponse {
                    request.setEtagAndLastModifiedHeaders(cachedResponse: previousResponse)
                }
                let (responseData, response): (Data?, URLResponse?)
                if ServerOriginPolicy.shared.isSameOrigin(url) {
                    (responseData, response) = try await connection.send(request: request)
                } else {
                    (responseData, response) = try await externalSession.data(for: request)
                }
                let data = responseData ?? Data()
                defer {
                    dataRequestMap[url] = nil
                }

                guard let response, response.extractStatusCode() == 200 else {
                    FileLog.shared.addMessage("Transcripts Data Retriever: request failed for transcript url \(url).")
                    return data
                }

                let responseToCache = CachedURLResponse(response: response, data: data)
                cache.storeCachedResponse(responseToCache, for: request)
                FileLog.shared.addMessage("Transcripts Data Retriever: request succeeded for url \(url).")

                return data
            } catch {
                FileLog.shared.addMessage("Transcripts Data Retriever: request failed for url \(url): \(error.localizedDescription).")
                dataRequestMap[url] = nil
                throw error
            }
        }
        dataRequestMap[url] = task

        return try await String(data: task.value, encoding: .utf8)
    }
}
