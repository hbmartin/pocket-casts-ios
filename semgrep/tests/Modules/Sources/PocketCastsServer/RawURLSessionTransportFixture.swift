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
