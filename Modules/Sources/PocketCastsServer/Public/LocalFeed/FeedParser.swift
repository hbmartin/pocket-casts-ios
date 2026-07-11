import Foundation

/// The channel-level fields of a feed parsed on device, plus its items in document order
/// (podcast feeds list newest episodes first).
public struct ParsedFeed: Sendable {
    public var title: String?
    public var author: String?
    public var feedDescription: String?
    public var feedDescriptionHTML: String?
    public var imageURL: String?
    public var category: String?
    public var showType: String?
    public var isExplicit = false
    public var fundingURL: String?
    /// RFC 5005 `<atom:link rel="next">` for paged feeds; nil on the last (or only) page.
    public var nextPageURL: String?
    public var items: [ParsedFeedItem] = []

    public init() {}
}

public struct ParsedFeedItem: Sendable {
    public var guid: String?
    public var title: String?
    public var enclosureURL: String?
    public var enclosureLength: Int64?
    public var enclosureType: String?
    public var duration: TimeInterval?
    public var publishedDate: Date?
    public var episodeNumber: Int64?
    public var seasonNumber: Int64?
    public var episodeType: String?
    public var itemDescription: String?
    public var itemDescriptionHTML: String?
    public var chaptersURL: String?
    public var transcripts: [ParsedFeedTranscript] = []

    public init() {}
}

public struct ParsedFeedTranscript: Sendable {
    public var url: String
    public var type: String?

    public init(url: String, type: String?) {
        self.url = url
        self.type = type
    }
}

public enum FeedParserError: Error {
    case notAFeed
    case malformedXML(underlying: Error?)
}

/// Parses RSS 2.0 and Atom podcast feeds — including the `<itunes:>` and `<podcast:>`
/// namespaces — using Foundation's streaming `XMLParser` (the Server module has no XML
/// dependency beyond Foundation). Pure data-in/struct-out: fetching, paging, identity,
/// and translation to the canonical server-dict shape happen in the callers.
public final class FeedParser {
    public init() {}

    public func parse(data: Data) throws -> ParsedFeed {
        let delegate = FeedParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        let succeeded = parser.parse()

        guard delegate.sawFeedRoot else {
            throw FeedParserError.notAFeed
        }
        // Tolerate truncated/dirty XML as long as we recognised a feed and recovered
        // at least a channel title or one item; otherwise surface the failure.
        if !succeeded, delegate.feed.title == nil, delegate.feed.items.isEmpty {
            throw FeedParserError.malformedXML(underlying: parser.parserError)
        }
        return delegate.feed
    }
}

private final class FeedParserDelegate: NSObject, XMLParserDelegate {
    private enum Namespace {
        static let itunes = "http://www.itunes.com/dtds/podcast-1.0.dtd"
        static let podcastIndexHosts = ["podcastindex.org"]
        static let atom = "http://www.w3.org/2005/Atom"
        static let content = "http://purl.org/rss/1.0/modules/content/"
    }

    var feed = ParsedFeed()
    var sawFeedRoot = false

    private var currentItem: ParsedFeedItem?
    private var text = ""
    private var inChannel = false
    private var inRssImage = false
    private var inAtomEntryAuthor = false
    private var isAtom = false

    private func isPodcastIndex(_ namespaceURI: String?) -> Bool {
        guard let namespaceURI else { return false }
        return Namespace.podcastIndexHosts.contains { namespaceURI.contains($0) }
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        text = ""

        switch elementName.lowercased() {
        case "rss":
            sawFeedRoot = true
        case "feed" where namespaceURI == Namespace.atom:
            sawFeedRoot = true
            isAtom = true
            inChannel = true
        case "channel":
            inChannel = true
        case "item", "entry":
            currentItem = ParsedFeedItem()
        case "image" where currentItem == nil && namespaceURI != Namespace.itunes:
            inRssImage = true
        case "author" where isAtom && currentItem != nil:
            inAtomEntryAuthor = true
        case "enclosure":
            currentItem?.enclosureURL = attributes["url"]
            currentItem?.enclosureLength = attributes["length"].flatMap { Int64($0) }
            currentItem?.enclosureType = attributes["type"]
        case "link":
            handleLink(namespaceURI: namespaceURI, attributes: attributes)
        case "image" where namespaceURI == Namespace.itunes:
            if currentItem == nil, let href = attributes["href"] {
                feed.imageURL = href
            }
        case "category" where namespaceURI == Namespace.itunes:
            // keep the first (top-level) category only, matching the single server field
            if currentItem == nil, feed.category == nil, let categoryText = attributes["text"] {
                feed.category = categoryText
            }
        case "funding" where isPodcastIndex(namespaceURI):
            if currentItem == nil, feed.fundingURL == nil, let url = attributes["url"] ?? attributes["href"] {
                feed.fundingURL = url
            }
        case "chapters" where isPodcastIndex(namespaceURI):
            currentItem?.chaptersURL = attributes["url"] ?? attributes["href"]
        case "transcript" where isPodcastIndex(namespaceURI):
            if let url = attributes["url"] ?? attributes["href"] {
                currentItem?.transcripts.append(ParsedFeedTranscript(url: url, type: attributes["type"]))
            }
        default:
            break
        }
    }

