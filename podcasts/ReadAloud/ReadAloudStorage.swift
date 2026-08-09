import AVFoundation
import CryptoKit
import Foundation
import PocketCastsReadAloud
import PocketCastsUtils
import Synchronization

/// On-disk layout for Read Aloud.
///
/// Both directories live under `Documents/` rather than `Caches/`:
///
/// - **Sources** must survive: the retained document is user content that
///   outlives every narration made from it, and the reading screen and any
///   re-narration read it back. `Caches/` would let the system purge it under
///   disk pressure and silently orphan the document. Imported files skip backups
///   because the user has the original elsewhere; composed text is itself the
///   original, so it remains backed up. One file per document, shared by all of
///   that document's narrations.
/// - **Workspaces** must survive too, which is the non-obvious half: chunk files
///   *are* the resume checkpoint. Putting them in `Caches/` would mean a purge
///   between launches quietly discards completed work the DB still claims
///   exists. Imported sources are excluded from backup because the user keeps the
///   original elsewhere; composed sources are the original and remain backed up.
nonisolated struct ReadAloudStorage: Sendable {
    private let rootURL: URL
    private let chunkValidator: @Sendable (URL) -> Bool

    /// Serializes the two sides of filesystem/database reconciliation. A caller
    /// that creates a source and its database row must hold this lock across both
    /// operations; launch sweeping holds the same lock while it snapshots the DB
    /// and removes files. Keeping the lock synchronous makes that transaction
    /// impossible to interleave without introducing an actor hop between the file
    /// and database writes.
    private static let reconciliationLock = Mutex(())

    static let `default` = ReadAloudStorage(
        rootURL: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/read_aloud", isDirectory: true)
    )

    init(
        rootURL: URL,
        chunkValidator: @escaping @Sendable (URL) -> Bool = Self.isReadableAudioChunk
    ) {
        self.rootURL = rootURL
        self.chunkValidator = chunkValidator
    }

    var sourcesURL: URL { rootURL.appendingPathComponent("sources", isDirectory: true) }
    private var importedSourcesURL: URL { sourcesURL.appendingPathComponent("imported", isDirectory: true) }
    private var composedSourcesURL: URL { sourcesURL.appendingPathComponent("composed", isDirectory: true) }
    var workURL: URL { rootURL.appendingPathComponent("work", isDirectory: true) }

    /// Use this around a source/draft write and the database transaction that
    /// makes it live:
    ///
    ///     try storage.withReconciliationLock {
    ///         let path = try storage.writeSource(...)
    ///         guard dataManager.readAloud.add(...) else { ... }
    ///     }
    ///
    /// Do not call another method documented as acquiring this lock from inside
    /// `operation`; `Mutex` is intentionally non-recursive.
    func withReconciliationLock<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        try Self.reconciliationLock.withLock { _ in
            try operation()
        }
    }

    // MARK: - Sources

    /// Copies a picked or shared file in and returns the path to store on the
    /// document row, relative to the sources directory.
    func importSource(from url: URL, documentUuid: String) throws -> String {
        let filename = Self.sourceFilename(documentUuid: documentUuid, pathExtension: url.pathExtension)
        let relativePath = "imported/\(filename)"
        let destination = try preparedImportedSourcesDirectory().appendingPathComponent(filename, isDirectory: false)

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
        let filename = Self.sourceFilename(documentUuid: documentUuid, pathExtension: "txt")
        let relativePath = "composed/\(filename)"
        let destination = try preparedComposedSourcesDirectory().appendingPathComponent(filename, isDirectory: false)

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

    /// Engines render to a generation-scoped temporary path. Only a validated,
    /// closed file is atomically renamed to `chunkURL`, so a process kill or a
    /// cancellation can never leave a partial file looking like a checkpoint.
    func partialChunkURL(narrationUuid: String, index: Int, generation: UInt64) -> URL {
        workspaceURL(narrationUuid: narrationUuid)
            .appendingPathComponent(
                String(format: "chunk-%05d.partial-%llu.caf", index, generation),
                isDirectory: false
            )
    }

    @discardableResult
    func prepareWorkspace(narrationUuid: String) throws -> URL {
        try withReconciliationLock {
            try prepareWorkspaceWithoutLock(narrationUuid: narrationUuid)
        }
    }

    private func prepareWorkspaceWithoutLock(narrationUuid: String) throws -> URL {
        let url = workspaceURL(narrationUuid: narrationUuid)
        try createDirectoryIfNeeded(at: url, excludedFromBackup: true)
        return url
    }

    /// Opens a workspace for this exact content/chunk/settings plan. A workspace
    /// without a manifest, or with a manifest from an incompatible plan, is
    /// discarded before any rendered index is trusted.
    @discardableResult
    func prepareWorkspace(
        narrationUuid: String,
        manifest: ReadAloudWorkspaceManifest
    ) throws -> URL {
        try withReconciliationLock {
            var workspace = workspaceURL(narrationUuid: narrationUuid)
            let manifestURL = self.manifestURL(narrationUuid: narrationUuid)

            if FileManager.default.fileExists(atPath: workspace.path) {
                let existing: ReadAloudWorkspaceManifest? = {
                    guard let data = try? Data(contentsOf: manifestURL) else { return nil }
                    return try? JSONDecoder().decode(ReadAloudWorkspaceManifest.self, from: data)
                }()
                if existing != manifest {
                    try FileManager.default.removeItem(at: workspace)
                }
            }

            workspace = try prepareWorkspaceWithoutLock(narrationUuid: narrationUuid)
            if !FileManager.default.fileExists(atPath: manifestURL.path) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
            }
            return workspace
        }
    }

    func manifestURL(narrationUuid: String) -> URL {
        workspaceURL(narrationUuid: narrationUuid)
            .appendingPathComponent("manifest.json", isDirectory: false)
    }

    /// Validates and atomically promotes one engine output into a durable
    /// checkpoint. `moveItem` is an atomic rename because both paths are in the
    /// same workspace directory; replacement uses the filesystem's atomic replace.
    func commitRenderedChunk(from temporaryURL: URL, narrationUuid: String, index: Int) throws {
        guard chunkValidator(temporaryURL) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw ReadAloudError.synthesisProducedNoAudio
        }

        let destination = chunkURL(narrationUuid: narrationUuid, index: index)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        }
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
            guard chunkValidator(url) else {
                // Old builds wrote directly to the final path, so validate on
                // read as well as promotion and repair any torn legacy checkpoint.
                try? FileManager.default.removeItem(at: url)
                continue
            }
            rendered.insert(index)
        }
        return rendered
    }

    // MARK: - Sweeping

    /// Removes retained files nothing references any more.
    ///
    /// The database and the filesystem can diverge for several reasons — a
    /// delete interrupted partway, a crash mid-render, a restore that brought
    /// back one and not the other — and every one of them leaves regenerable
    /// bytes that nothing will ever reclaim. Rather than making each delete path
    /// individually crash-safe, this reconciles the two on launch.
    ///
    /// Deliberately scoped to files this type owns. Generated *episodes* are not
    /// swept: those are visible `UserEpisode`s the user can see and delete, and
    /// removing someone's audio because a row looked wrong is far worse than
    /// leaving a stale file on disk.
    ///
    /// - Returns: how many entries were removed, for logging.
    @discardableResult
    func sweepOrphans(liveDocumentUuids: Set<String>, liveNarrationUuids: Set<String>) -> Int {
        withReconciliationLock {
            sweepOrphansWithoutLock(
                liveDocumentUuids: liveDocumentUuids,
                liveNarrationUuids: liveNarrationUuids
            )
        }
    }

    /// Takes the database snapshot under the reconciliation lock as well as the
    /// filesystem sweep. Importers use `withReconciliationLock` around their file
    /// and row writes, so neither side can observe the other's half-committed state.
    @discardableResult
    func sweepOrphans(
        liveIdentifiers: () -> (documentUuids: Set<String>, narrationUuids: Set<String>)
    ) -> Int {
        withReconciliationLock {
            let identifiers = liveIdentifiers()
            return sweepOrphansWithoutLock(
                liveDocumentUuids: identifiers.documentUuids,
                liveNarrationUuids: identifiers.narrationUuids
            )
        }
    }

    private func sweepOrphansWithoutLock(
        liveDocumentUuids: Set<String>,
        liveNarrationUuids: Set<String>
    ) -> Int {
        var removed = 0

        // New sources are separated by backup policy; legacy sources remain at
        // the root. Every file is still named for its document uuid.
        for directory in [sourcesURL, importedSourcesURL, composedSourcesURL] {
            for url in (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? [] {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let uuid = url.deletingPathExtension().lastPathComponent
                guard !liveDocumentUuids.contains(uuid) else { continue }
                if (try? FileManager.default.removeItem(at: url)) != nil {
                    removed += 1
                }
            }
        }

        // A workspace directory is named for its narration.
        for name in (try? FileManager.default.contentsOfDirectory(atPath: workURL.path)) ?? [] {
            guard !liveNarrationUuids.contains(name) else { continue }
            if (try? FileManager.default.removeItem(at: workURL.appendingPathComponent(name))) != nil {
                removed += 1
            }
        }

        return removed
    }

    // MARK: - Directories

    private func preparedImportedSourcesDirectory() throws -> URL {
        try createDirectoryIfNeeded(at: sourcesURL, excludedFromBackup: false)
        try createDirectoryIfNeeded(at: importedSourcesURL, excludedFromBackup: true)
        return importedSourcesURL
    }

    private func preparedComposedSourcesDirectory() throws -> URL {
        try createDirectoryIfNeeded(at: sourcesURL, excludedFromBackup: false)
        try createDirectoryIfNeeded(at: composedSourcesURL, excludedFromBackup: false)
        return composedSourcesURL
    }

    private func createDirectoryIfNeeded(at url: URL, excludedFromBackup: Bool) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        // Re-checked on every call, not only at creation, and failures
        // propagate: the backup exclusion documented above is a guarantee, and
        // a restore or an earlier failed attempt may have dropped it.
        var resourceURL = url
        if try resourceURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup != excludedFromBackup {
            var values = URLResourceValues()
            values.isExcludedFromBackup = excludedFromBackup
            try resourceURL.setResourceValues(values)
        }
    }

    private static func isReadableAudioChunk(_ url: URL) -> Bool {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64,
              size > 0,
              let file = try? AVAudioFile(forReading: url) else { return false }
        return file.length > 0
    }
}

