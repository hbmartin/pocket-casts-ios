import Foundation
import PocketCastsUtils

/// On-disk layout for Read Aloud.
///
/// Both directories live under `Documents/` rather than `Caches/`, and both are
/// excluded from backups — but for opposite reasons:
///
/// - **Sources** must survive: the retained document is user content that
///   outlives every narration made from it, and the reading screen and any
///   re-narration read it back. `Caches/` would let the system purge it under
///   disk pressure and silently orphan the document. It skips backups only
///   because the user has the original elsewhere. One file per document, shared
///   by all of that document's narrations.
/// - **Workspaces** must survive too, which is the non-obvious half: chunk files
///   *are* the resume checkpoint. Putting them in `Caches/` would mean a purge
///   between launches quietly discards completed work the DB still claims
///   exists.
nonisolated struct ReadAloudStorage: Sendable {
    private let rootURL: URL

    static let `default` = ReadAloudStorage(
        rootURL: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/read_aloud", isDirectory: true)
    )

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    var sourcesURL: URL { rootURL.appendingPathComponent("sources", isDirectory: true) }
    var workURL: URL { rootURL.appendingPathComponent("work", isDirectory: true) }

    // MARK: - Sources

    /// Copies a picked or shared file in and returns the path to store on the
    /// document row, relative to the sources directory.
    func importSource(from url: URL, documentUuid: String) throws -> String {
        let relativePath = Self.sourceFilename(documentUuid: documentUuid, pathExtension: url.pathExtension)
        let destination = try preparedSourcesDirectory().appendingPathComponent(relativePath, isDirectory: false)

        // Shared files arrive security-scoped (picker copies don't, and return
        // false here); the scope must span the copy and survive a throw.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: url, to: destination)
        return relativePath
    }

    /// Writes composed text as a source document, so pasted text is not a
    /// special case anywhere downstream.
    func writeSource(text: String, documentUuid: String) throws -> String {
        let relativePath = Self.sourceFilename(documentUuid: documentUuid, pathExtension: "txt")
        let destination = try preparedSourcesDirectory().appendingPathComponent(relativePath, isDirectory: false)

        try text.write(to: destination, atomically: true, encoding: .utf8)
        return relativePath
    }

    /// Resolved from the relative stored path: the container path changes across
    /// installs and OS upgrades, so an absolute path on the row would rot.
    func sourceURL(relativePath: String) -> URL {
        sourcesURL.appendingPathComponent(relativePath, isDirectory: false)
    }

    func deleteSource(relativePath: String) {
        try? FileManager.default.removeItem(at: sourceURL(relativePath: relativePath))
    }

    private static func sourceFilename(documentUuid: String, pathExtension: String) -> String {
        let ext = pathExtension.isEmpty ? "txt" : pathExtension.lowercased()
        return "\(documentUuid).\(ext)"
    }

    // MARK: - Workspaces

    func workspaceURL(narrationUuid: String) -> URL {
        workURL.appendingPathComponent(narrationUuid, isDirectory: true)
    }

    func chunkURL(narrationUuid: String, index: Int) -> URL {
        // Zero-padded so a directory listing sorts in narration order, which
        // makes a half-finished workspace readable when debugging.
        workspaceURL(narrationUuid: narrationUuid)
            .appendingPathComponent(String(format: "chunk-%05d.caf", index), isDirectory: false)
    }

    @discardableResult
    func prepareWorkspace(narrationUuid: String) throws -> URL {
        let url = workspaceURL(narrationUuid: narrationUuid)
        try createDirectoryIfNeeded(at: url)
        return url
    }

    func deleteWorkspace(narrationUuid: String) {
        try? FileManager.default.removeItem(at: workspaceURL(narrationUuid: narrationUuid))
    }

    /// Which chunk indices are already rendered.
    ///
    /// The filesystem, not the DB column, is the authority here: the row is
    /// bumped after the file lands, so a kill in between leaves the count one
    /// behind, and trusting the count would silently drop a rendered chunk.
    func renderedChunkIndices(narrationUuid: String, chunkCount: Int) -> Set<Int> {
        var rendered: Set<Int> = []
        for index in 0..<max(chunkCount, 0) {
            let url = chunkURL(narrationUuid: narrationUuid, index: index)
            guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64,
                  size > 0 else { continue }
            rendered.insert(index)
        }
        return rendered
    }

    // MARK: - Directories

    private func preparedSourcesDirectory() throws -> URL {
        try createDirectoryIfNeeded(at: sourcesURL)
        return sourcesURL
    }

    private func createDirectoryIfNeeded(at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        // Re-checked on every call, not only at creation, and failures
        // propagate: the backup exclusion documented above is a guarantee, and
        // a restore or an earlier failed attempt may have dropped it.
        var resourceURL = url
        if try resourceURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup != true {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try resourceURL.setResourceValues(values)
        }
    }
}
