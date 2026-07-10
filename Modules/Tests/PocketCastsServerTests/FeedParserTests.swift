import Foundation
import Testing
@testable import PocketCastsServer

@Suite("FeedParser")
struct FeedParserTests {
    private static let rssFixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"
         xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
         xmlns:podcast="https://podcastindex.org/namespace/1.0"
         xmlns:content="http://purl.org/rss/1.0/modules/content/"
         xmlns:atom="http://www.w3.org/2005/Atom">
      <channel>
        <title>Test Show &amp; Friends</title>
        <description>A test feed</description>
        <content:encoded><![CDATA[<p>A <b>test</b> feed</p>]]></content:encoded>
        <itunes:author>Jane Author</itunes:author>
        <itunes:image href="https://example.com/artwork.jpg"/>
        <itunes:category text="Technology"><itunes:category text="Tech News"/></itunes:category>
        <itunes:type>serial</itunes:type>
        <itunes:explicit>yes</itunes:explicit>
        <podcast:funding url="https://example.com/support">Support us!</podcast:funding>
        <atom:link rel="next" href="https://example.com/feed.xml?page=2"/>
        <item>
          <title>Episode Two</title>
          <guid isPermaLink="false">ep-2-guid</guid>
          <description>Second episode</description>
          <content:encoded><![CDATA[<p>Show notes for two</p>]]></content:encoded>
          <enclosure url="https://example.com/2.mp3" length="52428800" type="audio/mpeg"/>
          <pubDate>Wed, 15 Jan 2025 10:30:00 +0000</pubDate>
          <itunes:duration>1:02:03</itunes:duration>
          <itunes:episode>2</itunes:episode>
          <itunes:season>1</itunes:season>
          <itunes:episodeType>full</itunes:episodeType>
          <podcast:chapters url="https://example.com/2/chapters.json" type="application/json+chapters"/>
          <podcast:transcript url="https://example.com/2.vtt" type="text/vtt"/>
          <podcast:transcript url="https://example.com/2.srt" type="application/srt"/>
        </item>
        <item>
          <title>Episode One</title>
          <enclosure url="https://example.com/1.mp3" length="1024" type="audio/mpeg"/>
          <pubDate>Wed, 01 Jan 2025 08:00:00 GMT</pubDate>
          <itunes:duration>1830</itunes:duration>
        </item>
      </channel>
    </rss>
    """

    private static let atomFixture = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Atom Cast</title>
      <author><name>Atom Author</name></author>
      <entry>
        <id>atom-entry-1</id>
        <title>Atom Episode</title>
        <link rel="enclosure" href="https://example.com/atom-1.m4a" length="2048" type="audio/x-m4a"/>
        <published>2025-02-01T09:00:00Z</published>
        <summary>An atom episode</summary>
      </entry>
    </feed>
    """

    @Test("parses RSS 2.0 channel fields including itunes and podcast namespaces")
    func rssChannel() throws {
        let feed = try FeedParser().parse(data: Data(Self.rssFixture.utf8))

        #expect(feed.title == "Test Show & Friends")
        #expect(feed.author == "Jane Author")
        #expect(feed.feedDescription == "A test feed")
        #expect(feed.feedDescriptionHTML == "<p>A <b>test</b> feed</p>")
        #expect(feed.imageURL == "https://example.com/artwork.jpg")
        #expect(feed.category == "Technology")
        #expect(feed.showType == "serial")
        #expect(feed.isExplicit)
        #expect(feed.fundingURL == "https://example.com/support")
        #expect(feed.nextPageURL == "https://example.com/feed.xml?page=2")
        #expect(feed.items.count == 2)
    }

