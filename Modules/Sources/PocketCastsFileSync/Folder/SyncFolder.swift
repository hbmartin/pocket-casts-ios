import Foundation

public enum SyncFolderKind: String, Sendable {
    /// The app's iCloud Drive container (visible in Files under the app's
    /// own folder). Reliable change notifications and background download.
    case ubiquity
    /// Any Files.app location the user picked (Dropbox, Drive, local, …),
    /// retained via a security-scoped bookmark. Change detection is
    /// scan-based because third-party File Providers push no notifications.
    case securityScopedBookmark
}

/// One item found in the folder, placeholder or materialized.
public struct FolderEntry: Equatable, Hashable, Sendable {
    /// Path relative to the folder root, "/"-separated, no leading slash.
    public let relativePath: String
    public let sizeBytes: Int64
    public let mtimeMs: Int64
    public let isDirectory: Bool
    /// True when the item exists in the cloud but its bytes are not local
    /// (iCloud .icloud placeholder or a non-materialized provider item).
    public let isPlaceholder: Bool

    public init(relativePath: String, sizeBytes: Int64, mtimeMs: Int64, isDirectory: Bool, isPlaceholder: Bool) {
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.mtimeMs = mtimeMs
        self.isDirectory = isDirectory
        self.isPlaceholder = isPlaceholder
    }

    public var fileName: String {
        relativePath.components(separatedBy: "/").last ?? relativePath
    }
}

/// A coarse "something changed" signal; consumers rescan rather than trust
/// per-item detail, because providers differ wildly in what they report.
public struct FolderChangeHint: Sendable {
    public let changedPaths: [String]

    public init(changedPaths: [String] = []) {
        self.changedPaths = changedPaths
    }
}

public enum SyncFolderError: Error, Sendable {
    /// The bookmark no longer resolves (folder deleted, permission revoked,
    /// provider uninstalled). The UI must ask the user to re-pick.
    case bookmarkUnresolvable
    /// iCloud is unavailable (no account, or Documents disabled).
    case ubiquityUnavailable
    case fileNotFound(String)
    /// The item never finished materializing within the timeout.
    case materializeTimeout(String)
    /// The folder was written by a newer format version than this app reads.
    case formatTooNew(found: Int32, supported: Int32)
}

/// Abstraction over the sync folder root, hiding the differences between
/// the iCloud ubiquity container and a picked (security-scoped) folder.
///
/// All paths are relative to the folder root. Implementations perform all
/// I/O through NSFileCoordinator so File Provider extensions observe
/// coherent reads and writes.
public protocol SyncFolder: Sendable {
    var kind: SyncFolderKind { get }

    /// Resolves the root URL (bookmark resolution / container lookup).
    func rootURL() async throws -> URL

    /// Recursively lists entries under a relative directory. Includes
    /// placeholders. Directories are listed as entries too.
    func list(_ relativeDir: String) async throws -> [FolderEntry]

    /// Coordinated read; `body` receives a URL whose bytes are local for
    /// the duration of the call (the coordinator materializes placeholders
    /// on provider-backed folders).
    func coordinatedRead<T: Sendable>(_ relativePath: String, _ body: @Sendable @escaping (URL) throws -> T) async throws -> T

    /// Coordinated whole-file write, creating intermediate directories.
    func coordinatedWrite(_ relativePath: String, data: Data) async throws

    /// Creates a directory (and intermediates) under the root. Must run
    /// inside the implementation's access bracket (security scope for
    /// picked folders).
    func ensureDirectoryExists(_ relativeDir: String) async throws

    /// Coordinated copy of a local file into the folder.
    func coordinatedCopy(from localURL: URL, to relativePath: String) async throws

    /// Coordinated delete. Missing files are not an error (another device
    /// may have deleted first).
    func coordinatedDelete(_ relativePath: String) async throws

    /// Ensures the item's bytes are local (triggers download if needed) and
    /// returns the concrete file URL.
    func ensureMaterialized(_ relativePath: String) async throws -> URL

    /// Starts delivering change hints (iCloud: NSMetadataQuery updates;
    /// picked folders: no-op — callers schedule scans instead).
    func startChangeMonitoring(_ handler: @escaping @Sendable (FolderChangeHint) -> Void) async

    func stopChangeMonitoring() async
}
