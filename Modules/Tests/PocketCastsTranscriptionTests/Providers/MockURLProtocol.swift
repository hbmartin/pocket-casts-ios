import Foundation

/// Intercepts every request of a test `URLSession` and serves canned responses.
///
/// Handlers are registered **per API key**: every provider request carries its
/// key in an auth header, and each test uses a unique key, so parallel Swift
/// Testing runs stay isolated without serializing suites.
final class MockURLProtocol: URLProtocol {
    enum Outcome {
        case respond(statusCode: Int, headers: [String: String] = [:], body: Data = Data())
        case fail(any Error)

        static func json(_ string: String, statusCode: Int = 200, headers: [String: String] = [:]) -> Outcome {
            .respond(statusCode: statusCode, headers: headers, body: Data(string.utf8))
        }
    }

    typealias Handler = @Sendable (URLRequest) -> Outcome

    /// NSLock-guarded handler table. @unchecked Sendable justification: `handlers`
    /// is only ever read or written while `lock` is held.
    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [String: Handler] = [:]

        func set(_ handler: Handler?, for key: String) {
            lock.lock()
            defer { lock.unlock() }
            handlers[key] = handler
        }

        func handler(for key: String) -> Handler? {
            lock.lock()
            defer { lock.unlock() }
            return handlers[key]
        }
    }

    private static let registry = Registry()

    /// Registers `handler` for requests authenticated with `apiKey`.
    /// Pair with `unregister(apiKey:)` (e.g. via `defer`) to keep the table clean.
    static func register(apiKey: String, handler: @escaping Handler) {
        registry.set(handler, for: apiKey)
    }

    static func unregister(apiKey: String) {
        registry.set(nil, for: apiKey)
    }

    /// A session whose every request is served by this protocol.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// The auth headers the five providers use, checked in order.
    private static let keyHeaderFields = ["authorization", "xi-api-key", "x-goog-api-key"]

    private static func apiKey(from request: URLRequest) -> String? {
        for field in keyHeaderFields {
            if let value = request.value(forHTTPHeaderField: field) {
                // Normalize "Bearer <key>" / "Token <key>" schemes to the raw key.
                return value
                    .replacingOccurrences(of: "Bearer ", with: "")
                    .replacingOccurrences(of: "Token ", with: "")
            }
        }
        return nil
    }

    /// The request body: `URLProtocol` exposes bodies (including file uploads)
    /// only as a stream.
    static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }

        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let outcome: Outcome
        if let apiKey = Self.apiKey(from: request), let handler = Self.registry.handler(for: apiKey) {
            outcome = handler(request)
        } else {
            outcome = .respond(statusCode: 599, body: Data("MockURLProtocol: no handler registered for request".utf8))
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

    override func stopLoading() {}
}
