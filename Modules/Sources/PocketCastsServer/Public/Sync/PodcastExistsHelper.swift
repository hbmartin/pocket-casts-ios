import Foundation
import PocketCastsDataModel

/// Helper that checks for podcast existence and caches database requests.
class PodcastExistsHelper {
    static let shared = PodcastExistsHelper()

    private var checkedUuidsThatExist: [String] = []
    private var lock = NSLock()

    func exists(uuid: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if checkedUuidsThatExist.contains(uuid) {
            return true
        }

        let exists = DataManager.sharedManager.findPodcast(uuid: uuid, includeUnsubscribed: true) != nil

        if exists {
            checkedUuidsThatExist.append(uuid)
        }

        return exists
    }
}
