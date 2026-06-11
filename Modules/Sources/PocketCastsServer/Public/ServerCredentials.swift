import Foundation

public enum ServerCredentials {
    /// Secret needed to share one or more podcasts
    // nonisolated(unsafe): assigned once during app startup from generated credentials.
    nonisolated(unsafe) public static var sharing = ""
}
