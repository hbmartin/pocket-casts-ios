import Foundation
import PocketCastsDataModel
import Synchronization

/// Launch-time server dependencies protected for concurrent reads.
public final class ServerConfig: Sendable {
    public static let shared = ServerConfig()

    private struct State: Sendable {
        var syncDelegate: (any ServerSyncDelegate)?
        var playbackDelegate: (any ServerPlaybackDelegate)?
        var errorLogger: (any ErrorLogger)?
        var isConfigured = false
    }

    private let state = Mutex(State())

    // MARK: - App values required for Server communication

    public var syncDelegate: (any ServerSyncDelegate)? {
        state.withLock { $0.syncDelegate }
    }

    public var playbackDelegate: (any ServerPlaybackDelegate)? {
        state.withLock { $0.playbackDelegate }
    }

    /// Error logger for reporting sync errors to crash reporting services.
    public var errorLogger: (any ErrorLogger)? {
        state.withLock { $0.errorLogger }
    }

    var isConfigured: Bool {
        state.withLock { $0.isConfigured }
    }

    /// Installs all server dependencies exactly once, before background server work begins.
    ///
    /// - Returns: `true` when configuration was installed, or `false` when an earlier call won.
    @discardableResult
    public func configure(
        syncDelegate: any ServerSyncDelegate,
        playbackDelegate: any ServerPlaybackDelegate,
        errorLogger: any ErrorLogger
    ) -> Bool {
        state.withLock { state in
            guard !state.isConfigured else { return false }
            state.syncDelegate = syncDelegate
            state.playbackDelegate = playbackDelegate
            state.errorLogger = errorLogger
            state.isConfigured = true
            return true
        }
    }

    /// Call once on the main thread at launch so off-main reads of protected-data
    /// availability have a warm cache before the first sync runs.
    @MainActor public func warmProtectedDataAvailabilityCache() {
        _ = UserDefaults.isProtectedDataAvailable()
    }
}
