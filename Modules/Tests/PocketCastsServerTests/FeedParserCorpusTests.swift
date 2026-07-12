import Foundation
import Testing
@testable import PocketCastsServer

/// Runs the on-device feed parser over a corpus of real-world-shaped weird feeds
/// (encodings, CDATA, namespace soup, RFC 5005 paging, recoverable breakage) and
/// hostile inputs (XXE, billion-laughs, deep nesting, truncation).
///
/// The invariant for every input is totality: `parse` returns a `ParsedFeed` or throws
/// `FeedParserError` — it never crashes, never hangs past the time box, and never
/// resolves external entities into parsed fields.
@Suite("FeedParser corpus")
struct FeedParserCorpusTests {
    static let fixtureNames = [
        "utf8-bom",
        "utf16-le",
        "cdata-heavy",
        "mixed-namespaces",
        "paged-rfc5005",
        "malformed-recoverable",
        "xxe-external",
        "xxe-internal",
        "billion-laughs"
    ]

    /// Content that must never surface in a parsed field: markers of `/etc/passwd`
    /// (the external-entity target), the remote entity host, and the entity system id
    /// itself, which lives in the DTD and has no business appearing in feed content.
    private static let forbiddenCanaries = ["root:", "xxe-canary", "/etc/passwd"]

