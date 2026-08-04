// Fixture for pocketcasts.server-module-raw-urlsession-transport: first-party
// server traffic must use URLConnection, never a raw URLSession task.
import Foundation

enum RawURLSessionTransportFixture {
    static func bypassesTransport(request: URLRequest, completion: @escaping @Sendable (Data?) -> Void) {
        // ruleid: pocketcasts.server-module-raw-urlsession-transport
        URLSession.shared.dataTask(with: request) { data, _, _ in
            completion(data)
        }.resume()
    }

    static func bypassesTransportAsync(request: URLRequest) async throws -> Data {
        // ruleid: pocketcasts.server-module-raw-urlsession-transport
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    static func usesTransport(connection: URLConnection, request: URLRequest, completion: @escaping @Sendable (Data?) -> Void) {
        // ok: pocketcasts.server-module-raw-urlsession-transport
        connection.send(request: request) { data, _, _ in
            completion(data)
        }
    }
}

struct InjectedRawURLSessionTransportFixture {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func bypassesTransport(request: URLRequest) async throws -> Data {
        // ruleid: pocketcasts.server-module-raw-urlsession-transport
        let (data, _) = try await session.data(for: request)
        return data
    }
}

struct TransportDependencies {
    let session: URLSession
    let defaults: UserDefaults
    let token: String
}

struct EvasiveRawURLSessionTransportFixture {
    let deps: TransportDependencies

    func bypassesTransportInlineSession(request: URLRequest) async throws -> Data {
        // ruleid: pocketcasts.server-module-raw-urlsession-transport
        let (data, _) = try await URLSession(configuration: .ephemeral).data(for: request)
        return data
    }

    func bypassesTransportInlineSessionTask(request: URLRequest, completion: @escaping @Sendable (Data?) -> Void) {
        // ruleid: pocketcasts.server-module-raw-urlsession-transport
        URLSession(configuration: .default).dataTask(with: request) { data, _, _ in
            completion(data)
        }.resume()
    }

    func bypassesTransportInlineSessionDownload(url: URL) async throws -> URL {
        // ruleid: pocketcasts.server-module-raw-urlsession-transport
        let (location, _) = try await URLSession(configuration: .ephemeral).download(from: url)
        return location
    }

    func bypassesTransportNestedReceiver(request: URLRequest) async throws -> Data {
        // ruleid: pocketcasts.server-module-raw-urlsession-transport
        let (data, _) = try await deps.session.data(for: request)
        return data
    }

    func bypassesTransportSelfNestedReceiver(request: URLRequest) async throws -> Data {
        // ruleid: pocketcasts.server-module-raw-urlsession-transport
        let (data, _) = try await self.deps.session.data(for: request)
        return data
    }

    func encodesString(someString: String) -> Data? {
        // ok: pocketcasts.server-module-raw-urlsession-transport
        someString.data(using: .utf8)
    }

    func encodesStringLossily(someString: String) -> Data? {
        // ok: pocketcasts.server-module-raw-urlsession-transport
        someString.data(using: .utf8, allowLossyConversion: true)
    }

    func encodesNestedString() -> Data? {
        // ok: pocketcasts.server-module-raw-urlsession-transport
        deps.token.data(using: .utf8)
    }

    func readsDefaults(key: String) -> Data? {
        // ok: pocketcasts.server-module-raw-urlsession-transport
        UserDefaults.standard.data(forKey: key)
    }

    func readsNestedDefaults(key: String) -> Data? {
        // ok: pocketcasts.server-module-raw-urlsession-transport
        deps.defaults.data(forKey: key)
    }

    func canonicalizesViaStaticHelper(request: URLRequest) throws -> Data {
        // ok: pocketcasts.server-module-raw-urlsession-transport
        try AppAttestCanonicalRequest.data(for: request)
    }
}
