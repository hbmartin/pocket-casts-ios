import Foundation
import PocketCastsDataModel

/// Helper that checks for podcast existence and caches database requests.
// @unchecked Sendable: the uuid cache and revision counter are guarded by `lock`.
public final class PodcastExistsHelper: @unchecked Sendable {
    public static let shared = PodcastExistsHelper()

    private var checkedUuidsThatExist = Set<String>()
    private var cacheRevision: UInt64 = 0
    private let lock = NSLock()

    private init() {}

    func exists(uuid: String) -> Bool {
        // Avoid holding the cache lock during the database lookup. The revision
        // prevents caching a positive result if this uuid is invalidated mid-query.
        let revision = cacheRevisionForLookup(uuid: uuid)
        if revision.exists {
            return true
        }

        let exists = DataManager.sharedManager.findPodcast(uuid: uuid, includeUnsubscribed: true) != nil

        if exists {
            markExists(uuid: uuid, unlessInvalidatedAfter: revision.value)
        }

        return exists
    }

    func markExists(uuid: String) {
        lock.lock()
        defer { lock.unlock() }

        checkedUuidsThatExist.insert(uuid)
    }

    public func invalidate(uuid: String) {
        lock.lock()
        defer { lock.unlock() }

        cacheRevision += 1
        checkedUuidsThatExist.remove(uuid)
    }

    private func cacheRevisionForLookup(uuid: String) -> (exists: Bool, value: UInt64) {
        lock.lock()
        defer { lock.unlock() }

        return (checkedUuidsThatExist.contains(uuid), cacheRevision)
    }

    private func markExists(uuid: String, unlessInvalidatedAfter revision: UInt64) {
        lock.lock()
        defer { lock.unlock() }

        guard cacheRevision == revision else {
            return
        }

        checkedUuidsThatExist.insert(uuid)
    }
}
