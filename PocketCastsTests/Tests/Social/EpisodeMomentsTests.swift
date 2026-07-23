import PocketCastsServer
import PocketCastsUtils
import UIKit
import XCTest
@testable import podcasts

@MainActor
final class EpisodeMomentsTests: XCTestCase {
    func testCacheRejectsLateLoadForInactiveEpisode() {
        let cache = EpisodeMomentPinsCache()
        let episodeALoad = cache.beginLoading(episodeUuid: "episode-a")
        let episodeBLoad = cache.beginLoading(episodeUuid: "episode-b")
        let episodeAPins = [EpisodeMomentPin(id: 1, fraction: 0.25, seconds: 15)]
        let episodeBPins = [EpisodeMomentPin(id: 2, fraction: 0.5, seconds: 30)]

        XCTAssertFalse(cache.commit(episodeAPins, for: episodeALoad))
        XCTAssertTrue(cache.commit(episodeBPins, for: episodeBLoad))
        XCTAssertEqual(cache.cachedPins(activating: "episode-b"), episodeBPins)
        XCTAssertNil(cache.cachedPins(activating: "episode-a"))
    }

    func testCacheInvalidationRejectsAnInFlightLoadAndRemovesStoredPins() {
        let cache = EpisodeMomentPinsCache()
        let pin = EpisodeMomentPin(id: 1, fraction: 0.25, seconds: 15)
        let completedLoad = cache.beginLoading(episodeUuid: "episode")
        XCTAssertTrue(cache.commit([pin], for: completedLoad))
        XCTAssertEqual(cache.cachedPins(activating: "episode"), [pin])

        let inFlightLoad = cache.beginLoading(episodeUuid: "episode")
        cache.invalidate(episodeUuid: "episode")

        XCTAssertFalse(cache.commit([pin], for: inFlightLoad))
        XCTAssertNil(cache.cachedPins(activating: "episode"))
    }

    func testCacheKeepsPinsScopedToEachEpisode() {
        let cache = EpisodeMomentPinsCache()
        let episodeAPins = [EpisodeMomentPin(id: 1, fraction: 0.25, seconds: 15)]
        let episodeBPins = [EpisodeMomentPin(id: 2, fraction: 0.5, seconds: 30)]

        XCTAssertTrue(cache.commit(episodeAPins, for: cache.beginLoading(episodeUuid: "episode-a")))
        XCTAssertTrue(cache.commit(episodeBPins, for: cache.beginLoading(episodeUuid: "episode-b")))

        XCTAssertEqual(cache.cachedPins(activating: "episode-a"), episodeAPins)
        XCTAssertEqual(cache.cachedPins(activating: "episode-b"), episodeBPins)
    }

    func testFetchAllEpisodeCommentsLoadsEveryPage() async throws {
        let comments = (1 ... 5).map { SocialComment(id: Int64($0)) }
        var requests: [(limit: Int, offset: Int)] = []

        let loaded = await fetchAllEpisodeComments(pageSize: 2) { limit, offset in
            requests.append((limit, offset))
            return SocialCommentPage(
                comments: Array(comments.dropFirst(offset).prefix(limit)),
                total: comments.count
            )
        }

        XCTAssertEqual(loaded, comments)
        XCTAssertEqual(requests.map(\.limit), [2, 2, 2])
        XCTAssertEqual(requests.map(\.offset), [0, 2, 4])
    }

    func testFetchAllEpisodeCommentsRejectsAnIncompleteListing() async {
        var requestCount = 0

        let loaded = await fetchAllEpisodeComments(pageSize: 1) { _, _ in
            requestCount += 1
            if requestCount == 1 {
                return SocialCommentPage(comments: [SocialComment(id: 1)], total: 2)
            }
            return SocialCommentPage(comments: [], total: 2)
        }

        XCTAssertNil(loaded)
    }

