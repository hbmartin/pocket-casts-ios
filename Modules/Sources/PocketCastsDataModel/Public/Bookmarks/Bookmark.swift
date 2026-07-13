import Foundation
import SwiftUI

/// A bookmark that represents a position in time within an episode
public struct Bookmark: Hashable, Sendable {
    public let uuid: String
    public let title: String
    public let time: TimeInterval

    public let created: Date

    public let episodeUuid: String
    public let podcastUuid: String?

    /// Smart highlights: the transcript excerpt around `time`, filled in by the
    /// enrichment pipeline after creation. nil = plain (un-enriched) bookmark.
    public var excerpt: String? = nil
    /// Smart highlights: the end of the excerpt window (same time domain as `time`).
    public var endTime: TimeInterval? = nil

    public var episode: BaseEpisode? = nil
    public var podcast: Podcast? = nil

    // For syncing
    public var titleModified: Date? = nil
    public var deletedModified: Date? = nil
    public var deleted: Bool = false

    public init(uuid: String,
                title: String,
                time: TimeInterval,
                created: Date,
                episodeUuid: String,
                podcastUuid: String?,
                excerpt: String? = nil,
                endTime: TimeInterval? = nil,
                titleModified: Date? = nil,
                deletedModified: Date? = nil,
                deleted: Bool = false) {
        self.uuid = uuid
        self.title = title
        self.time = time
        self.created = created
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.excerpt = excerpt
        self.endTime = endTime
        self.titleModified = titleModified
        self.deletedModified = deletedModified
        self.deleted = deleted
    }

    // `BaseEpisode` and `Podcast` don't conform to Hashable, so instead we implement it manually to ignore those properties
    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
        hasher.combine(title)
        hasher.combine(time)
        hasher.combine(created)
        hasher.combine(episodeUuid)
        hasher.combine(podcastUuid)
        hasher.combine(titleModified)
        hasher.combine(deletedModified)
    }

    public static func == (lhs: Bookmark, rhs: Bookmark) -> Bool {
        lhs.uuid == rhs.uuid
    }
}

// MARK: - Identifiable

extension Bookmark: Identifiable {
    public var id: String { uuid }
}

// MARK: - Preview Data

extension PreviewProvider {
    public static func previewBookmark(title: String, time: TimeInterval, created: Date) -> Bookmark {
        Bookmark(uuid: UUID().uuidString,
                 title: title,
                 time: time,
                 created: created,
                 episodeUuid: "episode",
                 podcastUuid: "podcast")
    }
}
