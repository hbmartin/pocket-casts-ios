import Foundation

/// Wraps a non-`Sendable` value so it can cross an isolation boundary.
/// Use only when the value is handed over wholesale and the sending side
/// does not touch it afterwards — the compiler cannot verify this.
/// @unchecked Sendable: deliberate transfer wrapper; the hand-over contract above is the safety argument.
public struct UncheckedSendable<Value>: @unchecked Sendable {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}
