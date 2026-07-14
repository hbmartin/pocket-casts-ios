import CoreSpotlight
import Foundation

/// Pure construction of Spotlight items and their identifiers. Identifiers are
/// the deep-link currency: `episode:<episodeUuid>` opens the episode card,
/// `highlight:<bookmarkUuid>` seeks-and-plays at the bookmark (highlight items
/// arrive with the transcript/highlight indexing slice).
nonisolated enum SpotlightItemBuilder {

    static let episodeDomain = "episode"
    static let highlightDomain = "highlight"

    /// Cap on transcript text attached to one item. Spotlight handles transcript
    /// sizes fine, but a runaway document shouldn't become a multi-megabyte item.
    static let maxTextContentBytes = 256 * 1024

    /// Items expire (and get refreshed by reconciliation) well before Spotlight's
    /// own ~30-day default would silently drop them.
    static let expirationInterval: TimeInterval = 180 * 24 * 3600

    enum Target: Equatable, Sendable {
        case episode(uuid: String)
        case highlight(bookmarkUuid: String)
    }

    static func identifier(for target: Target) -> String {
        switch target {
        case .episode(let uuid):
            return "\(episodeDomain):\(uuid)"
        case .highlight(let bookmarkUuid):
            return "\(highlightDomain):\(bookmarkUuid)"
        }
    }

    static func parse(identifier: String) -> Target? {
        if let uuid = value(of: identifier, prefixedBy: "\(episodeDomain):") {
            return .episode(uuid: uuid)
        }
        if let uuid = value(of: identifier, prefixedBy: "\(highlightDomain):") {
            return .highlight(bookmarkUuid: uuid)
        }
        return nil
    }

    private static func value(of identifier: String, prefixedBy prefix: String) -> String? {
        guard identifier.hasPrefix(prefix) else { return nil }
        let value = String(identifier.dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }

    /// The episode fields an item is built from, snapshotted so builders and
    /// tests never touch the database.
    struct EpisodeMetadata: Equatable, Sendable {
        let uuid: String
        let title: String
        let podcastTitle: String?
        let episodeDescription: String?
        let publishedDate: Date?
        let duration: TimeInterval

        init(uuid: String, title: String, podcastTitle: String? = nil, episodeDescription: String? = nil, publishedDate: Date? = nil, duration: TimeInterval = 0) {
            self.uuid = uuid
            self.title = title
            self.podcastTitle = podcastTitle
            self.episodeDescription = episodeDescription
            self.publishedDate = publishedDate
            self.duration = duration
        }
    }

    static func episodeItem(_ metadata: EpisodeMetadata, transcriptText: String? = nil) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .audio)
        attributes.title = metadata.title
        attributes.containerTitle = metadata.podcastTitle
        attributes.contentDescription = metadata.episodeDescription.map { String($0.prefix(300)) }
        if metadata.duration > 0 {
            attributes.duration = NSNumber(value: metadata.duration)
        }
        attributes.contentCreationDate = metadata.publishedDate
        attributes.keywords = [metadata.podcastTitle].compactMap { $0 }
        if let transcriptText, !transcriptText.isEmpty {
            attributes.textContent = transcriptText
        }

        let item = CSSearchableItem(
            uniqueIdentifier: identifier(for: .episode(uuid: metadata.uuid)),
            domainIdentifier: episodeDomain,
            attributeSet: attributes
        )
        item.expirationDate = Date(timeIntervalSinceNow: expirationInterval)
        return item
    }

    /// Joins segment texts until the UTF-8 budget is reached — never splitting a
    /// segment, so the indexed text always ends on a spoken-sentence boundary.
    static func trimmedTextContent(_ segments: [String], maxBytes: Int = maxTextContentBytes) -> String {
        var totalBytes = 0
        var pieces: [String] = []
        for segment in segments {
            let cost = segment.utf8.count + (pieces.isEmpty ? 0 : 1)
            guard totalBytes + cost <= maxBytes else { break }
            totalBytes += cost
            pieces.append(segment)
        }
        return pieces.joined(separator: " ")
    }
}
