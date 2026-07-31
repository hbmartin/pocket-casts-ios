import CryptoKit
import Foundation

public enum CorpusJSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: CorpusJSONValue]), array([CorpusJSONValue]), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: CorpusJSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([CorpusJSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct CorpusArtifactDescriptor: Codable, Equatable, Sendable {
    public let url: URL
    public let mediaType: String
    public let format: String
    public let sha256: String
    public let source: String
    public let language: String
    public let provenance: [String: CorpusJSONValue]
}

public struct CorpusManifest: Codable, Equatable, Sendable {
    public struct Release: Codable, Equatable, Sendable {
        public let id: String
        public let language: String
    }

    public struct Chapter: Codable, Equatable, Sendable {
        public let title: String
        public let timestamp: String?
        public let startTime: Double
    }

    public let release: Release
    public let language: String
    public let transcripts: [CorpusArtifactDescriptor]
    public let fingerprints: [CorpusArtifactDescriptor]
    public let summary: String?
    public let chapters: [Chapter]?
}

public enum CorpusClientError: Error, Equatable, Sendable {
    case unavailable
    case invalidManifest
    case externalArtifactURL
    case hashMismatch
}

public actor CorpusManifestClient {
    public static let shared = CorpusManifestClient()

    private struct Cached: Sendable {
        let etag: String
        let data: Data
    }

    private let connection: URLConnection
    private var cache: [URL: Cached] = [:]
    private var cacheOrder: [URL] = []
    private var cacheCost = 0
    private static let maximumCacheEntries = 64
    private static let maximumCacheBytes = 16 * 1024 * 1024

    public init(connection: URLConnection = URLConnection(handler: URLSession.shared)) {
        self.connection = connection
    }

    public func manifest(episodeUUID: String, acceptLanguage: String? = nil) async throws -> CorpusManifest {
        var pathSegmentAllowed = CharacterSet.urlPathAllowed
        pathSegmentAllowed.remove(charactersIn: "/")
        guard let escaped = episodeUUID.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed),
              let url = URL(string: ServerConstants.Urls.api() + "corpus/episodes/\(escaped)/manifest")
        else { throw CorpusClientError.invalidManifest }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: ServerConstants.HttpHeaders.accept)
        if let acceptLanguage { request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language") }
        let data = try await revalidatedData(for: request)
        return try JSONDecoder().decode(CorpusManifest.self, from: data)
    }

    /// Shared capability gate and preferred-language construction used by all
    /// corpus consumers.
    public func availableManifest(episodeUUID: String) async throws -> CorpusManifest? {
        guard await ServerCapabilitiesClient.shared.load()?.features.corpus == true else { return nil }
        return try await manifest(
            episodeUUID: episodeUUID,
            acceptLanguage: Locale.preferredLanguages.joined(separator: ",")
        )
    }

    public func artifact(_ descriptor: CorpusArtifactDescriptor) async throws -> Data {
        guard isBackendURL(descriptor.url) else { throw CorpusClientError.externalArtifactURL }
        let data = try await revalidatedData(for: URLRequest(url: descriptor.url, cachePolicy: .reloadIgnoringLocalCacheData))
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == descriptor.sha256.lowercased() else { throw CorpusClientError.hashMismatch }
        return data
    }

    private func revalidatedData(for original: URLRequest) async throws -> Data {
        guard let url = original.url else { throw CorpusClientError.invalidManifest }
        var request = original
        let cached = cachedValue(for: url)
        if let cached { request.setValue(cached.etag, forHTTPHeaderField: ServerConstants.HttpHeaders.ifNoneMatch) }
        let (data, response) = try await connection.send(request: request)
        guard let http = response as? HTTPURLResponse else { throw CorpusClientError.unavailable }
        if http.statusCode == ServerConstants.HttpConstants.notModified, let cached { return cached.data }
        guard http.statusCode == ServerConstants.HttpConstants.ok, let data else { throw CorpusClientError.unavailable }
        if let etag = http.value(forHTTPHeaderField: ServerConstants.HttpHeaders.etag) {
            store(Cached(etag: etag, data: data), for: url)
        }
        return data
    }

    private func cachedValue(for url: URL) -> Cached? {
        guard let value = cache[url] else { return nil }
        cacheOrder.removeAll { $0 == url }
        cacheOrder.append(url)
        return value
    }

    private func store(_ value: Cached, for url: URL) {
        if let previous = cache.updateValue(value, forKey: url) {
            cacheCost -= previous.data.count
            cacheOrder.removeAll { $0 == url }
        }
        cacheCost += value.data.count
        cacheOrder.append(url)

        while cache.count > Self.maximumCacheEntries || cacheCost > Self.maximumCacheBytes {
            guard let oldest = cacheOrder.first else { break }
            cacheOrder.removeFirst()
            if let evicted = cache.removeValue(forKey: oldest) {
                cacheCost -= evicted.data.count
            }
        }
    }

    private func isBackendURL(_ url: URL) -> Bool {
        ServerOriginPolicy.shared.isSameOrigin(url)
    }
}
