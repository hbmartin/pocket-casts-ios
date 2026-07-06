import PocketCastsDataModel

nonisolated extension URLSession {
    func existingTask(for episode: BaseEpisode) async -> URLSessionTask? {
        guard let downloadTaskId = episode.downloadTaskId else {
            return nil
        }

        let tasks = await allTasks
        return tasks.first(where: { $0.taskDescription == downloadTaskId })
    }
}
