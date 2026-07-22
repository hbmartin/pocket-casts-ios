import XCTest
@testable import PocketCastsServer

final class SocialModerationTaskTests: XCTestCase {
    func testPodcastReviewNormalizesUserIdentifier() {
        let review = PodcastReview(userId: "ABCDEF12-3456-7890-ABCD-EF1234567890",
                                   handle: "person",
                                   displayName: "Person",
                                   rating: 5,
                                   text: "Review",
                                   createdAt: nil,
                                   updatedAt: nil)

        XCTAssertEqual(review.userId, "abcdef12-3456-7890-abcd-ef1234567890")
    }

    func testReportRequestIncludesStructuredContentTarget() {
        let request = SocialReportTask.makeRequest(targetUserId: "target-user",
                                                   reason: .spam,
                                                   context: "review:podcast-uuid",
                                                   targetType: "review",
                                                   contentRef: "podcast-uuid")

        XCTAssertEqual(request.targetUserID, "target-user")
        XCTAssertEqual(request.reason, .spam)
        XCTAssertEqual(request.context, "review:podcast-uuid")
        XCTAssertEqual(request.targetType, "review")
        XCTAssertEqual(request.contentRef, "podcast-uuid")
    }
}
