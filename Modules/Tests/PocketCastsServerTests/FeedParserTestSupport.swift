import Foundation
import Synchronization
import Testing
@testable import PocketCastsServer

// Shared support for FeedParserCorpusTests and FeedParserFuzzTests: a time-boxed
// parse harness (so hostile inputs fail tests instead of hanging CI) and a small
// deterministic PRNG for seeded fuzzing.

/// Outcome of a time-boxed parse. The parser's contract is totality — every input
/// either yields a `ParsedFeed` or throws — so `.timedOut` is the only outcome that
/// is unconditionally a failure (and the harness records it as one).
enum TimeBoxedParseOutcome {
    case parsed(ParsedFeed)
    case threw(any Error)
    case timedOut
}

/// Written by the parse thread before it signals the semaphore, read by the waiter
/// only after a successful wait — the semaphore provides the happens-before edge.
// @unchecked Sendable: single write happens-before the semaphore-gated read.
private final class ParseResultBox: @unchecked Sendable {
    var outcome: TimeBoxedParseOutcome = .timedOut
}

/// XMLParser cannot be cancelled. Once one hostile input strands a worker,
/// prevent the rest of the corpus from creating another unbounded thread.
private let parserTimeoutOccurred = Mutex(false)

/// Runs `FeedParser.parse` on a dedicated thread and gives up after `limit`, recording
/// a test failure, so a pathological input fails the test rather than hanging CI.
/// `XMLParser.parse()` cannot be cancelled, so on timeout the worker thread is
/// abandoned — acceptable collateral in an already-failing test run.
func parseTimeBoxed(_ data: Data,
                    limit: Duration = .seconds(5),
                    label: String = "input",
                    sourceLocation: SourceLocation = #_sourceLocation) -> TimeBoxedParseOutcome {
    let canStartWorker = parserTimeoutOccurred.withLock { !$0 }
    guard canStartWorker else {
        Issue.record("FeedParser.parse(\(label)) skipped because an earlier parser worker timed out", sourceLocation: sourceLocation)
        return .timedOut
    }

    let box = ParseResultBox()
    let semaphore = DispatchSemaphore(value: 0)
    let clock = ContinuousClock()
    let start = clock.now

    Thread.detachNewThread {
        do {
            box.outcome = .parsed(try FeedParser().parse(data: data))
        } catch {
            box.outcome = .threw(error)
        }
        semaphore.signal()
    }

    let limitSeconds = Double(limit.components.seconds) + Double(limit.components.attoseconds) / 1e18
    guard semaphore.wait(timeout: .now() + limitSeconds) == .success else {
        parserTimeoutOccurred.withLock { $0 = true }
        Issue.record("FeedParser.parse(\(label)) exceeded the \(limit) time box (elapsed \(clock.now - start))", sourceLocation: sourceLocation)
        return .timedOut
    }
    return box.outcome
}

/// Unwraps `.parsed`, for `try #require(parsedFeed(...))` in tests that expect success.
func parsedFeed(_ outcome: TimeBoxedParseOutcome) -> ParsedFeed? {
    if case .parsed(let feed) = outcome { return feed }
    return nil
}

/// Every string the parser can put into a `ParsedFeed`, flattened for canary scanning.
func feedStringFields(_ feed: ParsedFeed) -> [String] {
    var fields: [String?] = [
        feed.title, feed.author, feed.feedDescription, feed.feedDescriptionHTML,
        feed.imageURL, feed.category, feed.showType, feed.fundingURL, feed.nextPageURL
    ]
    for item in feed.items {
        fields += [
            item.guid, item.title, item.enclosureURL, item.enclosureType, item.episodeType,
            item.itemDescription, item.itemDescriptionHTML, item.chaptersURL
        ]
        fields += item.transcripts.map(\.url)
        fields += item.transcripts.map(\.type)
    }
    return fields.compactMap { $0 }
}

/// SplitMix64: a tiny, deterministic PRNG (Steele, Lea & Flood 2014). Seeded with a
/// fixed constant per test case so every fuzz failure is exactly reproducible — never
/// seed it from `Date()` or `SystemRandomNumberGenerator`.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// A deterministic random string mixing digits/separators (the interesting region for
/// duration and date parsing), printable ASCII, control characters, and arbitrary
/// non-surrogate Unicode scalars.
func randomString(using rng: inout SplitMix64, maxLength: Int = 24) -> String {
    let separatorPool = Array("0123456789:+-., TZ/".unicodeScalars)
    let length = Int.random(in: 0...maxLength, using: &rng)
    var scalars = String.UnicodeScalarView()
    for _ in 0..<length {
        switch Int.random(in: 0..<10, using: &rng) {
        case 0..<5:
            scalars.append(separatorPool[Int.random(in: 0..<separatorPool.count, using: &rng)])
        case 5..<8:
            scalars.append(Unicode.Scalar(UInt8.random(in: 0x20...0x7E, using: &rng)))
        case 8:
            scalars.append(Unicode.Scalar(UInt8.random(in: 0x00...0x1F, using: &rng)))
        default:
            var value: UInt32
            repeat {
                value = UInt32.random(in: 0x20...0x10FFFF, using: &rng)
            } while (0xD800...0xDFFF).contains(value)
            scalars.append(Unicode.Scalar(value)!)
        }
    }
    return String(scalars)
}
