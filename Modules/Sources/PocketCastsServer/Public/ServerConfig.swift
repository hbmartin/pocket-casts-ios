import Foundation
import PocketCastsDataModel

// Delegates are assigned once during app startup, before
// @unchecked Sendable: delegate assignment finishes before concurrent server communication starts.
public final class ServerConfig: @unchecked Sendable {
    public static let shared = ServerConfig()

    // MARK: - App values required for Server communication

    public var syncDelegate: ServerSyncDelegate?
    public var playbackDelegate: ServerPlaybackDelegate?
    /// Error logger for reporting sync errors to crash reporting services.
    public var errorLogger: ErrorLogger?

    /// Call once on the main thread at launch so off-main reads of protected-data
    /// availability have a warm cache before the first sync runs.
    @MainActor public func warmProtectedDataAvailabilityCache() {
        _ = UserDefaults.isProtectedDataAvailable()
    }
}
