import Foundation
import PocketCastsUtils
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

@Suite("LocalFeedURL")
struct LocalFeedURLTests {
    @Test("log redaction strips userinfo and blanks every query value")
    func redactionCoversUserinfoAndQueryTokens() {
        #expect(LocalFeedURL.redactedForLogging("https://user:secret@example.com/feed.xml") == "https://example.com/feed.xml")
        #expect(LocalFeedURL.redactedForLogging("https://example.com/feed.xml?token=abc123&x=1") == "https://example.com/feed.xml?token=REDACTED&x=REDACTED")
        #expect(LocalFeedURL.redactedForLogging("https://example.com/feed.xml") == "https://example.com/feed.xml")
    }

    @Test("removingCredentials keeps query items (token auth must keep working)")
    func removingCredentialsKeepsQuery() {
        #expect(LocalFeedURL.removingCredentials(from: "https://u:p@example.com/feed.xml?token=abc") == "https://example.com/feed.xml?token=abc")
    }

    @Test("userinfo credentials extract for keychain persistence")
    func credentialsExtraction() {
        // URLComponents percent-decodes the userinfo — the decoded form is what
        // Basic auth headers are built from.
        let credentials = LocalFeedURL.credentials(from: "https://user:pa%40ss@example.com/feed.xml")
        #expect(credentials?.user == "user")
        #expect(credentials?.password == "pa@ss")
        #expect(LocalFeedURL.credentials(from: "https://example.com/feed.xml") == nil)
    }
}

@Suite("LocalFeedCredentials", .serialized)
struct LocalFeedCredentialsTests {
    @Test("round-trips through the keychain keyed by podcast uuid")
    func roundTrip() throws {
        let previous = KeychainHelper.store
        defer { KeychainHelper.store = previous }
        KeychainHelper.store = InMemoryKeychainStore()

        LocalFeedCredentials.save(user: "user", password: "p:ss:word", podcastUuid: "pod-1")

        let restored = try #require(LocalFeedCredentials.credentials(podcastUuid: "pod-1"))
        #expect(restored.user == "user")
        #expect(restored.password == "p:ss:word", "only the first ':' separates user from password")
        #expect(LocalFeedCredentials.credentials(podcastUuid: "pod-2") == nil)

        LocalFeedCredentials.delete(podcastUuid: "pod-1")
        #expect(LocalFeedCredentials.credentials(podcastUuid: "pod-1") == nil)
    }
}
