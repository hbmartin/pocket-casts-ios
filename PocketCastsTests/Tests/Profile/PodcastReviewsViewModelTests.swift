import XCTest
import PocketCastsServer
@testable import podcasts

@MainActor
final class PodcastReviewsViewModelTests: XCTestCase {
    func testSubmittedReviewRemainsCommittedWhenRefreshFails() async {
        let original = review(userId: "USER-ID", text: "Original")
        let updated = review(userId: "user-id", text: "Updated")
        var fetchCount = 0
        let model = PodcastReviewsViewModel(
            podcastUuid: "podcast",
            ownUserId: "USER-ID",
            fetchReviews: { _, _, _ in
                fetchCount += 1
                return fetchCount == 1
                    ? PodcastReviewPage(reviews: [original], total: 1, yourReview: original)
                    : nil
            },
            submitReview: { _, _ in updated },
            deleteReview: { _ in false }
        )
        await model.load()
        model.draftText = "Updated"

        let succeeded = await model.submitDraft()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.yourReview, updated)
        XCTAssertEqual(model.reviews, [updated])
        XCTAssertEqual(model.total, 1)
    }

    func testDeletedReviewRemainsRemovedWhenRefreshFails() async {
        let original = review(userId: "user-id", text: "Original")
        var fetchCount = 0
        let model = PodcastReviewsViewModel(
            podcastUuid: "podcast",
            ownUserId: "user-id",
            fetchReviews: { _, _, _ in
                fetchCount += 1
                return fetchCount == 1
                    ? PodcastReviewPage(reviews: [original], total: 1, yourReview: original)
                    : nil
            },
            submitReview: { _, _ in nil },
            deleteReview: { _ in true }
        )
        await model.load()

        let succeeded = await model.deleteReview()

        XCTAssertTrue(succeeded)
        XCTAssertNil(model.yourReview)
        XCTAssertTrue(model.reviews.isEmpty)
        XCTAssertEqual(model.total, 0)
    }

    func testReviewReportIncludesStructuredTargetMetadata() async {
        let target = review(userId: "target-user", text: "Report me")
        var capturedReport: (userId: String, context: String, targetType: String, contentRef: String)?
        let model = PodcastReviewsViewModel(
            podcastUuid: "podcast-uuid",
            ownUserId: "own-user",
            fetchReviews: { _, _, _ in nil },
            submitReview: { _, _ in nil },
            deleteReview: { _ in false },
            reportUser: { userId, _, context, targetType, contentRef in
                capturedReport = (userId, context, targetType, contentRef)
                return true
            }
        )
        model.reportTarget = target

        await model.reportSelected(reason: .spam)

        XCTAssertEqual(capturedReport?.userId, "target-user")
        XCTAssertEqual(capturedReport?.context, "review:podcast-uuid")
        XCTAssertEqual(capturedReport?.targetType, "review")
        XCTAssertEqual(capturedReport?.contentRef, "podcast-uuid")
    }

    private func review(userId: String, text: String) -> PodcastReview {
        PodcastReview(userId: userId,
                      handle: "person",
                      displayName: "Person",
                      rating: 5,
                      text: text,
                      createdAt: nil,
                      updatedAt: nil)
    }
}
