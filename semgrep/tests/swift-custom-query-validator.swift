import Foundation

// Test fixture for pocketcasts.custom-query-sql-through-validator

func rawCustomQueryUsage(filter: EpisodeFilter, dataManager: DataManager) {
    // ruleid: pocketcasts.custom-query-sql-through-validator
    _ = dataManager.findPlaylistEpisodesWhere(query: "archived = 0", arguments: nil)

    // ruleid: pocketcasts.custom-query-sql-through-validator
    _ = dataManager.findEpisodesWhere(customWhere: filter.customQuery, arguments: nil)

    // ruleid: pocketcasts.custom-query-sql-through-validator
    _ = dataManager.findEpisodeWhere(customWhere: filter.customQuery, arguments: nil)

    // ruleid: pocketcasts.custom-query-sql-through-validator
    _ = dataManager.count(query: filter.customQuery, values: nil)
}

func approvedCustomQueryUsage(filter: EpisodeFilter, dataManager: DataManager, editorText: String) {
    // ok: pocketcasts.custom-query-sql-through-validator
    let result = dataManager.validateCustomQueryFragment(editorText)
    _ = result

    // ok: pocketcasts.custom-query-sql-through-validator
    let request = PlaylistQueryBuilder.episodesRequest(for: filter, limit: 10)
    _ = dataManager.episodes(matching: request)

    // ok: pocketcasts.custom-query-sql-through-validator
    let countRequest = PlaylistQueryBuilder.countRequest(.episodeCount, for: filter)
    _ = dataManager.count(matching: countRequest)

    // Raw WHERE strings that don't involve customQuery are outside this rule
    // (guarded separately by playlist-queries-use-typed-requests where applicable).
    // ok: pocketcasts.custom-query-sql-through-validator
    _ = dataManager.findEpisodesWhere(customWhere: "episodeStatus == 1", arguments: nil)
}
