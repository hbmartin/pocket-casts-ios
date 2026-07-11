import Foundation
import PocketCastsUtils

/// A generic request handler to send URLRequests with a completion block
public protocol RequestHandler: Sendable {
    func send(request: URLRequest, completion: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void)
}

extension URLSession: RequestHandler {
    public func send(request: URLRequest, completion: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) {
        let task = dataTask(with: request, completionHandler: completion)
        task.resume()
    }
}

public final class URLConnection: Sendable {

    private let handler: RequestHandler

    public init(handler: RequestHandler) {
        self.handler = handler
    }

    public func sendSynchronousRequest(with request: URLRequest) throws -> (Data?, URLResponse?) {
        // The semaphore establishes the happens-before edge for the boxed result.
        let result = UncheckedSendableBox<(Data?, URLResponse?, Error?)>((nil, nil, nil))
        let semaphore = DispatchSemaphore(value: 0)

        handler.send(request: request) {
            result.value = ($0, $1, $2)

            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .distantFuture)
        let (data, response, error) = result.value
        if let error {
            throw error
        }
        return (data, response)
    }

    public func send(request: URLRequest, completion: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) {
        handler.send(request: request, completion: completion)
    }

    public func send(request: URLRequest) async throws -> (Data?, URLResponse?) {
        try await withCheckedThrowingContinuation { continuation in
            send(request: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data, response))
                }
            }
        }
    }
}
