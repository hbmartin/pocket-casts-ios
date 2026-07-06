import Foundation
import PocketCastsDataModel
import PocketCastsServer

nonisolated extension AudioVideoFilter: AnalyticsDescribable {
    var analyticsDescription: String {
        switch self {
        case .all:
            return "all"
        case .audioOnly:
            return "audio"
        case .videoOnly:
            return "video"
        }
    }
}

nonisolated extension PlaylistSort: AnalyticsDescribable {
    var analyticsDescription: String {
        switch self {
        case .newestToOldest:
            return "newest_to_oldest"
        case .oldestToNewest:
            return "oldest_to_newest"
        case .shortestToLongest:
            return "shortest_to_longest"
        case .longestToShortest:
            return "longest_to_shortest"
        case .dragAndDrop:
            return "drag_and_drop"
        }
    }
}

nonisolated extension AutoAddToUpNextSetting: AnalyticsDescribable {
    var analyticsDescription: String {
        switch self {
        case .off:
            return "off"
        case .addLast:
            return "add_last"
        case .addFirst:
            return "add_first"
        }
    }
}

nonisolated extension AutoArchiveAfterTime: AnalyticsDescribable {
    var analyticsDescription: String {
        switch self {
        case .never:
            return "never"
        case .afterPlaying:
            return "after_playing"
        case .after1Day:
            return "after_24_hours"
        case .after2Days:
            return "after_2_days"
        case .after1Week:
            return "after_1_week"
        case .after2Weeks:
            return "after_2_weeks"
        case .after30Days:
            return "after_30_days"
        case .after90Days:
            return "after_3_months"
        }
    }
}

nonisolated extension PodcastGrouping: AnalyticsDescribable {
    var analyticsDescription: String {
        switch self {
        case .none:
            return "none"
        case .downloaded:
            return "downloaded"
        case .unplayed:
            return "unplayed"
        case .season:
            return "season"
        case .starred:
            return "starred"
        }
    }
}

nonisolated extension AutoAddLimitReachedAction: AnalyticsDescribable {
    var analyticsDescription: String {
        switch self {
        case .stopAdding:
            return "stop_adding"
        case .addToTopOnly:
            return "only_add_top"
        }
    }
}

nonisolated extension PodcastInfo: AnalyticsDescribable {
    var analyticsDescription: String {
        if let uuid {
            return uuid
        }

        if let iTunesId {
            return String(iTunesId)
        }

        return "unknown"
    }
}
