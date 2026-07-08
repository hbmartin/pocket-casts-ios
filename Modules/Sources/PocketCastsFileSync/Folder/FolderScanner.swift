import Foundation

/// Pure diff engine between two folder listings.
///
/// Both folder kinds use it: picked folders have no change notifications at
/// all, and on iCloud it backstops NSMetadataQuery (which can coalesce or
/// drop updates across app restarts). The manager persists the previous
/// scan and feeds the next listing through `diff`.
public enum FolderScanner {
    public struct Diff: Sendable, Equatable {
        public var added: [FolderEntry] = []
        /// Same path, different size/mtime/placeholder state.
        public var modified: [FolderEntry] = []
        public var removed: [FolderEntry] = []

        public var isEmpty: Bool {
            added.isEmpty && modified.isEmpty && removed.isEmpty
        }
    }

    public static func diff(previous: [FolderEntry], current: [FolderEntry]) -> Diff {
        var diff = Diff()
        let previousByPath = Dictionary(previous.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()

        for entry in current {
            seen.insert(entry.relativePath)
            guard let old = previousByPath[entry.relativePath] else {
                diff.added.append(entry)
                continue
            }
            if old != entry {
                diff.modified.append(entry)
            }
        }
        for entry in previous where !seen.contains(entry.relativePath) {
            diff.removed.append(entry)
        }
        return diff
    }

    /// Filters a listing down to audio/video files an uploads scan cares
    /// about, dropping directories, placeholder-artifacts and hidden files.
    public static func mediaFiles(
        in entries: [FolderEntry],
        isSupported: (String) -> Bool
    ) -> [FolderEntry] {
        entries.filter { entry in
            guard !entry.isDirectory else { return false }
            let name = entry.fileName
            guard !name.hasPrefix(".") else { return false }
            return isSupported(name)
        }
    }
}
