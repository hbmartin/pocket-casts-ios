import Foundation
import Testing
@testable import PocketCastsServer

@Suite("LocalPodcastSource")
struct LocalPodcastSourceTests {
    @Test("emits the canonical podcastInfo dict shape the add pipeline consumes")
    func canonicalDictShape() throws {
        var item = ParsedFeedItem()
        item.guid = "ep-guid"
        item.title = "Episode"
        item.enclosureURL = "https://example.com/1.mp3"
        item.enclosureLength = 1024
        item.enclosureType = "audio/mpeg"
        item.duration = 1830
        item.episodeNumber = 3
        item.seasonNumber = 2
        item.episodeType = "full"
        item.publishedDate = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z

        var feed = ParsedFeed()
        feed.title = "Test Show"
        feed.author = "Jane"
        feed.feedDescription = "desc"
        feed.feedDescriptionHTML = "<p>desc</p>"
        feed.category = "Technology"
        feed.showType = "serial"
        feed.isExplicit = true
        feed.fundingURL = "https://example.com/support"
        feed.items = [item]

        let feedURL = "https://example.com/feed.xml"
        let podcastUuid = LocalFeedIdentity.uuid(seed: feedURL)
        let info = LocalPodcastSource().podcastInfoDict(from: feed, podcastUuid: podcastUuid, feedURL: feedURL)

        let podcastJson = try #require(info["podcast"] as? [String: Any])
        #expect(podcastJson["uuid"] as? String == podcastUuid)
        #expect(podcastJson["url"] as? String == feedURL)
        #expect(podcastJson["title"] as? String == "Test Show")
        #expect(podcastJson["author"] as? String == "Jane")
        #expect(podcastJson["description"] as? String == "desc")
        #expect(podcastJson["description_html"] as? String == "<p>desc</p>")
        #expect(podcastJson["category"] as? String == "Technology")
        #expect(podcastJson["show_type"] as? String == "serial")
        #expect(podcastJson["explicit"] as? Bool == true)
        #expect((podcastJson["fundings"] as? [[String: Any]])?.first?["url"] as? String == "https://example.com/support")

        let episodes = try #require(podcastJson["episodes"] as? [[String: Any]])
        let episode = try #require(episodes.first)
        #expect(episode["uuid"] as? String == LocalFeedIdentity.uuid(seed: "ep-guid"))
        #expect(episode["title"] as? String == "Episode")
        #expect(episode["url"] as? String == "https://example.com/1.mp3")
        #expect(episode["file_size"] as? Int64 == 1024)
        #expect(episode["file_type"] as? String == "audio/mpeg")
        #expect(episode["duration"] as? Double == 1830)
        #expect(episode["number"] as? Int64 == 3)
        #expect(episode["season"] as? Int64 == 2)
        #expect(episode["type"] as? String == "full")
        #expect(episode["has_generated_transcript"] as? Bool == false)
        // the ISO string Episode.from parses with ISO8601DateFormatter
        #expect(episode["published"] as? String == "2025-01-01T00:00:00Z")
    }

    @Test("items without any stable identity are dropped")
    func dropsItemsWithoutIdentity() {
        var identityless = ParsedFeedItem()
        identityless.title = "No guid, no enclosure"

        var feed = ParsedFeed()
        feed.title = "Show"
        feed.items = [identityless]

        let info = LocalPodcastSource().podcastInfoDict(from: feed, podcastUuid: "uuid", feedURL: "https://example.com/feed.xml")
        let podcastJson = info["podcast"] as? [String: Any]
        #expect((podcastJson?["episodes"] as? [[String: Any]])?.isEmpty == true)
    }
}
