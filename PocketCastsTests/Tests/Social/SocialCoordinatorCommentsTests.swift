import Foundation
import PocketCastsDataModel
import XCTest

@testable import podcasts

@MainActor
final class SocialCoordinatorCommentsTests: DBTestCase {
    func testRefreshCallbackCompletesOnFirstCallback() async {
        let result = await SocialCoordinator.waitForRefreshCallback(timeout: .seconds(1)) { completion in
            completion()
            completion()
        }

        XCTAssertEqual(result, .completed)
    }

    func testRefreshCallbackTimesOutWhenCallbackNeverArrives() async {
        let result = await SocialCoordinator.waitForRefreshCallback(timeout: .milliseconds(10)) { _ in }

        XCTAssertEqual(result, .timedOut)
    }

    func testRefreshCallbackCooperatesWithCancellation() async {
        let task = Task {
            await SocialCoordinator.waitForRefreshCallback(timeout: .seconds(10)) { _ in }
        }

        task.cancel()

        let result = await task.value
        XCTAssertEqual(result, .cancelled)
    }

    func testCommentsViewModelRefreshesMissingEpisodeAndPopulatesTitles() async {
        let episodeUuid = "push-episode-\(UUID().uuidString)"
        let podcastUuid = "push-podcast-\(UUID().uuidString)"
        var refreshCount = 0
        let manager = dataManager!

        let model = await SocialCoordinator.commentsViewModel(
            episodeUuid: episodeUuid,
            podcastUuid: podcastUuid,
            focusCommentId: 42,
            refreshIfNeeded: {
                refreshCount += 1
                var podcast = Podcast()
                podcast.uuid = podcastUuid
                podcast.title = "Resolved Podcast"
                podcast.addedDate = Date()
                let savedPodcast = manager.save(podcast: podcast)

                var episode = Episode()
                episode.uuid = episodeUuid
                episode.podcastUuid = podcastUuid
                episode.podcast_id = savedPodcast.id
                episode.title = "Resolved Episode"
                episode.duration = 100
                episode.playedUpTo = 30
                manager.save(episode: episode)
            }
        )
        if let resolvedPodcast = dataManager.findPodcast(uuid: podcastUuid, includeUnsubscribed: true) {
            track(podcast: resolvedPodcast)
        }
        if let resolvedEpisode = dataManager.findEpisode(uuid: episodeUuid) as? Episode {
            track(episode: resolvedEpisode)
        }

        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(model.episodeTitle, "Resolved Episode")
        XCTAssertEqual(model.podcastTitle, "Resolved Podcast")
        XCTAssertEqual(model.podcastUuid, podcastUuid)
        XCTAssertEqual(model.focusCommentId, 42)
        XCTAssertTrue(model.canSeed)
    }
}
