import Foundation

/// A mutable box for handing a value across an isolation boundary where ordering is
/// established externally (typically a semaphore or dispatch-group wait). The box itself
/// performs no synchronization — use only where a happens-before edge already exists.
public final class UncheckedSendableBox<Value>: @unchecked Sendable {
    public var value: Value

    public init(_ value: Value) {
        self.value = value
    }
}
