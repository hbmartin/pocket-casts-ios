import Foundation
import Synchronization

public final class TraceManager: Sendable {
    public static let shared = TraceManager()

    private let traceHandler = Mutex<(any TraceHandlingProtocol)?>(nil)

    public func setup(handler: TraceHandlingProtocol) {
        traceHandler.withLock {
            precondition($0 == nil, "TraceManager.setup(handler:) must only be called once.")
            $0 = handler
        }
    }

    public func beginTracing(eventName: String) -> AnyObject? {
        let handler = traceHandler.withLock { $0 }

        return handler?.beginTracing(eventName: eventName)
    }

    public func endTracing(trace: AnyObject?) {
        guard let trace else { return }

        let handler = traceHandler.withLock { $0 }

        handler?.endTracing(trace: trace)
    }
}

public protocol TraceHandlingProtocol: Sendable {
    func beginTracing(eventName: String) -> AnyObject?
    func endTracing(trace: AnyObject)
}
