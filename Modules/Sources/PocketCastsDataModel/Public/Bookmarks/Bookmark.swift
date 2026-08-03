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

    /// Free-form flat tags, case-insensitively unique, sorted for stable display.
    /// The set syncs as a whole (LWW by `tagsModified`); see ADR-0016.
    public var tags: [String] = []

    public var episode: BaseEpisode? = nil
    public var podcast: Podcast? = nil

    // For syncing
    public var titleModified: Date? = nil
    public var deletedModified: Date? = nil
    /// Set when the user trims the excerpt window. A non-nil stamp marks
    /// `excerpt`/`endTime` as user-authored: re-enrichment must never overwrite
    /// them, and sync merges treat the stamped record as authoritative (ADR-0016).
    public var trimModified: Date? = nil
    /// Whole-set LWW stamp for `tags` (ADR-0016).
    public var tagsModified: Date? = nil
    public var deleted: Bool = false

    public init(uuid: String,
                title: String,
                time: TimeInterval,
                created: Date,
                episodeUuid: String,
                podcastUuid: String?,
                excerpt: String? = nil,
                endTime: TimeInterval? = nil,
                tags: [String] = [],
                titleModified: Date? = nil,
                deletedModified: Date? = nil,
                trimModified: Date? = nil,
                tagsModified: Date? = nil,
                deleted: Bool = false) {
        self.uuid = uuid
        self.title = title
        self.time = time
        self.created = created
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.excerpt = excerpt
        self.endTime = endTime
        self.tags = tags
        self.titleModified = titleModified
        self.deletedModified = deletedModified
        self.trimModified = trimModified
        self.tagsModified = tagsModified
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
        // Tags and the trim stamp drive SwiftUI row diffing (tag chips, trimmed
        // excerpts), so they participate in the hash like the title does.
        hasher.combine(tags)
        hasher.combine(trimModified)
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
