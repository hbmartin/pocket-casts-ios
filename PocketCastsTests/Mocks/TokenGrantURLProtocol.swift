import Foundation

/// Intercepts `user/token` refresh-grant requests made through `URLSession.shared`
/// (the refresh grant goes via `ApiServerHandler.obtainToken`, which doesn't use the
/// injectable `URLConnection`). Register with `URLProtocol.registerClass`, set `stub`,
/// and clear both in tearDown. Tests run serially, so the unsynchronized statics are
/// only ever mutated between requests.
final class TokenGrantURLProtocol: URLProtocol {
    struct StubResponse {
        let statusCode: Int
        let body: Data
        var headers: [String: String] = [:]
    }

    // nonisolated(unsafe): set/cleared by serial tests; read once per intercepted request.
    nonisolated(unsafe) static var stub: (@Sendable (URLRequest) -> StubResponse)?

    private static let requestCounter = NSLock()
    // nonisolated(unsafe): guarded by requestCounter.
    nonisolated(unsafe) private static var interceptedRequestCount = 0

    static var requestCount: Int {
        requestCounter.withLock { interceptedRequestCount }
    }

    static func resetCount() {
        requestCounter.withLock { interceptedRequestCount = 0 }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        stub != nil && request.url?.path.hasSuffix("user/token") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCounter.withLock { Self.interceptedRequestCount += 1 }

        guard let url = request.url, let stubResponse = Self.stub?(request),
              let response = HTTPURLResponse(url: url, statusCode: stubResponse.statusCode, httpVersion: nil, headerFields: stubResponse.headers)
        else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "TokenGrantURLProtocol", code: 1))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stubResponse.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
