import Foundation

/// A sync folder rooted at any Files.app location the user picked with a
/// document picker, retained across launches via a security-scoped
/// bookmark.
///
/// The picker itself lives app-side (UIKit); this type receives the picked
/// URL's bookmark data. Every operation brackets
/// `startAccessingSecurityScopedResource` and runs under file coordination
/// so provider extensions (Dropbox, Drive, …) stay coherent.
///
/// There are no change notifications for provider folders: the manager
/// drives `FolderScanner` on its scan schedule instead. `startChangeMonitoring`
/// is therefore a no-op here.
public actor BookmarkSyncFolder: SyncFolder {
    nonisolated public let kind: SyncFolderKind = .securityScopedBookmark

    private var bookmarkData: Data
    private var resolvedRoot: URL?
    /// Set when the bookmark was refreshed during resolution; the owner
    /// should persist the new data.
    public private(set) var refreshedBookmarkData: Data?

    public init(bookmarkData: Data) {
        self.bookmarkData = bookmarkData
    }

    /// Creates bookmark data for a freshly picked folder URL. Call from the
    /// document-picker delegate while the URL's implicit access window is
    /// still open, then init this actor with the result.
    public static func makeBookmarkData(forPickedFolder url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try url.bookmarkData()
    }

    public func rootURL() throws -> URL {
        if let resolvedRoot { return resolvedRoot }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale) else {
            throw SyncFolderError.bookmarkUnresolvable
        }
        if isStale {
            // Re-mint while the resolved URL still works so the next launch
            // doesn't have to rely on a stale bookmark.
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let refreshed = try? url.bookmarkData() {
                bookmarkData = refreshed
                refreshedBookmarkData = refreshed
            }
        }
        resolvedRoot = url
        return url
    }

    private func withAccess<T: Sendable>(_ body: (URL) async throws -> T) async throws -> T {
        let root = try rootURL()
        let accessing = root.startAccessingSecurityScopedResource()
        defer { if accessing { root.stopAccessingSecurityScopedResource() } }
        return try await body(root)
    }

    public func list(_ relativeDir: String) async throws -> [FolderEntry] {
        try await withAccess { root in
            try await CoordinatedFileIO.list(root: root, relativeDir: relativeDir)
        }
    }

    public func coordinatedRead<T: Sendable>(_ relativePath: String, _ body: @Sendable @escaping (URL) throws -> T) async throws -> T {
        try await withAccess { root in
            try await CoordinatedFileIO.read(root.appendingPathComponent(relativePath), body)
        }
    }

    public func coordinatedWrite(_ relativePath: String, data: Data) async throws {
        try await withAccess { root in
            try await CoordinatedFileIO.write(root.appendingPathComponent(relativePath), data: data)
        }
    }

    public func createDirectory(_ relativePath: String) async throws {
        try await withAccess { root in
            try await CoordinatedFileIO.createDirectory(root.appendingPathComponent(relativePath, isDirectory: true))
        }
    }

    public func coordinatedCopy(from localURL: URL, to relativePath: String) async throws {
        try await withAccess { root in
            try await CoordinatedFileIO.copy(from: localURL, to: root.appendingPathComponent(relativePath))
        }
    }

    public func coordinatedDelete(_ relativePath: String) async throws {
        try await withAccess { root in
            try await CoordinatedFileIO.delete(root.appendingPathComponent(relativePath))
        }
    }

    public func ensureMaterialized(_ relativePath: String) async throws -> URL {
        // A coordinated read forces the provider to materialize the item;
        // the URL is returned for immediate follow-up use (callers should
        // copy the bytes out inside their own coordinatedRead when they
        // need durability, since the provider may evict again).
        try await withAccess { root in
            let url = root.appendingPathComponent(relativePath)
            return try await CoordinatedFileIO.read(url) { actualURL in
                guard FileManager.default.fileExists(atPath: actualURL.path) else {
                    throw SyncFolderError.fileNotFound(relativePath)
                }
                return actualURL
            }
        }
    }

    public func startChangeMonitoring(_ handler: @escaping @Sendable (FolderChangeHint) -> Void) {
        // Provider folders push no notifications; the manager's scan
        // schedule (foreground, post-write, periodic, BGAppRefresh) is the
        // change source.
    }

    public func stopChangeMonitoring() {}
}
