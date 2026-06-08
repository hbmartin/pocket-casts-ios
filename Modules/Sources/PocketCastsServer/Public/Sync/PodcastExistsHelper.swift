import Foundation
import PocketCastsDataModel

/// Helper that checks for podcast existence and caches database requests.
public final class PodcastExistsHelper {
    public static let shared = PodcastExistsHelper()

    private var checkedUuidsThatExist = Set<String>()
    private let lock = NSLock()

    private init() {}

    func exists(uuid: String) -> Bool {
        if cachedExists(uuid: uuid) {
            return true
        }

        let exists = DataManager.sharedManager.findPodcast(uuid: uuid, includeUnsubscribed: true) != nil

        if exists {
            markExists(uuid: uuid)
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

        checkedUuidsThatExist.remove(uuid)
    }

    private func cachedExists(uuid: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return checkedUuidsThatExist.contains(uuid)
    }
}
