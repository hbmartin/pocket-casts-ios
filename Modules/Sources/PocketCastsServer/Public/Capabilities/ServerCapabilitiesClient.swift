import Foundation
import PocketCastsUtils

public struct ServerCapabilities: Codable, Equatable, Sendable {
    public struct Features: Codable, Equatable, Sendable {
        public let avatar: Bool
        public let folderSuggestions: Bool
        public let corpus: Bool
    }

    public let serverVersion: String
    public let appAttestMode: String
    public let features: Features
}

public struct ServerStatusSnapshot: Equatable, Sendable {
    public let originState: ServerOriginPolicy.State
    public let livenessStatus: Int?
    public let discoverStatus: Int?
    public let artworkStatus: Int?
    public let capabilities: ServerCapabilities?
}

public actor ServerCapabilitiesClient {
    public static let shared = ServerCapabilitiesClient()

    private let connection: URLConnection
    private var cachedCapabilities: ServerCapabilities?

    public init(connection: URLConnection = URLConnection(handler: URLSession.shared)) {
        self.connection = connection
    }

    public func load(force: Bool = false) async -> ServerCapabilities? {
        if !force, let cachedCapabilities { return cachedCapabilities }
        guard let url = URL(string: ServerConstants.Urls.api() + "api/v1/capabilities") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15.seconds)
        request.setValue("application/json", forHTTPHeaderField: ServerConstants.HttpHeaders.accept)
        do {
            let (data, response) = try await connection.send(request: request)
            guard (response as? HTTPURLResponse)?.statusCode == ServerConstants.HttpConstants.ok, let data else { return nil }
            let decoded = try JSONDecoder().decode(ServerCapabilities.self, from: data)
            cachedCapabilities = decoded
            return decoded
        } catch {
            return nil
        }
    }

    /// Diagnostics for the Settings server-status screen. The capability call
    /// is attested; the other probes are representative public routes.
    public func statusSnapshot() async -> ServerStatusSnapshot {
        async let liveness = status(path: "livez")
        async let discover = status(path: "discover/ios/content_v3.json")
        async let artwork = status(path: "discover/images/artwork/light/280/1.png")
        async let capabilities = load(force: true)
        return await ServerStatusSnapshot(
            originState: ServerOriginPolicy.shared.state,
            livenessStatus: liveness,
            discoverStatus: discover,
            artworkStatus: artwork,
            capabilities: capabilities
        )
    }

    private func status(path: String) async -> Int? {
        guard let origin = ServerOriginPolicy.shared.origin,
              let url = URL(string: path, relativeTo: origin)?.absoluteURL
        else { return nil }
        do {
            let (_, response) = try await connection.send(request: URLRequest(url: url))
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }
}
