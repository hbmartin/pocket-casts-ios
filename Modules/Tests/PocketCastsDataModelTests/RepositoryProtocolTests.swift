import Dependencies
import PocketCastsDataModelTesting
@testable import PocketCastsDataModel
import XCTest

final class RepositoryProtocolTests: XCTestCase {
    func testMockStubsAndRecordsInvocations() {
        let mock = EpisodeRepositoryMock()
        let episode = Episode()
        episode.uuid = "episode-uuid"
        mock.stub("findEpisode(uuid:)", with: episode)

        XCTAssertEqual(mock.findEpisode(uuid: "episode-uuid")?.uuid, "episode-uuid")
        XCTAssertEqual(mock.callCount(of: "findEpisode(uuid:)"), 1)

        // Unstubbed methods fall back to empty defaults rather than trapping.
        XCTAssertEqual(mock.findEpisodesWhere(customWhere: "1 = 1", arguments: nil).count, 0)
        XCTAssertNil(mock.findBaseEpisode(uuid: "missing"))
    }

    func testMockSatisfiesProtocolExistential() {
        let mock: any EpisodeRepository = EpisodeRepositoryMock()
        XCTAssertNil(mock.findEpisode(uuid: "anything"))
    }

    func testOverloadedMockMethodsRecordConcreteEpisodeType() {
        let mock = EpisodeRepositoryMock()

        mock.bulkMarkAsPlayed(episodes: [Episode()], updateSyncFlag: false)
        mock.bulkMarkAsPlayed(episodes: [UserEpisode()], updateSyncFlag: false)

        XCTAssertEqual(mock.callCount(of: "bulkMarkAsPlayed(episodes:updateSyncFlag:)_Episode"), 1)
        XCTAssertEqual(mock.callCount(of: "bulkMarkAsPlayed(episodes:updateSyncFlag:)_UserEpisode"), 1)
    }

    func testDefaultArgumentConveniencesForwardToFullRequirement() {
        let mock = PodcastRepositoryMock()
        let repository: any PodcastRepository = mock

        _ = repository.allPodcasts(includeUnsubscribed: true)

        XCTAssertEqual(mock.callCount(of: "allPodcasts(includeUnsubscribed:reloadFromDatabase:)"), 1)
    }

    func testDependencyOverrideSwapsImplementation() {
        let mock = EpisodeRepositoryMock()

        withDependencies {
            $0.episodeRepository = mock
        } operation: {
            @Dependency(\.episodeRepository) var episodeRepository
            XCTAssertTrue((episodeRepository as AnyObject) === mock)
        }
    }

    func testNativeAsyncFindersRoundTrip() async {
        let dataManager = DataManager.newTestDataManager()

        var podcast = Podcast()
        podcast.uuid = UUID().uuidString.lowercased()
        podcast.addedDate = Date()
        podcast = dataManager.save(podcast: podcast)

        let episode = Episode()
        episode.uuid = UUID().uuidString.lowercased()
        episode.addedDate = Date()
        episode.podcastUuid = podcast.uuid
        episode.podcast_id = podcast.id
        dataManager.save(episode: episode)

        let found = await dataManager.findEpisodeAsync(uuid: episode.uuid)
        XCTAssertEqual(found?.uuid, episode.uuid)

        let baseFound = await dataManager.findBaseEpisodeAsync(uuid: episode.uuid)
        XCTAssertEqual(baseFound?.uuid, episode.uuid)

        let missing = await dataManager.findEpisodeAsync(uuid: "missing-uuid")
        XCTAssertNil(missing)

        let missingUserEpisode = await dataManager.findUserEpisodeAsync(uuid: "missing-uuid")
        XCTAssertNil(missingUserEpisode)
    }

    func testDefaultAsyncImplementationForwardsToSyncRequirement() async {
        let mock = EpisodeRepositoryMock()
        let repository: any EpisodeRepository = mock

        _ = await repository.findEpisodeAsync(uuid: "any-uuid")

        XCTAssertEqual(mock.callCount(of: "findEpisode(uuid:)"), 1)
    }

    func testSaveAsyncDefaultsForwardToSyncRequirement() async {
        let podcastMock = PodcastRepositoryMock()
        let podcastRepository: any PodcastRepository = podcastMock
        await podcastRepository.saveAsync(podcast: Podcast())
        XCTAssertEqual(podcastMock.callCount(of: "save(podcast:)"), 1)

        let episodeMock = EpisodeRepositoryMock()
        let episodeRepository: any EpisodeRepository = episodeMock
        await episodeRepository.saveAsync(episode: Episode())
        XCTAssertEqual(episodeMock.callCount(of: "save(episode:)"), 1)
    }

    func testSaveAsyncRoundTrip() async {
        let dataManager = DataManager.newTestDataManager()

        var podcast = Podcast()
        podcast.uuid = UUID().uuidString.lowercased()
        podcast.addedDate = Date()
        podcast.isEffectsOverridden = true
        podcast = await dataManager.saveAsync(podcast: podcast)

        let episode = Episode()
        episode.uuid = UUID().uuidString.lowercased()
        episode.addedDate = Date()
        episode.podcastUuid = podcast.uuid
        episode.podcast_id = podcast.id
        episode.deselectedChaptersModified = 1234
        await dataManager.saveAsync(episode: episode)

        let foundPodcast = await dataManager.findPodcastAsync(uuid: podcast.uuid, includeUnsubscribed: true)
        XCTAssertEqual(foundPodcast?.uuid, podcast.uuid)
        XCTAssertEqual(foundPodcast?.isEffectsOverridden, true)

        let foundEpisode = await dataManager.findEpisodeAsync(uuid: episode.uuid)
        XCTAssertEqual(foundEpisode?.uuid, episode.uuid)
        XCTAssertEqual(foundEpisode?.deselectedChaptersModified, 1234)
    }

    func testDataManagerSatisfiesAllRepositoryProtocols() {
        let dataManager = DataManager.newTestDataManager()

        XCTAssertNotNil(dataManager as any UpNextRepository)
        XCTAssertNotNil(dataManager as any PodcastRepository)
        XCTAssertNotNil(dataManager as any EpisodeRepository)
        XCTAssertNotNil(dataManager as any UserEpisodeRepository)
        XCTAssertNotNil(dataManager as any PlaylistRepository)
        XCTAssertNotNil(dataManager as any FolderRepository)
        XCTAssertNotNil(dataManager as any DataMaintenance)
    }
}
