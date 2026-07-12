import Foundation
import Testing
@testable import PocketCastsServer

/// Seeded pseudo-random fuzzing of the on-device feed parser. Every test case is
/// driven by a fixed seed through SplitMix64, so any failure reproduces exactly from
/// the seed in the test name — no `Date()`- or system-entropy-seeded randomness.
///
/// Invariants: the parser is total (returns or throws, never crashes or hangs past the
/// time box), parsing is deterministic, `LocalFeedIdentity` is stable, and the
/// duration/date scalar parsers are total over arbitrary strings.
@Suite("FeedParser fuzz")
struct FeedParserFuzzTests {
    static let seeds: [UInt64] = (1...20).map { UInt64($0) }

    // MARK: - Base feed, assembled from parts so structural mutation is easy

    private static let header = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"
         xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
         xmlns:podcast="https://podcastindex.org/namespace/1.0"
         xmlns:atom="http://www.w3.org/2005/Atom">
    <channel>
    <title>Fuzz Base Feed</title>
    <description>Deterministic fuzzing base</description>
    <itunes:author>Fuzz Author</itunes:author>
    <itunes:image href="https://example.com/fuzz/art.jpg"/>
    <atom:link rel="next" href="https://example.com/fuzz/page2.xml"/>
    """

    private static let itemBlocks: [String] = (1...4).map { index in
        """
        <item>
        <title>Fuzz Episode \(index)</title>
        <guid>fuzz-guid-\(index)</guid>
        <description>Episode number \(index)</description>
        <enclosure url="https://example.com/fuzz/\(index).mp3" length="\(index * 1000)" type="audio/mpeg"/>
        <pubDate>Wed, 0\(index) Jan 2025 10:00:00 +0000</pubDate>
        <itunes:duration>\(index):00</itunes:duration>
        <podcast:transcript url="https://example.com/fuzz/\(index).vtt" type="text/vtt"/>
        </item>
        """
    }

    private static let footer = "</channel>\n</rss>"

    private static func feed(itemOrder: [Int]) -> String {
        ([header] + itemOrder.map { itemBlocks[$0] } + [footer]).joined(separator: "\n")
    }

    // MARK: - Mutators

    private func shuffledItemsFeed(using rng: inout SplitMix64) -> String {
        Self.feed(itemOrder: Array(Self.itemBlocks.indices).shuffled(using: &rng))
    }

    /// Removes 1–5 randomly chosen `name="value"` attributes; the XML stays well-formed.
    /// `xmlns:` declarations are exempt (an undeclared prefix is a fatal error under
    /// `shouldProcessNamespaces`), as is the `<?xml ?>` prolog (mangling it is fatal at
    /// byte 0) — byte-level mutation covers those hostile shapes instead.
    private func droppingRandomAttributes(_ xml: String, using rng: inout SplitMix64) -> String {
        let regex = try! NSRegularExpression(pattern: "[a-zA-Z:][-a-zA-Z0-9:]* ?= ?\"[^\"]*\"")
        let ns = xml as NSString
        let prologEnd = ns.range(of: "?>").location
        var matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).filter { match in
            !ns.substring(with: match.range).hasPrefix("xmlns")
                && (prologEnd == NSNotFound || match.range.location > prologEnd)
        }
        guard !matches.isEmpty else { return xml }

        matches.shuffle(using: &rng)
        let dropCount = Int.random(in: 1...min(5, matches.count), using: &rng)
        // Remove back-to-front so the earlier UTF-16 offsets stay valid.
        let dropped = matches.prefix(dropCount).sorted { $0.range.location > $1.range.location }
        var result = xml
        for match in dropped {
            guard let range = Range(match.range, in: result) else { continue }
            result.removeSubrange(range)
        }
        return result
    }

    private static let injectionTokens = [
        "&amp;", "&#x41;", "&bogus;", "&#0;", "&#xD800;",
        "<!ENTITY x \"y\">", "]]>", "<![CDATA[", "<item>", "</item>", "\u{0}", "<?", "<!--"
    ]

    /// Splices entity references, stray CDATA markers, and rogue tags into random
    /// positions; the result is usually no longer well-formed — which is the point.
    private func injectingTokens(_ xml: String, using rng: inout SplitMix64) -> String {
        var result = xml
        for _ in 0..<5 {
            let token = Self.injectionTokens[Int.random(in: 0..<Self.injectionTokens.count, using: &rng)]
            let offset = Int.random(in: 0...result.count, using: &rng)
            result.insert(contentsOf: token, at: result.index(result.startIndex, offsetBy: offset))
        }
        return result
    }

    /// 32 byte-level edits: overwrite, insert, or delete a byte at a random position.
    private func mutatingBytes(_ data: Data, using rng: inout SplitMix64) -> Data {
        var bytes = [UInt8](data)
        for _ in 0..<32 where !bytes.isEmpty {
            switch UInt64.random(in: 0..<3, using: &rng) {
            case 0:
                bytes[Int.random(in: bytes.indices, using: &rng)] = UInt8.random(in: .min ... .max, using: &rng)
            case 1:
                bytes.insert(UInt8.random(in: .min ... .max, using: &rng), at: Int.random(in: 0...bytes.count, using: &rng))
            default:
                bytes.remove(at: Int.random(in: bytes.indices, using: &rng))
            }
        }
        return Data(bytes)
    }

    private func episodeIdentities(_ outcome: TimeBoxedParseOutcome) -> [String?]? {
        guard let feed = parsedFeed(outcome) else { return nil }
        return feed.items.map { LocalFeedIdentity.episodeUuid(guid: $0.guid, enclosureURL: $0.enclosureURL) }
    }

    // MARK: - Parser totality

    @Test("structural mutations: shuffled items, dropped attributes, injected entities", arguments: Self.seeds)
    func structuralMutations(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        var xml = shuffledItemsFeed(using: &rng)
        xml = droppingRandomAttributes(xml, using: &rng)
        xml = injectingTokens(xml, using: &rng)
        _ = parseTimeBoxed(Data(xml.utf8), label: "structural seed \(seed)")
    }

    @Test("byte-level mutations never crash or hang", arguments: Self.seeds)
    func byteMutations(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        let data = mutatingBytes(Data(Self.feed(itemOrder: Array(Self.itemBlocks.indices)).utf8), using: &rng)
        _ = parseTimeBoxed(data, label: "byte seed \(seed)")
    }

    // MARK: - Determinism and identity stability

    @Test("same bytes parse to the same episode identities, twice over", arguments: Self.seeds)
    func identityStability(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)

        // Well-formed mutation (shuffle + attribute drops): both parses must succeed
        // and agree, and every item keeps an identity because guids survive mutation.
        let wellFormed = Data(droppingRandomAttributes(shuffledItemsFeed(using: &rng), using: &rng).utf8)
        let first = episodeIdentities(parseTimeBoxed(wellFormed, label: "first parse, seed \(seed)"))
        let second = episodeIdentities(parseTimeBoxed(wellFormed, label: "second parse, seed \(seed)"))
        let identities = try #require(first, "well-formed mutation must parse (seed \(seed))")
        #expect(identities == second, "identities must be stable across parses (seed \(seed))")
        #expect(identities.count == Self.itemBlocks.count)
        #expect(identities.allSatisfy { $0 != nil }, "guids survive attribute drops, so every item keeps an identity (seed \(seed))")

        // Arbitrarily mutated bytes: whatever the outcome, it must be deterministic.
        let mutated = mutatingBytes(wellFormed, using: &rng)
        let firstMutated = episodeIdentities(parseTimeBoxed(mutated, label: "first mutated parse, seed \(seed)"))
        let secondMutated = episodeIdentities(parseTimeBoxed(mutated, label: "second mutated parse, seed \(seed)"))
        #expect(firstMutated == secondMutated, "mutated bytes must parse deterministically (seed \(seed))")
    }

    @Test("LocalFeedIdentity is deterministic and well-formed for arbitrary seeds", arguments: Self.seeds)
    func identityOnArbitraryStrings(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        for _ in 0..<50 {
            let raw = randomString(using: &rng)
            let uuid = LocalFeedIdentity.uuid(seed: raw)
            #expect(uuid == LocalFeedIdentity.uuid(seed: raw), "uuid(seed:) must be deterministic for \(raw.debugDescription)")
            #expect(uuid.count == 36)
            #expect(Array(uuid)[14] == "5", "version nibble must be 5 for \(raw.debugDescription)")

            let episode = LocalFeedIdentity.episodeUuid(guid: raw, enclosureURL: nil)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect((episode == nil) == trimmed.isEmpty,
                    "episodeUuid is nil exactly when the guid trims to empty: \(raw.debugDescription)")
        }
    }

    // MARK: - Scalar parser totality

    @Test("duration and date parsing are total over arbitrary strings", arguments: Self.seeds)
    func scalarParserTotality(seed: UInt64) {
        var rng = SplitMix64(seed: seed)

        for _ in 0..<40 {
            let input = randomString(using: &rng, maxLength: 32)
            if let seconds = FeedDurationParser.seconds(from: input) {
                #expect(seconds >= 0, "durations are never negative: \(input.debugDescription)")
            }
            _ = FeedDateParser.date(from: input) // totality: must return or nil, never crash
        }

        // Near-miss durations: random numeric colon-joined parts, 1–4 components.
        for _ in 0..<40 {
            let parts = (0..<Int.random(in: 1...4, using: &rng)).map { _ in String(UInt64.random(in: 0...99999, using: &rng)) }
            let input = parts.joined(separator: ":")
            let seconds = FeedDurationParser.seconds(from: input)
            if parts.count <= 3 {
                #expect(seconds != nil && seconds! >= 0, "numeric \(input.debugDescription) must parse")
            } else {
                #expect(seconds == nil, "more than three components must be rejected: \(input.debugDescription)")
            }
        }

        // Round trip on canonical H:MM:SS.
        for _ in 0..<20 {
            let h = Int.random(in: 0...23, using: &rng)
            let m = Int.random(in: 0..<60, using: &rng)
            let s = Int.random(in: 0..<60, using: &rng)
            #expect(FeedDurationParser.seconds(from: "\(h):\(m):\(s)") == TimeInterval(h * 3600 + m * 60 + s))
        }
    }
}
