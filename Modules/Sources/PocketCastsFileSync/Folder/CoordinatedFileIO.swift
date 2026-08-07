import Foundation

/// Shared NSFileCoordinator-based primitives for both folder kinds.
///
/// NSFileCoordinator's API is blocking, so every operation hops to a
/// utility queue and resumes a continuation. Coordination matters even for
/// the ubiquity container: it is what makes File Provider extensions
/// materialize placeholders on read and propagate writes promptly.
enum CoordinatedFileIO {
    private static let queue = DispatchQueue(label: "au.com.pocketcasts.filesync.io", qos: .utility)

    static func read<T: Sendable>(_ url: URL, _ body: @Sendable @escaping (URL) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinatorError: NSError?
                var result: Result<T, Error>?
                coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { actualURL in
                    result = Result { try body(actualURL) }
                }
                if let coordinatorError {
                    continuation.resume(throwing: coordinatorError)
                } else if let result {
                    continuation.resume(with: result)
                } else {
                    continuation.resume(throwing: SyncFolderError.fileNotFound(url.lastPathComponent))
                }
            }
        }
    }

    static func write(_ url: URL, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinatorError: NSError?
                var result: Result<Void, Error>?
                coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { actualURL in
                    result = Result {
                        try FileManager.default.createDirectory(
                            at: actualURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true)
                        try data.write(to: actualURL, options: .atomic)
                    }
                }
                if let coordinatorError {
                    continuation.resume(throwing: coordinatorError)
                } else if let result {
                    continuation.resume(with: result)
                } else {
                    continuation.resume(throwing: SyncFolderError.fileNotFound(url.lastPathComponent))
                }
            }
        }
    }

    static func createDirectory(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinatorError: NSError?
                var result: Result<Void, Error>?
                coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError) { actualURL in
                    result = Result {
                        try FileManager.default.createDirectory(
                            at: actualURL,
                            withIntermediateDirectories: true)
                    }
                }
                if let coordinatorError {
                    continuation.resume(throwing: coordinatorError)
                } else if let result {
                    continuation.resume(with: result)
                } else {
                    continuation.resume(throwing: SyncFolderError.fileNotFound(url.lastPathComponent))
                }
            }
        }
    }

    static func copy(from source: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinatorError: NSError?
                var result: Result<Void, Error>?
                coordinator.coordinate(readingItemAt: source, options: [],
                                       writingItemAt: destination, options: .forReplacing,
                                       error: &coordinatorError) { actualSource, actualDestination in
                    result = Result {
                        try FileManager.default.createDirectory(
                            at: actualDestination.deletingLastPathComponent(),
                            withIntermediateDirectories: true)
                        if FileManager.default.fileExists(atPath: actualDestination.path) {
                            try FileManager.default.removeItem(at: actualDestination)
                        }
                        try FileManager.default.copyItem(at: actualSource, to: actualDestination)
                    }
                }
                if let coordinatorError {
                    continuation.resume(throwing: coordinatorError)
                } else if let result {
                    continuation.resume(with: result)
                } else {
                    continuation.resume(throwing: SyncFolderError.fileNotFound(source.lastPathComponent))
                }
            }
        }
    }

    static func delete(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinatorError: NSError?
                var result: Result<Void, Error>?
                coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinatorError) { actualURL in
                    result = Result {
                        do {
                            try FileManager.default.removeItem(at: actualURL)
                        } catch where isMissingFileError(error) {
                            // Another device may have deleted first; that is success.
                        }
                    }
                }
                if let coordinatorError {
                    if isMissingFileError(coordinatorError) {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: coordinatorError)
                    }
                } else if let result {
                    continuation.resume(with: result)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == ENOENT)
    }

    /// Recursive listing with placeholder awareness. iCloud placeholders
    /// surface to FileManager as ".<name>.icloud" wrappers; they are
    /// unwrapped to their logical names here. Provider-backed placeholders
    /// (Dropbox/Drive picked folders) report through URL resource keys —
    /// exact behaviour varies by provider, which the Phase 0 device spike
    /// pins down; unknown states default to "materialized".
    static func list(root: URL, relativeDir: String) async throws -> [FolderEntry] {
        try await listing(root: root, relativeDir: relativeDir).entries
    }

    static func listing(root: URL, relativeDir: String) async throws -> FolderListing {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let dir = relativeDir.isEmpty
                    ? root
                    : root.appendingPathComponent(relativeDir, isDirectory: true)
                var entries: [FolderEntry] = []
                let keys: [URLResourceKey] = [
                    .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                    .ubiquitousItemDownloadingStatusKey,
                ]
                var isComplete = true
                guard let enumerator = FileManager.default.enumerator(
                    at: dir, includingPropertiesForKeys: keys,
                    options: [.skipsPackageDescendants],
                    errorHandler: { _, _ in
                        isComplete = false
                        return true
                    }) else {
                    continuation.resume(returning: FolderListing(entries: [], isComplete: false))
                    return
                }
                let rootPath = dir.standardizedFileURL.path
                for case let itemURL as URL in enumerator {
                    let values: URLResourceValues
                    do {
                        values = try itemURL.resourceValues(forKeys: Set(keys))
                    } catch {
                        isComplete = false
                        continue
                    }
                    let standardized = itemURL.standardizedFileURL.path
                    guard standardized.hasPrefix(rootPath) else { continue }
                    var relative = String(standardized.dropFirst(rootPath.count))
                    if relative.hasPrefix("/") { relative.removeFirst() }
                    guard !relative.isEmpty else { continue }

                    let isDirectory = values.isDirectory ?? false
                    var isPlaceholder = false
                    var name = itemURL.lastPathComponent

                    if !isDirectory, name.hasPrefix("."), name.hasSuffix(".icloud") {
                        // .<name>.icloud placeholder: unwrap the logical name.
                        name = String(name.dropFirst().dropLast(".icloud".count))
                        let parent = (relative as NSString).deletingLastPathComponent
                        relative = parent.isEmpty ? name : "\(parent)/\(name)"
                        isPlaceholder = true
                    } else if let status = values.ubiquitousItemDownloadingStatus,
                              status != .current {
                        isPlaceholder = true
                    }

                    let mtime = values.contentModificationDate.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
                    entries.append(FolderEntry(
                        relativePath: relativeDir.isEmpty ? relative : "\(relativeDir)/\(relative)",
                        sizeBytes: Int64(values.fileSize ?? 0),
                        mtimeMs: mtime,
                        isDirectory: isDirectory,
                        isPlaceholder: isPlaceholder))
                }
                continuation.resume(returning: FolderListing(entries: entries, isComplete: isComplete))
            }
        }
    }
}
