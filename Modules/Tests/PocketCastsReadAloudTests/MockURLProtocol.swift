import Foundation

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

    /// NSLock-guarded handler table.
    /// @unchecked Sendable: state is only ever read or written while the lock is held.
    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [String: Handler] = [:]
        private var requests: [String: [URLRequest]] = [:]

        func set(_ handler: Handler?, for key: String) {
            lock.lock()
            defer { lock.unlock() }
            handlers[key] = handler
            if handler == nil { requests[key] = nil }
        }

        func handler(for key: String) -> Handler? {
            lock.lock()
            defer { lock.unlock() }
            return handlers[key]
        }

        func record(_ request: URLRequest, for key: String) {
            lock.lock()
            defer { lock.unlock() }
            requests[key, default: []].append(request)
        }

        func recorded(for key: String) -> [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return requests[key] ?? []
        }
    }

    private static let registry = Registry()

    static func register(apiKey: String, handler: @escaping Handler) {
        registry.set(handler, for: apiKey)
    }

    static func unregister(apiKey: String) {
        registry.set(nil, for: apiKey)
    }

    /// Requests seen for a key, so a test can assert on the shape of what was
    /// sent as well as what came back.
    static func requests(apiKey: String) -> [URLRequest] {
        registry.recorded(for: apiKey)
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
        let key = Self.apiKey(from: request)
        if let key { Self.registry.record(request, for: key) }

        let outcome: Outcome
        if let key, let handler = Self.registry.handler(for: key) {
            outcome = handler(request)
        } else {
            outcome = .respond(
                statusCode: 599,
                body: Data("MockURLProtocol: no handler registered for request".utf8)
            )
        }

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
