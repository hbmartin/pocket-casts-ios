import Foundation
@testable import PocketCastsFileSync

/// Dictionary-backed SyncFolder fake for engine tests: no disk, no
/// coordination, deterministic listings.
actor InMemorySyncFolder: SyncFolder {
    nonisolated let kind: SyncFolderKind = .securityScopedBookmark

    private var files: [String: Data] = [:]
    private var directories = Set<String>()
    private let root = URL(fileURLWithPath: "/in-memory-sync-folder")

    func rootURL() throws -> URL { root }

    func contents(of path: String) -> Data? { files[path] }

    func storedFilePaths() -> [String] { files.keys.sorted() }

    func createdDirectoryPaths() -> [String] { directories.sorted() }

    func list(_ relativeDir: String) async throws -> [FolderEntry] {
        let prefix = relativeDir.isEmpty ? "" : relativeDir + "/"
        var entries: [FolderEntry] = []
        var directories = Set<String>()
        for (path, data) in files where path.hasPrefix(prefix) {
            let remainder = String(path.dropFirst(prefix.count))
            let components = remainder.components(separatedBy: "/")
            if components.count > 1 {
                var partial = prefix
                for component in components.dropLast() {
                    partial += component
                    directories.insert(partial)
                    partial += "/"
                }
            }
            entries.append(FolderEntry(
                relativePath: path,
                sizeBytes: Int64(data.count),
                mtimeMs: 1000,
                isDirectory: false,
                isPlaceholder: false))
        }
        entries.append(contentsOf: directories.map {
            FolderEntry(relativePath: $0, sizeBytes: 0, mtimeMs: 1000, isDirectory: true, isPlaceholder: false)
        })
        return entries.sorted { $0.relativePath < $1.relativePath }
    }

    func coordinatedRead<T: Sendable>(_ relativePath: String, _ body: @Sendable @escaping (URL) throws -> T) async throws -> T {
        guard let data = files[relativePath] else {
            throw SyncFolderError.fileNotFound(relativePath)
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("inmemory-\(UUID().uuidString)")
        try data.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        return try body(temp)
    }

    func coordinatedWrite(_ relativePath: String, data: Data) async throws {
        files[relativePath] = data
    }

    func createDirectory(_ relativePath: String) async throws {
        directories.insert(relativePath)
    }

    func coordinatedCopy(from localURL: URL, to relativePath: String) async throws {
        files[relativePath] = try Data(contentsOf: localURL)
    }

    func coordinatedDelete(_ relativePath: String) async throws {
        files[relativePath] = nil
    }

    func ensureMaterialized(_ relativePath: String) async throws -> URL {
        guard files[relativePath] != nil else {
            throw SyncFolderError.fileNotFound(relativePath)
        }
        return root.appendingPathComponent(relativePath)
    }

    func startChangeMonitoring(_ handler: @escaping @Sendable (FolderChangeHint) -> Void) {}
    func stopChangeMonitoring() {}
}
