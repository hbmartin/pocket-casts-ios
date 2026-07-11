import Foundation
import PocketCastsDataModel
import Synchronization

/// Helper that checks for podcast existence and caches database requests.
public final class PodcastExistsHelper: Sendable {
    public static let shared = PodcastExistsHelper()

    private struct Cache {
        var checkedUuidsThatExist = Set<String>()
        var revision: UInt64 = 0
    }

    private let cache = Mutex(Cache())

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
        cache.withLock {
            $0.checkedUuidsThatExist.insert(uuid)
        }
    }

    public func invalidate(uuid: String) {
        cache.withLock {
            $0.revision += 1
            $0.checkedUuidsThatExist.remove(uuid)
        }
    }

    private func cacheRevisionForLookup(uuid: String) -> (exists: Bool, value: UInt64) {
        cache.withLock {
            ($0.checkedUuidsThatExist.contains(uuid), $0.revision)
        }
    }

    private func markExists(uuid: String, unlessInvalidatedAfter revision: UInt64) {
        cache.withLock {
            guard $0.revision == revision else {
                return
            }

            $0.checkedUuidsThatExist.insert(uuid)
        }
    }
}
