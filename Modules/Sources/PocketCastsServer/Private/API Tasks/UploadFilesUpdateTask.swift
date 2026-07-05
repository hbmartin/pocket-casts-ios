import PocketCastsDataModel
import PocketCastsUtils
import SwiftProtobuf
import UIKit

class UploadFilesUpdateTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((Int) -> Void)?

    private var episodes = [UserEpisode]()

    init(episodes: [UserEpisode]) {
        self.episodes = episodes

        super.init()
    }

    override func apiTokenAcquired(token: String) {
        let url = ServerConstants.Urls.api() + "files"

        var updateRequest = Files_FileListUpdateRequest()

        for episode in episodes {
            var updateFile = Files_FileUpdate()
            updateFile.uuid = episode.uuid

            if episode.titleModified > 0 {
                updateFile.title = episode.title ?? "no name"
            }
            if episode.imageColorModified > 0 {
                updateFile.colour = Google_Protobuf_Int32Value(episode.imageColor)
            }
            if episode.playedUpToModified > 0, !episode.playedUpTo.isNaN, !episode.playedUpTo.isInfinite {
                updateFile.playedUpTo = Google_Protobuf_Int32Value(Int32(episode.playedUpTo))
            }
            if episode.playingStatusModified > 0 {
                updateFile.playingStatus = Google_Protobuf_Int32Value(episode.playingStatus)
            }
            if episode.durationModified > 0 {
                updateFile.duration = Google_Protobuf_Int64Value(Int64(episode.duration))
            }
            updateRequest.files.append(updateFile)
        }

        do {
            let data = try updateRequest.serializedData()
            let (_, httpStatus) = postToServer(url: url, token: token, data: data)

            guard httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("Upload file Update failed \(httpStatus)")
                completion?(httpStatus)
                return
            }
            episodes = episodes.map { episode in
                var episode = episode
                episode.titleModified = 0
                episode.imageColorModified = 0
                episode.playingStatusModified = 0
                episode.playedUpToModified = 0
                episode.durationModified = 0
                return episode
            }

            DataManager.sharedManager.bulkSave(episodes: episodes)
            completion?(httpStatus)
        } catch {
            FileLog.shared.addMessage("UploadFilesUpdateTask: Protobuf Encoding failed \(error.localizedDescription)")
            completion?(-1)
        }
    }
}
