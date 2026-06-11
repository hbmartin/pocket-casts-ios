import Foundation

/// Runs a synchronous data-layer call on a background queue so async callers
/// never block the main thread. Used by the repository protocols' default
/// async implementations; conformers with natively async reads override them.
func runOffMainThread<T>(_ work: @escaping () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: work())
        }
    }
}
