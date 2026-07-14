import AVFoundation
import XCTest

@testable import podcasts

/// The streamed timed-metadata pipeline (P1-4): groups must resolve through a
/// single serial consumer in arrival order (unordered completion makes
/// `ChapterManager.appendStreamedChapter` silently drop earlier chapters),
/// forwarded groups must carry the session's episode, and ending a session
/// must drop queued and in-flight groups instead of applying them to the next
/// episode.
@MainActor
final class StreamedChapterMetadataHandlerTests: XCTestCase {
    /// MainActor-isolated (and therefore Sendable) so the `@Sendable` sink
    /// closure can capture it; the sink itself runs on the main actor.
    @MainActor
    private final class Recorder {
        var events: [(title: String?, time: TimeInterval, episodeUuid: String)] = []
    }

    func testGroupsResolveInArrivalOrderDespiteSlowLoads() async {
        let recorder = Recorder()
        let delivered = expectation(description: "all groups delivered")
        delivered.expectedFulfillmentCount = 3

        let handler = StreamedChapterMetadataHandler(
            loadGroup: { group in
                // The first-arriving group loads slowest; per-group untracked
                // tasks would deliver it last and lose its chapter.
                if group.time == 10 { try? await Task.sleep(for: .milliseconds(150)) }
                return ("title-\(Int(group.time))", nil)
            },
            sink: { title, _, time, episodeUuid in
                recorder.events.append((title, time, episodeUuid))
                delivered.fulfill()
            }
        )

        handler.startSession(episodeUuid: "episode-a")
        handler.enqueue(.init(time: 10, items: []))
        handler.enqueue(.init(time: 5, items: []))
        handler.enqueue(.init(time: 20, items: []))

        await fulfillment(of: [delivered], timeout: 5)
        XCTAssertEqual(recorder.events.map(\.time), [10, 5, 20],
                       "Groups must reach the sink in arrival order, not load-completion order")
        XCTAssertEqual(recorder.events.map(\.episodeUuid), Array(repeating: "episode-a", count: 3))
    }

    func testEndSessionDropsQueuedAndInFlightGroups() async {
        let recorder = Recorder()
        let delivered = expectation(description: "next session's group delivered")

        let handler = StreamedChapterMetadataHandler(
            loadGroup: { group in
                if group.time == 1 { try? await Task.sleep(for: .milliseconds(100)) }
                return ("title-\(Int(group.time))", nil)
            },
            sink: { title, _, time, episodeUuid in
                recorder.events.append((title, time, episodeUuid))
                delivered.fulfill()
            }
        )

        handler.startSession(episodeUuid: "episode-a")
        handler.enqueue(.init(time: 1, items: [])) // may be in-flight when the session ends
        handler.enqueue(.init(time: 2, items: [])) // still queued when the session ends
        handler.endSession()

        handler.startSession(episodeUuid: "episode-b")
        handler.enqueue(.init(time: 3, items: []))

        await fulfillment(of: [delivered], timeout: 5)
        // Grace period so a leaked episode-a delivery would be caught.
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(recorder.events.map(\.time), [3],
                       "Episode A's stale groups must never reach the sink after its session ended")
        XCTAssertEqual(recorder.events.first?.episodeUuid, "episode-b")
    }

    func testGroupsEnqueuedWithoutASessionAreDropped() async {
        let recorder = Recorder()
        let delivered = expectation(description: "sentinel delivered")

        let handler = StreamedChapterMetadataHandler(
            loadGroup: { group in ("title-\(Int(group.time))", nil) },
            sink: { title, _, time, episodeUuid in
                recorder.events.append((title, time, episodeUuid))
                delivered.fulfill()
            }
        )

        handler.enqueue(.init(time: 7, items: []))

        handler.startSession(episodeUuid: "episode-a")
        handler.enqueue(.init(time: 42, items: []))

        await fulfillment(of: [delivered], timeout: 5)
        XCTAssertEqual(recorder.events.map(\.time), [42])
    }

    func testDelegateCallbackFiltersAndEnqueuesGroups() async {
        let recorder = Recorder()
        let delivered = expectation(description: "valid group delivered")

        let handler = StreamedChapterMetadataHandler(
            loadGroup: { _ in ("loaded", nil) },
            sink: { title, _, time, episodeUuid in
                recorder.events.append((title, time, episodeUuid))
                delivered.fulfill()
            }
        )
        handler.startSession(episodeUuid: "episode-a")

        let title = AVMutableMetadataItem()
        title.identifier = .commonIdentifierTitle
        title.value = "Chapter" as NSString

        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        let valid = AVTimedMetadataGroup(items: [title], timeRange: CMTimeRange(start: CMTime(seconds: 30, preferredTimescale: 600), duration: .zero))
        let negativeTime = AVTimedMetadataGroup(items: [title], timeRange: CMTimeRange(start: CMTime(seconds: -5, preferredTimescale: 600), duration: .zero))
        let irrelevant = AVTimedMetadataGroup(items: [], timeRange: CMTimeRange(start: CMTime(seconds: 60, preferredTimescale: 600), duration: .zero))

        handler.metadataOutput(output, didOutputTimedMetadataGroups: [negativeTime, valid, irrelevant], from: nil)

        await fulfillment(of: [delivered], timeout: 5)
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(recorder.events.map(\.time), [30],
                       "Negative-time and no-relevant-item groups must be filtered at the delegate")
        XCTAssertEqual(recorder.events.first?.episodeUuid, "episode-a")
    }
}
