import Foundation
@testable import PocketCastsServer

struct MockRequestHandler {
    typealias Handler = (@Sendable (URLRequest) throws -> (Data?, URLResponse?))

    let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }
}

extension MockRequestHandler: RequestHandler {
    func send(request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        do {
            let (data, response) = try handler(request)
            completion(data, response, nil)
        } catch {
            completion(nil, nil, error)
        }
    }
}

extension URLConnection {
    /// A convenient initializer to pass a block which returns data, response, and error for a given URLRequest.
    /// - Parameter mockHandler: The handler block (URLRequest) throws -> (Data, URLResponse?)
    convenience init(mockHandler: @escaping MockRequestHandler.Handler) {
        let suite = "MockURLHandler.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let policy = ServerOriginPolicy(buildOrigin: "https://tests.invalid", defaults: defaults, allowInsecureLoopback: false)
        self.init(handler: MockRequestHandler(handler: mockHandler), originPolicy: policy)
    }
}
