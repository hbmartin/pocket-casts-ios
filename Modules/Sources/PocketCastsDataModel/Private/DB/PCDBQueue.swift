import Foundation

public protocol PCDBQueue {
    func inDatabase(_ block: (PCDatabase) -> Void)

    func inTransaction(_ block: (PCDatabase, UnsafeMutablePointer<ObjCBool>) -> Void)

    func read(_ block: (PCDatabase) -> Void)

    func write(_ block: (PCDatabase) -> Void)

    /// Async read that schedules on the database engine's own reader pool rather
    /// than blocking a cooperative-pool thread.
    func read<T>(_ block: @Sendable @escaping (PCDatabase) throws -> T) async throws -> T

    /// Async write counterpart to `read(_:)`.
    func write<T>(_ block: @Sendable @escaping (PCDatabase) throws -> T) async throws -> T

    func close()
}