/// Everything that makes an existing chunk index reusable. The manifest is
/// deliberately content-addressed rather than storing user text a second time.
nonisolated struct ReadAloudWorkspaceManifest: Codable, Equatable, Sendable {
    struct Chunk: Codable, Equatable, Sendable {
        let index: Int
        let textFingerprint: String
        let startsBlock: Bool
    }

    private static let schemaVersion = 1

    let version: Int
    let contentFingerprint: String
    let engineId: String
    let engineKind: Int32
    let providerId: String?
    let modelId: String?
    let voiceId: String
    let rate: Double
    let maxCharactersPerChunk: Int
    let chunkBoundary: String
    let chunks: [Chunk]

    init(
        document: ExtractedDocument,
        chunks: [NarrationChunk],
        engineId: String,
        engineKind: Int32,
        providerId: String?,
        modelId: String?,
        voiceId: String,
        rate: Double,
        maxCharactersPerChunk: Int,
        chunkBoundary: ChunkBoundary
    ) {
        version = Self.schemaVersion
        let content: String = document.blocks.map { block -> String in
            let kind = block.isHeading ? "h" : "p"
            return "\(kind):\(block.text.utf8.count):\(block.text)"
        }.joined(separator: "\u{0}")
        contentFingerprint = Self.fingerprint(content)
        self.engineId = engineId
        self.engineKind = engineKind
        self.providerId = providerId
        self.modelId = modelId
        self.voiceId = voiceId
        self.rate = rate
        self.maxCharactersPerChunk = maxCharactersPerChunk
        self.chunkBoundary = switch chunkBoundary {
        case .everyBlock: "everyBlock"
        case .headingsOnly: "headingsOnly"
        }
        self.chunks = chunks.map {
            Chunk(index: $0.index, textFingerprint: Self.fingerprint($0.text), startsBlock: $0.startsBlock)
        }
    }

    private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
