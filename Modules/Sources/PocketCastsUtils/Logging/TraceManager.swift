import Foundation

// @unchecked Sendable: `traceHandler` is assigned once via `setup(handler:)` during app
// launch, before any tracing happens, and is only read afterwards.
public final class TraceManager: @unchecked Sendable {
    public static let shared = TraceManager()

    private let lock = NSLock()
    private var traceHandler: TraceHandlingProtocol?

    public func setup(handler: TraceHandlingProtocol) {
        lock.lock()
        defer { lock.unlock() }

        precondition(traceHandler == nil, "TraceManager.setup(handler:) must only be called once.")
        traceHandler = handler
    }

    public func beginTracing(eventName: String) -> AnyObject? {
        lock.lock()
        let handler = traceHandler
        lock.unlock()

        return handler?.beginTracing(eventName: eventName)
    }

    public func endTracing(trace: AnyObject?) {
        guard let trace else { return }

        lock.lock()
        let handler = traceHandler
        lock.unlock()

        handler?.endTracing(trace: trace)
    }
}

public protocol TraceHandlingProtocol {
    func beginTracing(eventName: String) -> AnyObject?
    func endTracing(trace: AnyObject)
}
