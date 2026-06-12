import Foundation
import PocketCastsUtils

/// Runs a synchronous data-layer call on a background queue so async callers
/// never block the main thread. Used by the repository protocols' default
/// async implementations; conformers with natively async reads override them.
///
/// The closure is moved across threads exactly once and the caller awaits the
/// result, so the unchecked transfer is safe even though `work` (which captures
/// the not-yet-Sendable `DataManager`) cannot be marked `@Sendable` today.
func runOffMainThread<T>(_ work: @escaping () -> T) async -> T {
    let work = UncheckedSendable(work)
    return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: work.value())
        }
    }
}