    @Test("parses RSS items: enclosure, guid, dates, durations, podcast namespace")
    func rssItems() throws {
        let feed = try FeedParser().parse(data: Data(Self.rssFixture.utf8))

        let first = try #require(feed.items.first)
        #expect(first.title == "Episode Two")
        #expect(first.guid == "ep-2-guid")
        #expect(first.enclosureURL == "https://example.com/2.mp3")
        #expect(first.enclosureLength == 52428800)
        #expect(first.enclosureType == "audio/mpeg")
        #expect(first.duration == 3723)
        #expect(first.episodeNumber == 2)
        #expect(first.seasonNumber == 1)
        #expect(first.episodeType == "full")
        #expect(first.itemDescription == "Second episode")
        #expect(first.itemDescriptionHTML == "<p>Show notes for two</p>")
        #expect(first.chaptersURL == "https://example.com/2/chapters.json")
        #expect(first.transcripts.map(\.url) == ["https://example.com/2.vtt", "https://example.com/2.srt"])
        #expect(first.transcripts.first?.type == "text/vtt")

        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute) = (2025, 1, 15, 10, 30)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        #expect(first.publishedDate == Calendar(identifier: .gregorian).date(from: components))

        let second = try #require(feed.items.last)
        #expect(second.guid == nil)
        #expect(second.duration == 1830)
        #expect(second.publishedDate != nil)
    }

    @Test("parses Atom feeds")
    func atom() throws {
        let feed = try FeedParser().parse(data: Data(Self.atomFixture.utf8))

        #expect(feed.title == "Atom Cast")
        #expect(feed.author == "Atom Author")

        let entry = try #require(feed.items.first)
        #expect(entry.guid == "atom-entry-1")
        #expect(entry.title == "Atom Episode")
        #expect(entry.enclosureURL == "https://example.com/atom-1.m4a")
        #expect(entry.enclosureLength == 2048)
        #expect(entry.enclosureType == "audio/x-m4a")
        #expect(entry.itemDescription == "An atom episode")
        #expect(entry.publishedDate != nil)
    }

    @Test("rejects XML that is not a feed")
    func notAFeed() {
        let opml = Data("<?xml version=\"1.0\"?><opml version=\"1.0\"><body/></opml>".utf8)
        #expect(throws: FeedParserError.self) {
            try FeedParser().parse(data: opml)
        }
    }

    @Test("rejects unparseable garbage")
    func garbage() {
        #expect(throws: FeedParserError.self) {
            try FeedParser().parse(data: Data("not xml at all".utf8))
        }
    }

    @Test("recovers items parsed before a truncation")
    func truncated() throws {
        let endIndex = try #require(Self.rssFixture.range(of: "<item>\n      <title>Episode One")).lowerBound
        let truncated = String(Self.rssFixture[..<endIndex])

        let feed = try FeedParser().parse(data: Data(truncated.utf8))
        #expect(feed.title == "Test Show & Friends")
        #expect(feed.items.count == 1)
    }

    @Test("duration formats", arguments: [
        ("90", 90.0),
        ("2:03", 123.0),
        ("1:02:03", 3723.0),
        ("00:00:05", 5.0)
    ])
    func durations(input: String, expected: TimeInterval) {
        #expect(FeedDurationParser.seconds(from: input) == expected)
    }

    @Test("invalid durations return nil")
    func invalidDurations() {
        #expect(FeedDurationParser.seconds(from: "") == nil)
        #expect(FeedDurationParser.seconds(from: "abc") == nil)
        #expect(FeedDurationParser.seconds(from: "1:2:3:4") == nil)
    }

    @Test("date formats: RFC 822 variants and ISO 8601")
    func dates() {
        #expect(FeedDateParser.date(from: "Wed, 15 Jan 2025 10:30:00 +0000") != nil)
        #expect(FeedDateParser.date(from: "Wed, 15 Jan 2025 10:30:00 GMT") != nil)
        #expect(FeedDateParser.date(from: "15 Jan 2025 10:30:00 +0000") != nil)
        #expect(FeedDateParser.date(from: "2025-01-15T10:30:00Z") != nil)
        #expect(FeedDateParser.date(from: "2025-01-15T10:30:00.500Z") != nil)
        #expect(FeedDateParser.date(from: "not a date") == nil)
    }
}