    private func handleLink(namespaceURI: String?, attributes: [String: String]) {
        guard namespaceURI == Namespace.atom else { return }
        let rel = attributes["rel"]?.lowercased()
        if currentItem != nil {
            if rel == "enclosure" {
                currentItem?.enclosureURL = attributes["href"]
                currentItem?.enclosureLength = attributes["length"].flatMap { Int64($0) }
                currentItem?.enclosureType = attributes["type"]
            }
        } else if rel == "next", let href = attributes["href"] {
            feed.nextPageURL = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { text = "" }

        switch elementName.lowercased() {
        case "item", "entry":
            if let item = currentItem {
                feed.items.append(item)
            }
            currentItem = nil
        case "image":
            inRssImage = false
        case "author" where isAtom && currentItem != nil:
            inAtomEntryAuthor = false
        case "title":
            if currentItem != nil {
                setIfEmpty(&currentItem!.title, trimmed)
            } else if inChannel, !inRssImage {
                setIfEmpty(&feed.title, trimmed)
            }
        case "guid":
            if currentItem != nil { setIfEmpty(&currentItem!.guid, trimmed) }
        case "id" where isAtom:
            if currentItem != nil { setIfEmpty(&currentItem!.guid, trimmed) }
        case "description":
            if currentItem != nil {
                setIfEmpty(&currentItem!.itemDescription, trimmed)
            } else if inChannel, !inRssImage {
                setIfEmpty(&feed.feedDescription, trimmed)
            }
        case "summary" where namespaceURI == Namespace.itunes || isAtom:
            if currentItem != nil {
                setIfEmpty(&currentItem!.itemDescription, trimmed)
            } else if inChannel {
                setIfEmpty(&feed.feedDescription, trimmed)
            }
        case "encoded" where namespaceURI == Namespace.content:
            if currentItem != nil {
                setIfEmpty(&currentItem!.itemDescriptionHTML, trimmed)
            } else if inChannel {
                setIfEmpty(&feed.feedDescriptionHTML, trimmed)
            }
        case "content" where isAtom:
            if currentItem != nil { setIfEmpty(&currentItem!.itemDescriptionHTML, trimmed) }
        case "author" where namespaceURI == Namespace.itunes:
            if currentItem == nil {
                setIfEmpty(&feed.author, trimmed)
            }
        case "name" where isAtom && !inAtomEntryAuthor:
            // <feed><author><name> — entry-level author names are ignored
            if currentItem == nil {
                setIfEmpty(&feed.author, trimmed)
            }
        case "url" where inRssImage:
            setIfEmpty(&feed.imageURL, trimmed)
        case "type" where namespaceURI == Namespace.itunes:
            if currentItem == nil {
                setIfEmpty(&feed.showType, trimmed.lowercased())
            }
        case "explicit" where namespaceURI == Namespace.itunes:
            if currentItem == nil {
                feed.isExplicit = ["yes", "true", "explicit"].contains(trimmed.lowercased())
            }
        case "pubdate":
            if currentItem != nil, currentItem!.publishedDate == nil {
                currentItem!.publishedDate = FeedDateParser.date(from: trimmed)
            }
        case "published", "updated":
            if isAtom, currentItem != nil, currentItem!.publishedDate == nil {
                currentItem!.publishedDate = FeedDateParser.date(from: trimmed)
            }
        case "duration" where namespaceURI == Namespace.itunes:
            currentItem?.duration = FeedDurationParser.seconds(from: trimmed)
        case "episode" where namespaceURI == Namespace.itunes:
            currentItem?.episodeNumber = Int64(trimmed)
        case "season" where namespaceURI == Namespace.itunes:
            currentItem?.seasonNumber = Int64(trimmed)
        case "episodetype" where namespaceURI == Namespace.itunes:
            if currentItem != nil { setIfEmpty(&currentItem!.episodeType, trimmed.lowercased()) }
        default:
            break
        }
    }

    private func setIfEmpty(_ target: inout String?, _ value: String) {
        guard target == nil || target?.isEmpty == true, !value.isEmpty else { return }
        target = value
    }
}

/// Parses the date formats found in the wild: RFC 822 (`pubDate`, in several truncations)
/// and ISO 8601 (Atom, and some RSS feeds that use it anyway).
enum FeedDateParser {
    private static var rfc822Formatters: [DateFormatter] { [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm Z",
        "dd MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm Z"
    ].map { format in
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    } }

    // nonisolated(unsafe): ISO8601DateFormatter is documented thread-safe (unlike
    // DateFormatter it has no mutable parse state); it just lacks a Sendable annotation.
    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()
    // nonisolated(unsafe): same as above — documented thread-safe, configured once here.
    nonisolated(unsafe) private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for formatter in rfc822Formatters {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return isoFormatter.date(from: trimmed) ?? isoFractionalFormatter.date(from: trimmed)
    }
}

/// Parses `<itunes:duration>` in all its shapes: plain seconds, `MM:SS`, `HH:MM:SS`,
/// optionally with fractional seconds.
enum FeedDurationParser {
    static func seconds(from string: String) -> TimeInterval? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.components(separatedBy: ":")
        guard parts.count <= 3, !parts.isEmpty else { return nil }

        var total: TimeInterval = 0
        for part in parts {
            guard let value = TimeInterval(part), value >= 0 else { return nil }
            total = total * 60 + value
        }
        return total
    }
}