    private static func fixtureData(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "xml", subdirectory: "Fixtures/Feeds"),
            "missing fixture \(name).xml — is Fixtures/Feeds in the test bundle?"
        )
        return try Data(contentsOf: url)
    }

    // MARK: - Whole-corpus invariants

    @Test("every fixture parses or throws within the time box and never leaks external content", arguments: Self.fixtureNames)
    func totalityAndNoExternalContent(name: String) throws {
        let outcome = parseTimeBoxed(try Self.fixtureData(name), label: name)
        guard let feed = parsedFeed(outcome) else {
            return // .threw is an acceptable total outcome; .timedOut was already recorded
        }
        for field in feedStringFields(feed) {
            for canary in Self.forbiddenCanaries {
                #expect(!field.localizedCaseInsensitiveContains(canary),
                        "\(name): parsed field contains forbidden content \(canary.debugDescription): \(field.debugDescription)")
            }
        }
    }

    // MARK: - Encoding variants

    @Test("UTF-8 BOM feed parses cleanly, BOM excluded from the title")
    func utf8BOM() throws {
        let feed = try #require(parsedFeed(parseTimeBoxed(try Self.fixtureData("utf8-bom"), label: "utf8-bom")))
        #expect(feed.title == "BOM Feed")
        #expect(feed.author == "Bôm Author")
        #expect(feed.items.count == 2)
        #expect(feed.items.first?.title == "Episode \u{1F3A7} One")
        #expect(feed.items.first?.duration == 1800)
    }

    @Test("UTF-16 little-endian feed parses via its BOM")
    func utf16LittleEndian() throws {
        let feed = try #require(parsedFeed(parseTimeBoxed(try Self.fixtureData("utf16-le"), label: "utf16-le")))
        #expect(feed.title == "UTF-16 Feed")
        #expect(feed.feedDescription == "Sixteen bits of café \u{1F399}")
        let item = try #require(feed.items.first)
        #expect(item.guid == "utf16-ep-1")
        #expect(item.duration == 900)
    }

    // MARK: - CDATA and namespaces

    @Test("CDATA-heavy feed: markup stays literal and fake items inside CDATA are not items")
    func cdataHeavy() throws {
        let feed = try #require(parsedFeed(parseTimeBoxed(try Self.fixtureData("cdata-heavy"), label: "cdata-heavy")))
        #expect(feed.title == "CDATA & <Friends>")
        #expect(feed.feedDescription == "Contains <b>markup</b> & raw ampersands && \"quotes\"")
        #expect(feed.feedDescriptionHTML?.contains("<a href=\"https://example.com?a=1&b=2\">") == true)

        #expect(feed.items.count == 1, "the <item> markup inside CDATA must not create a feed item")
        let item = try #require(feed.items.first)
        #expect(item.title == "Ends with a bracket sequence ]]> done")
        #expect(item.guid == "cdata-guid-1")
        #expect(item.itemDescription?.contains("<item><title>fake</title></item>") == true)
        #expect(item.duration == 2700, "CDATA-wrapped duration should be trimmed and parsed")
    }

    @Test("namespace matching is by URI, not prefix; lookalike namespaces are ignored")
    func mixedNamespaces() throws {
        let feed = try #require(parsedFeed(parseTimeBoxed(try Self.fixtureData("mixed-namespaces"), label: "mixed-namespaces")))
        #expect(feed.author == "Prefix Author")
        #expect(feed.imageURL == "https://example.com/mixed/art.jpg")
        #expect(feed.category == "Technology")
        #expect(feed.nextPageURL == "https://example.com/mixed/page2.xml")
        #expect(!feed.isExplicit, "<fake:explicit> is not the itunes namespace and must be ignored")

        let item = try #require(feed.items.first)
        #expect(item.duration == 123, "<it:duration> must win; <fake:duration> must be ignored")
        #expect(item.transcripts.map(\.url) == ["https://example.com/mixed/1.vtt"])
        #expect(item.chaptersURL == "https://example.com/mixed/1.json")
    }

    @Test("RFC 5005 paging: channel-level rel=next wins, item-level and other rels are ignored")
    func pagedFeed() throws {
        let feed = try #require(parsedFeed(parseTimeBoxed(try Self.fixtureData("paged-rfc5005"), label: "paged-rfc5005")))
        #expect(feed.nextPageURL == "https://example.com/paged/page2.xml")
        #expect(feed.items.count == 1)
    }

    // MARK: - Malformed but recoverable

    @Test("markup broken mid-feed still yields the channel and the items parsed before the error")
    func malformedRecoverable() throws {
        let feed = try #require(parsedFeed(parseTimeBoxed(try Self.fixtureData("malformed-recoverable"), label: "malformed-recoverable")))
        #expect(feed.title == "Recoverable Feed")
        #expect(feed.items.count == 1)
        #expect(feed.items.first?.guid == "recover-1")
    }

    // MARK: - Hostile inputs

    @Test("external entities never resolve, even when the target file provably exists")
    func xxeRuntimeCanary() throws {
        let canary = "XXE-CANARY-53c1e9"
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("feedparser-xxe-\(UUID().uuidString).txt")
        try canary.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE rss [<!ENTITY xxe SYSTEM "\(fileURL.absoluteString)">]>
        <rss version="2.0">
          <channel>
            <title>Runtime XXE Probe</title>
            <item><title>Safe</title><guid>safe-1</guid></item>
            <item><title>Payload &xxe;</title><guid>payload-1</guid><description>&xxe;</description></item>
          </channel>
        </rss>
        """

        // Throwing is acceptable; leaking the canary (or timing out) is the failure.
        let outcome = parseTimeBoxed(Data(xml.utf8), label: "runtime XXE")
        guard let feed = parsedFeed(outcome) else { return }
        for field in feedStringFields(feed) {
            #expect(!field.contains(canary), "external entity content leaked into parsed output: \(field.debugDescription)")
        }
    }

    @Test("declared internal entities are ordinary document content and still parse")
    func internalEntities() throws {
        let feed = try #require(parsedFeed(parseTimeBoxed(try Self.fixtureData("xxe-internal"), label: "xxe-internal")))
        #expect(feed.items.first?.guid == "internal-1")
    }

    @Test("billion-laughs expansion completes (or errors) within the time box")
    func billionLaughs() throws {
        // Totality + the time box are the invariants; whether libxml2 expands the
        // entities or aborts on amplification is implementation detail.
        _ = parseTimeBoxed(try Self.fixtureData("billion-laughs"), label: "billion-laughs")
    }

    @Test("600-deep element nesting cannot crash or hang the parser")
    func deeplyNestedElements() {
        var xml = "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>Deep</title>"
        xml += String(repeating: "<d>", count: 600)
        xml += "leaf"
        xml += String(repeating: "</d>", count: 600)
        xml += "</channel></rss>"
        _ = parseTimeBoxed(Data(xml.utf8), label: "600-deep nesting")
    }

    @Test("500 unclosed nested items cannot crash or hang the parser")
    func deeplyNestedUnclosedItems() {
        let xml = "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>Unclosed</title>"
            + String(repeating: "<item><title>t</title>", count: 500)
        _ = parseTimeBoxed(Data(xml.utf8), label: "500 unclosed items")
    }

    @Test("truncating a valid feed at any byte offset yields a feed or an error, never a crash")
    func truncations() throws {
        let full = try Self.fixtureData("utf8-bom")
        // Stride by a prime so offsets land mid-tag, mid-attribute, and mid-multibyte
        // character (the fixture contains BOM, emoji, and accented characters).
        var offsets = Array(stride(from: 0, to: full.count, by: 17))
        offsets += [1, 2, 3, full.count - 1, full.count]

        for offset in offsets {
            let truncated = Data(full.prefix(offset))
            let outcome = parseTimeBoxed(truncated, label: "truncation at byte \(offset)")
            if case .parsed(let feed) = outcome {
                #expect(feed.items.count <= 2, "truncation cannot invent items (offset \(offset))")
            }
        }
    }
}
