import Foundation
import GRDB

/// GRDB `ValueObservation` support for `GRDBQueue` (B6 ValueObservation pilot).
///
/// This is the module-internal bridge between GRDB's observation machinery and
/// the `AsyncStream`-based API `DataManager` exposes to the app (see
/// `DatabaseObserving`): app code never sees GRDB types.
extension GRDBQueue {
    /// Observes the database region accessed by `fetch` and streams the fetched
    /// value: one initial value as soon as the first read completes, then a new
    /// value after every committed write transaction that touches the observed
    /// region. Consecutive duplicate values are dropped (`removeDuplicates`), so
    /// chatty writes that don't change the result don't wake consumers.
    ///
    /// The observed region is re-evaluated on every fetch, so closures that build
    /// their SQL dynamically (e.g. from a playlist row read in the same closure)
    /// stay correctly tracked. Cancelling the consuming task tears the
    /// observation down.
    func observe<Value: Equatable & Sendable>(
        _ fetch: @escaping @Sendable (Database) throws -> Value
    ) -> AsyncStream<Value> {
        let observation = ValueObservation.tracking(fetch).removeDuplicates()
        let dbPool = dbPool
        let logger = logger
        return AsyncStream { continuation in
            let task = Task {
                do {
                    for try await value in observation.values(in: dbPool) {
                        continuation.yield(value)
                    }
                } catch {
                    // Observation failures (e.g. the database being closed) end the
                    // stream; consumers treat a finished stream as "no more updates".
                    logger?.log(error: error, context: [:])
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
