import Foundation

/// Wraps a non-`Sendable` value so it can cross an isolation boundary.
/// Use only when the value is handed over wholesale and the sending side
/// does not touch it afterwards — the compiler cannot verify this.
public struct UncheckedSendable<Value>: @unchecked Sendable {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}
