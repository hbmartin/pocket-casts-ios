import Foundation
import PocketCastsDataModel

class FireAndForgetSaveFixture {
    func badPodcastSave(podcast: Podcast) {
        // ruleid: pocketcasts.no-fire-and-forget-datamanager-write
        DispatchQueue.global(qos: .userInitiated).async {
            DataManager.sharedManager.save(podcast: podcast)
        }
    }

    func badEpisodeSave(episode: BaseEpisode) {
        // ruleid: pocketcasts.no-fire-and-forget-datamanager-write
        DispatchQueue.global().async {
            DataManager.sharedManager.save(episode: episode)
        }
    }

    func badDeleteWithSurroundingWork(episodeUuid: String) {
        // ruleid: pocketcasts.no-fire-and-forget-datamanager-write
        DispatchQueue.global(qos: .background).async {
            let uuid = episodeUuid
            DataManager.sharedManager.delete(episodeUuid: uuid)
            print(uuid)
        }
    }

    func goodAwaitedSave(podcast: Podcast) {
        // ok: pocketcasts.no-fire-and-forget-datamanager-write
        Task {
            await DataManager.sharedManager.saveAsync(podcast: podcast)
        }
    }

    func goodBackgroundRead(uuid: String) {
        // ok: pocketcasts.no-fire-and-forget-datamanager-write
        DispatchQueue.global(qos: .userInitiated).async {
            _ = DataManager.sharedManager.findBaseEpisode(uuid: uuid)
        }
    }

    func goodSynchronousSave(podcast: Podcast) {
        // ok: pocketcasts.no-fire-and-forget-datamanager-write
        DataManager.sharedManager.save(podcast: podcast)
    }
}
