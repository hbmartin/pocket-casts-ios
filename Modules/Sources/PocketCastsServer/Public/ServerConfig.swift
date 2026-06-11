import Foundation
import PocketCastsDataModel

// @unchecked Sendable: delegates are assigned once during app startup, before
// any server communication happens.
public final class ServerConfig: @unchecked Sendable {
    public static let shared = ServerConfig()

    private var backgroundSessionHandler: (() -> Void)?

    // MARK: - App values required for Server communication

    public var syncDelegate: ServerSyncDelegate?
    public var playbackDelegate: ServerPlaybackDelegate?

    /// Error logger for reporting sync errors to crash reporting services.
    public var errorLogger: ErrorLogger?

    public func setBackgroundSessionCompletionHandler(handler: (() -> Void)?) {
        backgroundSessionHandler = handler
    }

    public func backgroundSessionCompletionHandler() -> (() -> Void)? {
        backgroundSessionHandler
    }
}
