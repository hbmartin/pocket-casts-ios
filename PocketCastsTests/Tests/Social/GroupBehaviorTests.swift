import PocketCastsServer
import XCTest

@testable import podcasts

@MainActor
final class GroupBehaviorTests: XCTestCase {
    private let failingService = GroupDetailService(
        fetchPosts: { _, _ in nil },
        fetchMembers: { _ in nil },
        submitPost: { _ in nil },
        deletePost: { _ in false },
        reportUser: { _, _, _ in false },
        join: { _ in false },
        leave: { _ in false },
        deleteGroup: { _ in false },
        setAlert: { _, _ in false },
        kick: { _, _, _ in false }
    )

    func testPostFailureIsShownInline() async {
        let model = makeModel()
        model.composeText = "A group post"

        await model.send()

        XCTAssertEqual(model.postError, L10n.socialGroupPostFailed)
        XCTAssertEqual(model.composeText, "A group post")
        XCTAssertFalse(model.isSending)
    }

    func testMutationFailuresExposeGenericActionAlert() async {
        let model = makeModel()
        let post = GroupPost(id: 10, userId: "other")
        let member = GroupMemberInfo(handle: "member", displayName: "Member", role: .member)

        await model.delete(post)
        XCTAssertEqual(model.actionError, L10n.socialGroupActionFailed)
        model.actionError = nil

        await model.join()
        XCTAssertEqual(model.actionError, L10n.socialGroupActionFailed)
        model.actionError = nil

        await model.leave()
        XCTAssertEqual(model.actionError, L10n.socialGroupActionFailed)
        XCTAssertFalse(model.departed)
        model.actionError = nil

        await model.deleteGroup()
        XCTAssertEqual(model.actionError, L10n.socialGroupActionFailed)
        XCTAssertFalse(model.departed)
        model.actionError = nil

        await model.toggleAlerts()
        XCTAssertEqual(model.actionError, L10n.socialGroupActionFailed)
        model.actionError = nil

        model.reportTarget = post
        await model.reportSelected(reason: .spam)
        XCTAssertEqual(model.actionError, L10n.socialGroupActionFailed)
        XCTAssertEqual(model.reportTarget, post)
        model.actionError = nil

        await model.kick(member, ban: false)
        XCTAssertEqual(model.actionError, L10n.socialGroupActionFailed)
        model.actionError = nil

        await model.kick(member, ban: true)
        XCTAssertEqual(model.actionError, L10n.socialGroupActionFailed)
    }

    func testCreatedAndJoinedGroupsLeaveDiscoverImmediately() {
        let discovered = SocialGroup(id: 1, title: "Discovered", visibility: .public)
        let created = SocialGroup(id: 1, title: "Created", visibility: .public, yourRole: .owner)
        let createdModel = SocialGroupsViewModel(fixture: [], discover: [discovered])

        createdModel.inserted(created)

        XCTAssertEqual(createdModel.groups, [created])
        XCTAssertTrue(createdModel.discover.isEmpty)

        let joinedModel = SocialGroupsViewModel(fixture: [], discover: [discovered])
        joinedModel.joinedGroup(id: discovered.id)

        XCTAssertTrue(joinedModel.discover.isEmpty)
    }

    func testNewestMilestoneUsesDateThenKindAndTierTieBreakers() {
        let old = SocialMilestone(kind: .episodes, tier: 1_000, crossedAt: Date(timeIntervalSince1970: 1))
        let newestHours = SocialMilestone(kind: .hours, tier: 100, crossedAt: Date(timeIntervalSince1970: 2))
        let newestEpisodesLow = SocialMilestone(kind: .episodes, tier: 50, crossedAt: Date(timeIntervalSince1970: 2))
        let newestEpisodesHigh = SocialMilestone(kind: .episodes, tier: 100, crossedAt: Date(timeIntervalSince1970: 2))

        let selected = SocialFeedViewModel.newestMilestone(in: [newestEpisodesLow, old, newestHours, newestEpisodesHigh])

        XCTAssertEqual(selected, newestEpisodesHigh)
    }

    func testCreateGroupSubmissionDisablesCancellationAndRejectsDuplicateWork() async {
        let gate = CreateGroupSubmissionGate()
        let started = expectation(description: "submission started")
        let completion = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let group = SocialGroup(id: 1, title: "Group")
        let first = Task { @MainActor in
            await gate.perform {
                started.fulfill()
                for await _ in completion.stream {
                    return group
                }
                return nil
            }
        }
        await fulfillment(of: [started], timeout: 1)

        XCTAssertTrue(gate.isSaving)
        XCTAssertFalse(gate.canCancel)
        let duplicate = await gate.perform {
            XCTFail("Duplicate save work must not start")
            return group
        }
        XCTAssertNil(duplicate)

        completion.continuation.yield()
        completion.continuation.finish()
        let firstResult = await first.value
        XCTAssertEqual(firstResult, group)
        XCTAssertFalse(gate.isSaving)
        XCTAssertTrue(gate.canCancel)
    }

    private func makeModel() -> GroupDetailViewModel {
        GroupDetailViewModel(
            fixture: [],
            group: SocialGroup(id: 1, title: "Group", visibility: .public, yourRole: .member),
            service: failingService
        )
    }
}
