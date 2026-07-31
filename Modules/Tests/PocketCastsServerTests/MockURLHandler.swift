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
    func send(request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> Void) -> RequestCancellation? {
        do {
            let (data, response) = try handler(request)
            completion(data, response, nil)
        } catch {
            completion(nil, nil, error)
        }
        return nil
    }
}

extension URLConnection {
    /// A convenient initializer to pass a block which returns data, response, and error for a given URLRequest.
    /// - Parameter mockHandler: The handler block (URLRequest) throws -> (Data, URLResponse?)
    convenience init(mockHandler: @escaping MockRequestHandler.Handler) {
        // pinsOrigin: false keeps test policies stateless — no UserDefaults suite
        // is created or accumulated per test, and runs can never cross-contaminate.
        let policy = ServerOriginPolicy(
            buildOrigin: "https://tests.invalid",
            defaults: UserDefaults(suiteName: "MockURLHandler.ephemeral") ?? .standard,
            allowInsecureLoopback: false,
            pinsOrigin: false
        )
        self.init(handler: MockRequestHandler(handler: mockHandler), originPolicy: policy)
    }
}
