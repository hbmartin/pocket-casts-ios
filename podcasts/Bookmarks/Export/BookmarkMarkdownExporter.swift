import Foundation
import PocketCastsDataModel

/// Formats bookmarks as a Markdown document grouped podcast → episode, each
/// bookmark as `- [HH:MM:SS](share-link) Title — created <date>` (program item 65).
/// The formatter is pure — episode/podcast titles and share links arrive resolved —
/// so it is directly unit-testable.
nonisolated struct BookmarkMarkdownExporter {
    struct ResolvedBookmark {
        let title: String
        let time: TimeInterval
        let created: Date
        let episodeTitle: String
        let podcastTitle: String
        /// Time-linked share URL; nil for content that has no public share page
        /// (local files), which renders the timestamp as plain text.
        let shareLink: String?

        init(title: String, time: TimeInterval, created: Date, episodeTitle: String, podcastTitle: String, shareLink: String?) {
            self.title = title
            self.time = time
            self.created = created
            self.episodeTitle = episodeTitle
            self.podcastTitle = podcastTitle
            self.shareLink = shareLink
        }
    }

    var locale = Locale.current
    var timeZone = TimeZone.current

    /// Groups by podcast title, then episode title, preserving the incoming
    /// bookmark order (callers pass list order) within each episode.
    func markdown(for bookmarks: [ResolvedBookmark]) -> String {
        guard !bookmarks.isEmpty else { return "# \(L10n.bookmarks)\n" }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone

        var lines = ["# \(L10n.bookmarks)", ""]

        let byPodcast = orderedGroups(of: bookmarks, key: \.podcastTitle)
        for (podcastTitle, podcastBookmarks) in byPodcast {
            lines.append("## \(escape(podcastTitle))")
            lines.append("")

            let byEpisode = orderedGroups(of: podcastBookmarks, key: \.episodeTitle)
            for (episodeTitle, episodeBookmarks) in byEpisode {
                lines.append("### \(escape(episodeTitle))")
                lines.append("")
                for bookmark in episodeBookmarks {
                    let timestamp = Self.timestamp(bookmark.time)
                    let timePart = bookmark.shareLink.map { "[\(timestamp)](\($0))" } ?? timestamp
                    lines.append("- \(timePart) \(escape(bookmark.title)) — \(dateFormatter.string(from: bookmark.created))")
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// HH:MM:SS, zero-padded; hours included even when zero so lists align.
    static func timestamp(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func orderedGroups(of bookmarks: [ResolvedBookmark], key: KeyPath<ResolvedBookmark, String>) -> [(String, [ResolvedBookmark])] {
        var order = [String]()
        var groups = [String: [ResolvedBookmark]]()
        for bookmark in bookmarks {
            let groupKey = bookmark[keyPath: key]
            if groups[groupKey] == nil { order.append(groupKey) }
            groups[groupKey, default: []].append(bookmark)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// Minimal Markdown escaping for user-authored titles: enough that a title
    /// cannot break the list/heading structure.
    private func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "#", with: "\\#")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}

// MARK: - Resolution from live data

extension BookmarkMarkdownExporter {
    /// Resolves display titles and time-linked share URLs for export. Episodes
    /// with no public share page (user files) get plain-text timestamps.
    @MainActor
    static func resolve(_ bookmarks: [Bookmark], bookmarkManager: BookmarkManager) -> [ResolvedBookmark] {
        bookmarks.map { bookmark in
            let episode = bookmark.episode ?? bookmarkManager.episode(for: bookmark)
            let podcast: Podcast? = bookmark.podcast ?? bookmark.podcastUuid.flatMap { DataManager.sharedManager.findPodcast(uuid: $0, includeUnsubscribed: true) }

            let shareLink: String? = if let episode = episode as? Episode {
                episode.shareURL + "?t=\(Int(bookmark.time.rounded()))"
            } else {
                nil
            }

            return ResolvedBookmark(
                title: bookmark.title,
                time: bookmark.time,
                created: bookmark.created,
                episodeTitle: episode?.displayableTitle() ?? L10n.bookmarksExportUnknownEpisode,
                podcastTitle: podcast?.title ?? episode?.subTitle() ?? L10n.bookmarksExportUnknownPodcast,
                shareLink: shareLink
            )
        }
    }
}
