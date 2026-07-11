import Foundation
import Testing
@testable import PocketCastsDataModel

/// The cachedLoudness column (migration 77): per-episode integrated BS.1770
/// loudness that seeds VoiceBoostN; 0 = not yet measured.
@Suite("Episode loudness cache")
struct EpisodeLoudnessCacheTests {
    private func makeSavedEpisode(_ dataManager: DataManager, uuid: String = "episode-1") -> Episode {
        var episode = Episode()
        episode.uuid = uuid
        episode.addedDate = Date()
        episode.podcastUuid = "podcast-1"
        dataManager.save(episode: episode)
        return dataManager.findEpisode(uuid: uuid)!
    }

    @Test("loudness round-trips through the database")
    func loudnessPersistence() {
        let dataManager = DataManager.newTestDataManager()
        let episode = makeSavedEpisode(dataManager)

        #expect(dataManager.findLoudness(episode: episode) == 0)

        dataManager.saveLoudness(episode: episode, loudness: -18.7)
        #expect(abs(dataManager.findLoudness(episode: episode) - (-18.7)) < 0.0001)

        let reloaded = dataManager.findEpisode(uuid: episode.uuid)
        #expect(reloaded != nil)
        #expect(abs((reloaded?.cachedLoudness ?? 0) - (-18.7)) < 0.0001)
    }

    @Test("clearCachedAudioMetadata zeroes both cached measurements")
    func clearingCachedMetadata() {
        let dataManager = DataManager.newTestDataManager()
        let episode = makeSavedEpisode(dataManager)

        dataManager.saveLoudness(episode: episode, loudness: -16)
        dataManager.saveFrameCount(episode: episode, frameCount: 123_456)

        dataManager.clearCachedAudioMetadata(episode: episode)

        #expect(dataManager.findLoudness(episode: episode) == 0)
        #expect(dataManager.findFrameCount(episode: episode) == 0)
    }

    @Test("user episode loudness round-trips too")
    func userEpisodeLoudness() {
        let dataManager = DataManager.newTestDataManager()

        var userEpisode = UserEpisode()
        userEpisode.uuid = "user-episode-1"
        userEpisode.addedDate = Date()
        _ = dataManager.save(episode: userEpisode)
        let saved = dataManager.findUserEpisode(uuid: "user-episode-1")!

        dataManager.saveLoudness(episode: saved, loudness: -14.2)
        #expect(abs(dataManager.findLoudness(episode: saved) - (-14.2)) < 0.0001)

        dataManager.clearCachedAudioMetadata(episode: saved)
        #expect(dataManager.findLoudness(episode: saved) == 0)
    }
}
