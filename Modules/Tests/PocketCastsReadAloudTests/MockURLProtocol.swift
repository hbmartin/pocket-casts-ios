import Foundation
import Synchronization

/// Intercepts every request of a test `URLSession` and serves canned responses.
///
/// Mirrors `PocketCastsTranscriptionTests/Providers/MockURLProtocol` — test
/// targets can't import each other, so the pattern is duplicated rather than
/// shared. Handlers are registered **per API key**: every provider request
/// carries its key in an auth header and each test uses a unique one, so
/// parallel Swift Testing runs stay isolated without serializing suites.
final class MockURLProtocol: URLProtocol {
    enum Outcome {
        case respond(statusCode: Int, headers: [String: String] = [:], body: Data = Data())
        case fail(any Error)

        static func json(_ string: String, statusCode: Int = 200, headers: [String: String] = [:]) -> Outcome {
            .respond(statusCode: statusCode, headers: headers, body: Data(string.utf8))
        }
    }

    typealias Handler = @Sendable (URLRequest) -> Outcome

    /// The handler table and the requests seen for each key.
    ///
    /// Held in a `Mutex` rather than behind a hand-rolled lock, so the type is
    /// Sendable on its own terms instead of asserting it with
    /// `@unchecked Sendable` — the sibling in `PocketCastsTranscriptionTests`
    /// predates that pattern.
    private struct Registry: Sendable {
        var handlers: [String: Handler] = [:]
        var requests: [String: [URLRequest]] = [:]
    }

    private static let registry = Mutex(Registry())

    static func register(apiKey: String, handler: @escaping Handler) {
        registry.withLock { $0.handlers[apiKey] = handler }
    }

    static func unregister(apiKey: String) {
        registry.withLock {
            $0.handlers[apiKey] = nil
            $0.requests[apiKey] = nil
        }
    }

    /// Requests seen for a key, so a test can assert on the shape of what was
    /// sent as well as what came back.
    static func requests(apiKey: String) -> [URLRequest] {
        registry.withLock { $0.requests[apiKey] ?? [] }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func apiKey(from request: URLRequest) -> String? {
        request.value(forHTTPHeaderField: "xi-api-key")
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Record and look up together, but run the handler after releasing the
        // lock: it is test-supplied code and could re-enter.
        let handler: Handler? = Self.registry.withLock { registry in
            guard let key = Self.apiKey(from: request) else { return nil }
            registry.requests[key, default: []].append(request)
            return registry.handlers[key]
        }

        let outcome = handler?(request) ?? .respond(
            statusCode: 599,
            body: Data("MockURLProtocol: no handler registered for request".utf8)
        )

        switch outcome {
        case .respond(let statusCode, let headers, let body):
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: statusCode,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .fail(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // Responses are delivered synchronously in startLoading(), so by the
        // time a cancel could arrive there is nothing in flight to stop.
    }
}
