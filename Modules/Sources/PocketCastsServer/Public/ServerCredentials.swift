import Foundation

public enum ServerCredentials {
    private static let lock = NSLock()

    /// Secret needed to share one or more podcasts
    // nonisolated(unsafe): written once during app startup from generated credentials.
    nonisolated(unsafe) public private(set) static var sharing = ""

    // nonisolated(unsafe): written once under `lock` during app startup, alongside `sharing`.
    nonisolated(unsafe) private static var hasConfiguredSharing = false

    public static func configureSharing(_ value: String) {
        lock.lock()
        defer { lock.unlock() }

        precondition(!hasConfiguredSharing, "ServerCredentials.sharing configured more than once")
        sharing = value
        hasConfiguredSharing = true
    }
}
