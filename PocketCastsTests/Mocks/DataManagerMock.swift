import Foundation
import GRDB

@testable import PocketCastsDataModel

// @unchecked Sendable: restates DataManager's conformance, as Swift requires of subclasses; test-only stub state.
class DataManagerMock: DataManager, @unchecked Sendable {
    /// Unique throwaway database per instance (must NOT touch the shared
    /// newTestDatabase() pool, which DBTestCase suites keep open); also needed
    /// because the internal designated init is no longer inherited cross-module.
    convenience init() {
        let dbPath = NSTemporaryDirectory().appending("\(UUID().uuidString).sqlite")
        self.init(dbQueue: GRDBQueue(dbPool: try! DatabasePool(path: dbPath)))
    }

    var podcastsToReturn: [Podcast] = []
    var episodesToReturn: [Episode] = []
    var dailyListeningTimeToReturn: [String: Double] = [:]

    override func findEpisodesWhere(customWhere: String, arguments: [Any]?) -> [Episode] {
        return episodesToReturn
    }

    override func allPodcasts(includeUnsubscribed: Bool, reloadFromDatabase: Bool = false) -> [Podcast] {
        return podcastsToReturn
    }

    /// `Podcast` is a value type, so callers that mutate a copy and `save` it no longer mutate the
    /// instance held in `podcastsToReturn`. Mirror the real save/reload round-trip by writing the saved
    /// value back into the in-memory store so `allPodcasts` reflects it.
    @discardableResult
    override func save(podcast: Podcast) -> Podcast {
        var saved = podcast
        if let index = podcastsToReturn.firstIndex(where: { $0.uuid == podcast.uuid }) {
            if saved.id == 0 {
                saved.id = podcastsToReturn[index].id
            }
            podcastsToReturn[index] = saved
        } else {
            if saved.id == 0 {
                saved.id = Int64((podcastsToReturn.map(\.id).max() ?? 0) + 1)
            }
            podcastsToReturn.append(saved)
        }
        return saved
    }

    override func dailyListeningTime(forLast days: Int = 365) -> [String: Double] {
        return dailyListeningTimeToReturn
    }
}
