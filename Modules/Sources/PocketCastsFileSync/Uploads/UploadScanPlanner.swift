import Foundation

/// Pure decision core of the uploads scan.
///
/// Given the current folder listing and the local database's folder-backed
/// episodes, it decides what to do about each file — without touching the
/// database or filesystem, so every rule is unit-testable.
///
/// Identity model ("list now, hash on download"):
/// - A newly discovered file gets a **provisional** episode keyed by
///   path+size(+mtime), so it is playable immediately without downloading.
/// - When the file is first fully materialized it is hashed; the hash either
///   **promotes** the provisional episode to canonical or **re-keys** it
///   onto an existing canonical episode (rename/copy detection).
public enum UploadScanPlanner {

    /// A folder-backed episode as the planner sees it (a projection of
    /// UserEpisode, kept model-free so this module layer stays pure).
    public struct KnownEpisode: Equatable, Sendable {
        public let uuid: String
        public let relativePath: String
        public let sizeBytes: Int64
        public let mtimeMs: Int64
        public let contentHash: String?
        public let isCanonical: Bool

        public init(uuid: String, relativePath: String, sizeBytes: Int64, mtimeMs: Int64,
                    contentHash: String?, isCanonical: Bool) {
            self.uuid = uuid
            self.relativePath = relativePath
            self.sizeBytes = sizeBytes
            self.mtimeMs = mtimeMs
            self.contentHash = contentHash
            self.isCanonical = isCanonical
        }
    }

    public enum Action: Equatable, Sendable {
        /// Unknown file: create a provisional episode (fresh uuid assigned
        /// by the executor). `group` is the first path component under the
        /// uploads root, "" for loose files.
        case createProvisional(entry: FolderEntry, group: String)
        /// A known episode's file moved/renamed (matched by size+mtime
        /// heuristic).
        case updatePath(episodeUuid: String, entry: FolderEntry, group: String)
        /// The file changed in place (same path, different size/mtime):
        /// identity is void; re-hash on next materialization.
        case resetIdentity(episodeUuid: String, entry: FolderEntry)
        /// The backing file is gone from the folder (and no rename target
        /// matched). The episode row is removed; cloud trash is the undo.
        case removeEpisode(episodeUuid: String)
    }

    public static func plan(
        mediaEntries: [FolderEntry],
        knownEpisodes: [KnownEpisode]
    ) -> [Action] {
        var actions: [Action] = []

        let knownByPath = Dictionary(uniqueKeysWithValues: knownEpisodes.map { ($0.relativePath, $0) })
        var seenPaths = Set<String>()
        var claimedEpisodes = Set<String>()

        // Pass 1: files present in the folder.
        for entry in mediaEntries {
            seenPaths.insert(entry.relativePath)

            if let known = knownByPath[entry.relativePath] {
                claimedEpisodes.insert(known.uuid)
                if known.sizeBytes == entry.sizeBytes {
                    // Same file (mtime drift alone is provider noise).
                    continue
                }
                // Replaced in place: same name, different content.
                actions.append(.resetIdentity(episodeUuid: known.uuid, entry: entry))
                continue
            }

            // Rename detection: an episode whose file vanished and whose
            // size+mtime match this new path exactly.
            if let moved = knownEpisodes.first(where: { known in
                !claimedEpisodes.contains(known.uuid)
                    && !mediaEntries.contains(where: { $0.relativePath == known.relativePath })
                    && known.sizeBytes == entry.sizeBytes
                    && known.mtimeMs == entry.mtimeMs
            }) {
                claimedEpisodes.insert(moved.uuid)
                actions.append(.updatePath(episodeUuid: moved.uuid, entry: entry, group: group(of: entry)))
                continue
            }

            actions.append(.createProvisional(entry: entry, group: group(of: entry)))
        }

        // Pass 2: episodes whose files are gone and weren't rename-claimed.
        for known in knownEpisodes where !seenPaths.contains(known.relativePath) && !claimedEpisodes.contains(known.uuid) {
            actions.append(.removeEpisode(episodeUuid: known.uuid))
        }

        return actions
    }

    /// The grouping (virtual podcast) for a file: its first path component
    /// below the uploads root, or "" for files at the root.
    public static func group(of entry: FolderEntry) -> String {
        let components = entry.relativePath.components(separatedBy: "/")
        return components.count > 1 ? components[0] : ""
    }

    // MARK: Hash promotion

    public enum HashResolution: Equatable, Sendable {
        /// First device to hash this content: episode becomes canonical.
        case promote(episodeUuid: String)
        /// The hash already belongs to another episode (rename across a
        /// re-scan gap, or a duplicate file): merge the provisional row's
        /// local state into the canonical row and drop the provisional.
        case rekey(provisionalUuid: String, canonicalUuid: String)
        /// Hash matches what the episode already has: nothing to do.
        case unchanged
    }

    /// Decides what a freshly computed hash means for a provisional episode.
    /// `hashOwners` maps known content hashes to episode uuids (from the DB).
    public static func resolveHash(
        _ sha256: String,
        for episodeUuid: String,
        currentHash: String?,
        hashOwners: [String: String]
    ) -> HashResolution {
        if currentHash == sha256 { return .unchanged }
        if let owner = hashOwners[sha256], owner != episodeUuid {
            return .rekey(provisionalUuid: episodeUuid, canonicalUuid: owner)
        }
        return .promote(episodeUuid: episodeUuid)
    }
}
