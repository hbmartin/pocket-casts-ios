import AppIntents
import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// A highlight surfaced to Shortcuts (Highlights program S5): enough structure
/// for users to build their own pipelines (Notion, Drafts, files) without the
/// app shipping per-destination integrations.
struct HighlightAppEntity: TransientAppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Highlight")

    @Property(title: "Title")
    var title: String

    @Property(title: "Excerpt")
    var excerpt: String?

    @Property(title: "Tags")
    var tags: [String]

    @Property(title: "Episode")
    var episodeTitle: String

    @Property(title: "Podcast")
    var podcastTitle: String

    @Property(title: "Timestamp (seconds)")
    var timeSeconds: Int

    @Property(title: "Created")
    var created: Date

    @Property(title: "Link")
    var link: URL?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(episodeTitle)")
    }
}

/// "Get Highlights" for Shortcuts: returns highlights (optionally since a date
/// or filtered to a tag), newest first.
struct GetHighlightsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Highlights"
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Created After")
    var since: Date?

    @Parameter(title: "Tag")
    var tag: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[HighlightAppEntity]> {
        guard FeatureFlag.pkmExport.enabled else {
            return .result(value: [])
        }

        let manager = PlaybackManager.shared.bookmarkManager
        var bookmarks = manager.allBookmarks(sorted: .newestToOldest)

        if let since {
            bookmarks = bookmarks.filter { $0.created > since }
        }
        if let tag, !tag.isEmpty {
            bookmarks = bookmarks.filter { bookmark in
                bookmark.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
        }

        let entities = bookmarks.map { bookmark -> HighlightAppEntity in
            let episode = manager.episode(for: bookmark)
            let entity = HighlightAppEntity()
            entity.title = bookmark.title
            entity.excerpt = bookmark.excerpt
            entity.tags = bookmark.tags
            entity.episodeTitle = episode?.displayableTitle() ?? ""
            entity.podcastTitle = (episode as? Episode).flatMap {
                DataManager.sharedManager.findPodcast(uuid: $0.podcastUuid)?.title
            } ?? ""
            entity.timeSeconds = Int(bookmark.time.rounded())
            entity.created = bookmark.created
            entity.link = (episode as? Episode).flatMap {
                URL(string: $0.shareURL + "?t=\(Int(bookmark.time.rounded()))")
            }
            return entity
        }

        return .result(value: entities)
    }
}
