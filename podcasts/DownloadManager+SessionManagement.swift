import Foundation
import PocketCastsDataModel
import PocketCastsUtils

extension DownloadManager {

    func transferForegroundDownloadsToBackground() {
        cellularForegroundSession.getTasksWithCompletionHandler { _, _, downloadTasks in
            for foregroundTask in downloadTasks {
                guard let request = foregroundTask.currentRequest else { continue }

                // clear the task description here so that when we cancel it we don't update the episode associated with it, since we're about to resume it straight after
                let savedTaskDescription = foregroundTask.taskDescription
                foregroundTask.taskDescription = nil

                // cancel the foreground task, and transfer it to the background. Try to use the resume data if some is returned so it doesn't have to start again
                foregroundTask.cancel { data in
                    // Transfer tracking data from foreground to background task
                    let oldAttempt = self.downloadAttempts.removeValue(forKey: foregroundTask.taskIdentifier)

                    let backgroundTask: URLSessionDownloadTask
                    if let data {
                        backgroundTask = self.cellularBackgroundSession.downloadTask(withResumeData: data)
                    } else {
                        backgroundTask = self.cellularBackgroundSession.downloadTask(with: request)
                    }
                    backgroundTask.taskDescription = savedTaskDescription

                    // Transfer the tracking data to the new task
                    if let attempt = oldAttempt {
                        self.downloadAttempts[backgroundTask.taskIdentifier] = attempt
                    }

                    backgroundTask.resume()
                }
            }
        }
    }

    func clearStuckDownloads() async {
        let episodesWithDownloadIds = dataManager.findEpisodesWhereNotNull(propertyName: "downloadTaskId")

        var episodeUuids = episodesWithDownloadIds.map { $0.uuid }

        let tasks = await allTasks()

        tasks.forEach { task in
            if let taskDescription = task.taskDescription {
                if let episode = dataManager.findBaseEpisode(downloadTaskId: taskDescription), let index = episodeUuids.firstIndex(of: episode.uuid) {
                    episodeUuids.remove(at: index)
                } else {
                    task.cancel()
                }
            } else {
                task.cancel()
            }
        }

        if episodeUuids.isEmpty { return }

        for episodeUuid in episodeUuids {
            guard let episode = DataManager.sharedManager.findBaseEpisode(uuid: episodeUuid) else { continue }

            let downloadStatus: DownloadStatus = episode.downloaded(pathFinder: self) ? .downloaded : .notDownloaded
            dataManager.saveEpisode(downloadStatus: downloadStatus, downloadTaskId: nil, episode: episode)
            FileLog.shared.addMessage("Clearing download status on an episode that isn't downloading anymore: \(episode.displayableTitle())")
        }
    }
}
