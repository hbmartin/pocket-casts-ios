import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Resolves parsed feed items against the episodes already in the database, so a
/// `.localFeed` refresh of a podcast whose back catalog carries server-canonical
/// episode UUIDs (a signed-out subscribe of a server-sourced podcast) never
/// re-mints that catalog under hash UUIDs — the mass-duplication failure mode.
///
/// Pure function over in-memory indexes: no I/O and no database access.
///
/// Match precedence per item:
/// 1. the item's deterministic hash UUID is already in the database,
/// 2. exact `downloadUrl` == enclosure URL,
/// 3. normalized title + published date (day granularity, UTC) — logged when it fires.
///
/// Documented limitation: an item with no guid AND a changed enclosure URL AND a
/// changed title cannot be correlated and will ingest as a duplicate.
public enum LocalFeedEpisodeMatcher {
    public enum Match: Equatable, Sendable {
        /// The item already exists in the database under this UUID (hash-derived
        /// or server-canonical).
        case existing(uuid: String)
        /// Genuinely new item; ingest under its deterministic hash UUID.
        case new(hashUuid: String)
    }

    /// One entry per input item, in order. `nil` means the item carries no derivable
    /// identity (no guid and no enclosure URL) and must be skipped entirely.
    public static func match(items: [ParsedFeedItem], existing: [Episode]) -> [Match?] {
        var uuids = Set<String>()
        var uuidByDownloadUrl = [String: String]()
        var uuidByTitleAndDay = [TitleDayKey: String]()

        for episode in existing {
            uuids.insert(episode.uuid)
            if let url = episode.downloadUrl, !url.isEmpty, uuidByDownloadUrl[url] == nil {
                uuidByDownloadUrl[url] = episode.uuid
            }
            if let key = TitleDayKey(title: episode.title, date: episode.publishedDate),
               uuidByTitleAndDay[key] == nil {
                uuidByTitleAndDay[key] = episode.uuid
            }
        }

        return items.map { item in
            guard let hashUuid = LocalFeedIdentity.episodeUuid(guid: item.guid, enclosureURL: item.enclosureURL) else {
                return nil
            }
            if uuids.contains(hashUuid) {
                return .existing(uuid: hashUuid)
            }
            if let enclosureURL = item.enclosureURL, let uuid = uuidByDownloadUrl[enclosureURL] {
                return .existing(uuid: uuid)
            }
            if let key = TitleDayKey(title: item.title, date: item.publishedDate),
               let uuid = uuidByTitleAndDay[key] {
                FileLog.shared.addMessage("LocalFeedEpisodeMatcher: title+date fallback matched \"\(item.title ?? "")\" to existing episode \(uuid)")
                return .existing(uuid: uuid)
            }
            return .new(hashUuid: hashUuid)
        }
    }

    /// Case-insensitive trimmed title + UTC calendar day. Both parts are required —
    /// an empty title or missing date never participates in the fallback.
    struct TitleDayKey: Hashable {
        let title: String
        let day: DateComponents

        private static let utcCalendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            return calendar
        }()

        init?(title: String?, date: Date?) {
            let normalized = title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            guard !normalized.isEmpty, let date else { return nil }
            self.title = normalized
            self.day = Self.utcCalendar.dateComponents([.year, .month, .day], from: date)
        }
    }
}
