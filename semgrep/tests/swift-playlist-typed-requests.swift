import Foundation

// Test fixture for pocketcasts.playlist-queries-use-typed-requests

func legacyStringPlaylistQueries(playlist: EpisodeFilter) {
    // ruleid: pocketcasts.playlist-queries-use-typed-requests
    let query = PlaylistQueryBuilder.query(clause: .episode, for: playlist, limit: 10)
    _ = DataManager.sharedManager.findEpisodesWhere(customWhere: query.sql, arguments: query.arguments)

    // ruleid: pocketcasts.playlist-queries-use-typed-requests
    let filterQuery = PlaylistQueryBuilder.queryFor(filter: playlist, episodeUuidToAdd: nil, limit: 1)
    _ = filterQuery

    // ruleid: pocketcasts.playlist-queries-use-typed-requests
    let existsSql = PlaylistQueryBuilder.podcastExistsInPlaylistEpisodesQuery(includeDeleted: false)
    _ = existsSql
}

func typedPlaylistQueries(playlist: EpisodeFilter) {
    // ok: pocketcasts.playlist-queries-use-typed-requests
    let request = PlaylistQueryBuilder.episodesRequest(for: playlist, limit: 10)
    _ = DataManager.sharedManager.episodes(matching: request)

    // ok: pocketcasts.playlist-queries-use-typed-requests
    let countRequest = PlaylistQueryBuilder.countRequest(.episodeCount, for: playlist)
    _ = DataManager.sharedManager.count(matching: countRequest)

    // ok: pocketcasts.playlist-queries-use-typed-requests
    let filterRequest = PlaylistQueryBuilder.filterEpisodesRequest(for: playlist, episodeUuidToAdd: nil, limit: 1)
    _ = DataManager.sharedManager.episodes(matching: filterRequest)

    // ok: pocketcasts.playlist-queries-use-typed-requests
    let existsRequest = PlaylistQueryBuilder.podcastExistsInPlaylistEpisodesRequest(podcastUuid: "uuid")
    _ = DataManager.sharedManager.exists(matching: existsRequest)
}
