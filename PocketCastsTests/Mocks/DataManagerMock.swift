import Foundation

@testable import PocketCastsDataModel

class DataManagerMock: DataManager {
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
        if let index = podcastsToReturn.firstIndex(where: { $0.uuid == podcast.uuid }) {
            podcastsToReturn[index] = podcast
        } else {
            podcastsToReturn.append(podcast)
        }
        return podcast
    }

    override func dailyListeningTime(forLast days: Int = 365) -> [String: Double] {
        return dailyListeningTimeToReturn
    }
}
