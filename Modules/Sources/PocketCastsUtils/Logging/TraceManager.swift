import Foundation

// @unchecked Sendable: `traceHandler` is assigned once via `setup(handler:)` during app
// launch, before any tracing happens, and is only read afterwards.
public final class TraceManager: @unchecked Sendable {
    public static let shared = TraceManager()

    private var traceHandler: TraceHandlingProtocol?

    public func setup(handler: TraceHandlingProtocol) {
        traceHandler = handler
    }

    public func beginTracing(eventName: String) -> AnyObject? {
        traceHandler?.beginTracing(eventName: eventName)
    }

    public func endTracing(trace: AnyObject?) {
        guard let trace else { return }

        traceHandler?.endTracing(trace: trace)
    }
}

public protocol TraceHandlingProtocol {
    func beginTracing(eventName: String) -> AnyObject?
    func endTracing(trace: AnyObject)
}