    func testFetchAllEpisodeCommentsAcceptsAnEmptyListing() async {
        let loaded = await fetchAllEpisodeComments { _, _ in
            SocialCommentPage(comments: [], total: 0)
        }

        XCTAssertEqual(loaded, [])
    }

    func testCommentsRowRecomputesSeedGateWhenOpened() throws {
        var canSeedNow = false
        let model = EpisodeCommentsRowViewModel(
            episodeUuid: "episode",
            podcastUuid: "podcast",
            episodeTitle: "Episode",
            podcastTitle: "Podcast",
            canSeed: false,
            canSeedProvider: { canSeedNow }
        )
        var openedModel: EpisodeCommentsViewModel?
        model.onOpen = { openedModel = $0 }

        canSeedNow = true
        model.open()

        XCTAssertTrue(try XCTUnwrap(openedModel).canSeed)
    }

    func testTimestampedTopLevelMutationInvalidatesEpisodeMoments() {
        var invalidatedEpisodeUuid: String?

        invalidateMomentPinsIfNeeded(
            afterMutating: SocialComment(id: 1, timestampSeconds: 30),
            episodeUuid: "episode",
            invalidator: { invalidatedEpisodeUuid = $0 }
        )

        XCTAssertEqual(invalidatedEpisodeUuid, "episode")
    }

    func testPlainCommentAndTimestampedReplyDoNotInvalidateEpisodeMoments() {
        var invalidatedEpisodeUuids: [String] = []

        invalidateMomentPinsIfNeeded(
            afterMutating: SocialComment(id: 1),
            episodeUuid: "plain-comment",
            invalidator: { invalidatedEpisodeUuids.append($0) }
        )
        invalidateMomentPinsIfNeeded(
            afterMutating: SocialComment(id: 2, parentId: 1, timestampSeconds: 30),
            episodeUuid: "reply",
            invalidator: { invalidatedEpisodeUuids.append($0) }
        )

        XCTAssertTrue(invalidatedEpisodeUuids.isEmpty)
    }

    func testMomentPinTouchTrackerCancelsAfterMovementBeyondTolerance() {
        var tracker = MomentPinTouchTracker()
        tracker.begin(candidate: 42, at: .zero)

        tracker.move(to: CGPoint(x: MomentPinTouchTracker.tapTolerance + 1, y: 0))

        XCTAssertNil(tracker.end())
    }

    func testMomentPinTouchTrackerKeepsStationaryTap() {
        var tracker = MomentPinTouchTracker()
        tracker.begin(candidate: 42, at: .zero)

        tracker.move(to: CGPoint(x: MomentPinTouchTracker.tapTolerance, y: 0))

        XCTAssertEqual(tracker.end(), 42)
        XCTAssertNil(tracker.candidate)
    }

    func testMomentPinsCreateActivatableAccessibilityActions() throws {
        let delegate = TimeSliderDelegateSpy()
        let slider = TimeSlider(frame: CGRect(x: 0, y: 0, width: 300, height: 80))
        slider.delegate = delegate
        slider.totalDuration = 120
        slider.momentPins = [(id: 42, fraction: 0.25), (id: 84, fraction: 0.5)]

        let actions = try XCTUnwrap(slider.accessibilityCustomActions)
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(
            actions[0].name,
            L10n.accessibilityPlayerOpenMoment(1, TimeFormatter.shared.playTimeFormat(time: 30))
        )
        XCTAssertTrue(try XCTUnwrap(actions[0].actionHandler)(actions[0]))
        XCTAssertEqual(delegate.tappedMomentId, 42)
    }
}

@MainActor
private final class TimeSliderDelegateSpy: TimeSliderDelegate {
    private(set) var tappedMomentId: Int64?

    func sliderDidBeginSliding() {}
    func sliderDidEndSliding() {}
    func sliderDidProvisionallySlide(to _: TimeInterval) {}
    func sliderDidSlide(to _: TimeInterval) {}
    func sliderDidTapMoment(id: Int64) {
        tappedMomentId = id
    }
}
