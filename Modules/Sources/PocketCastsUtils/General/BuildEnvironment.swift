import Foundation

/// Describes the type of build environment the app is running in.
/// Use `BuildEnvironment.current` to get the environment for the current running build.
public enum BuildEnvironment: Sendable {
    /// From Xcode, or another DEBUG build
    case debug

    /// A release build distributed through TestFlight
    case testFlight

    /// A release build
    case appStore

    /// Returns the `BuildEnvironment` for the current build
    public static let current: BuildEnvironment = .determineCurrentEnvironment

    /// Determines the current environment by:
    /// - If the DEBUG or STAGING preprocessor macros are set, return `.debug`
    /// - For a release build carrying a sandbox App Store receipt, return `.testFlight`
    /// - For anything else, return `.appStore`
    private static var determineCurrentEnvironment: BuildEnvironment {
        #if DEBUG || STAGING
        return .debug
        #else
        // TestFlight builds receive a sandbox receipt; App Store builds get the
        // production one. No receipt at all (e.g. simulator release) is treated
        // as App Store — the conservative default for release-only affordances.
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return .testFlight
        }
        return .appStore
        #endif
    }
}
