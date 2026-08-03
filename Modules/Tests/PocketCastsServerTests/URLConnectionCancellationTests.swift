import Foundation
import Synchronization
import Testing

@testable import PocketCastsServer

private final class CancellableRequestHandler: RequestHandler, Sendable {
    private struct State {
        var completion: (@Sendable (Data?, URLResponse?, Error?) -> Void)?
        var cancellationCount = 0
    }

    private let state = Mutex(State())

    var hasStarted: Bool { state.withLock { $0.completion != nil } }
    var cancellationCount: Int { state.withLock { $0.cancellationCount } }

    func send(
        request _: URLRequest,
        completion: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> RequestCancellation? {
        state.withLock { $0.completion = completion }
        return RequestCancellation { [weak self] in self?.cancel() }
    }

    private func cancel() {
        let completion = state.withLock { state in
            state.cancellationCount += 1
            defer { state.completion = nil }
            return state.completion
        }
        completion?(nil, nil, URLError(.cancelled))
    }
}

struct URLConnectionCancellationTests {
    @Test func cancellingAsyncSendCancelsUnderlyingRequest() async throws {
        let handler = CancellableRequestHandler()
        let connection = URLConnection(handler: handler)
        let request = URLRequest(url: try #require(URL(string: "https://example.com/resource")))
        let task = Task { try await connection.sendRaw(request: request) }

        for _ in 0 ..< 100 where !handler.hasStarted {
            await Task.yield()
        }
        try #require(handler.hasStarted)
        task.cancel()

        await #expect(throws: URLError.self) {
            try await task.value
        }
        #expect(handler.cancellationCount == 1)
    }
}
