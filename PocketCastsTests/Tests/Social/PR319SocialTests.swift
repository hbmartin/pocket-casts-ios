import Foundation
import PocketCastsDataModel
@testable import PocketCastsServer
import XCTest
@testable import podcasts

final class SocialNotificationPayloadTests: XCTestCase {
    func testIntegerPayloadParsesStringsAndJSONNumbers() {
        let stringValue: Int64? = NotificationsHelper.socialPayloadInteger("12345")
        let numberValue: Int64? = NotificationsHelper.socialPayloadInteger(NSNumber(value: 12345))

        XCTAssertEqual(stringValue, 12345)
        XCTAssertEqual(numberValue, 12345)
    }

    func testIntegerPayloadRejectsFractionsAndOverflow() {
        let fraction: Int64? = NotificationsHelper.socialPayloadInteger(NSNumber(value: 1.5))
        let overflow: Int8? = NotificationsHelper.socialPayloadInteger("128")

        XCTAssertNil(fraction)
        XCTAssertNil(overflow)
    }

    func testSocialSectionVisibilityDoesNotDependOnEnumOrdering() {
        XCTAssertEqual(
            NotificationsViewController.visibleSections(showSocialSection: false),
            NotificationsViewController.Section.allCases.filter { $0 != .social }
        )
        XCTAssertEqual(
            NotificationsViewController.visibleSections(showSocialSection: true),
            NotificationsViewController.Section.allCases
        )
    }
}

@MainActor
final class FindPeopleViewModelTests: XCTestCase {
    func testEmptySearchIsAValidNoResultsState() async {
        let model = FindPeopleViewModel(searchPeople: { _ in .success([]) })

        await model.performSearch(query: "nobody")

        XCTAssertTrue(model.searchedWithNoResults)
        XCTAssertNil(model.loadError)
    }

    func testFailedSearchIsNotPresentedAsNoResults() async {
        let model = FindPeopleViewModel(searchPeople: { _ in .failure(.requestFailed(statusCode: 503)) })

        await model.performSearch(query: "offline")

        XCTAssertFalse(model.searchedWithNoResults)
        XCTAssertNotNil(model.loadError)
    }

    func testSuggestionFailureSurfacesErrorWhileSuccessfulCuratorsRemain() async {
        let curator = SocialProfileSummary(handle: "curator", displayName: "Curator")
        let model = FindPeopleViewModel(
            isJoined: { true },
            loadPeopleSuggestions: { .failure(.invalidResponse) },
            loadCurators: { .success([curator]) }
        )

        await model.loadSuggestions()

        XCTAssertEqual(model.curators, [curator])
        XCTAssertTrue(model.suggestions.isEmpty)
        XCTAssertNotNil(model.loadError)
    }

    func testContactMatchFailureIsNotPresentedAsAnEmptySuccess() async {
        let model = FindPeopleViewModel(
            matchContactHashes: { _ in .failure(.requestFailed(statusCode: 500)) }
        )

        await model.loadContactMatches([SocialContactHash(kind: .email, hash: "hash")])

        XCTAssertTrue(model.contactMatches.isEmpty)
        XCTAssertNotNil(model.loadError)
    }

    func testContactKindsMapOnlyToSupportedWireValues() {
        XCTAssertEqual(SocialContactHash.Kind.email.apiValue, .email)
        XCTAssertEqual(SocialContactHash.Kind.phone.apiValue, .phone)
    }
}

@MainActor
final class SocialNotificationSettingsViewModelTests: XCTestCase {
    func testRapidTogglesSerializeAndPersistLatestMask() async {
        let gate = ProfileUpdateGate()
        let profile = SocialProfile(userId: "user", handle: "handle", displayName: "Name")
        let model = SocialNotificationSettingsViewModel(
            profile: profile,
            updateProfile: { await gate.update($0) }
        )

        model.set(.followRequest, enabled: false)
        await gate.waitForCallCount(1)
        model.set(.newFollower, enabled: false)
        await Task.yield()
        let callCountAfterSecondToggle = await gate.callCount
        XCTAssertEqual(callCountAfterSecondToggle, 1, "a second write must not overlap the first")

        await gate.releaseNext()
        await gate.waitForCallCount(2)
        await gate.releaseNext()
        await model.waitForPendingSave()

        let expected = SocialPushType.setEnabled(
            .newFollower,
            enabled: false,
            in: SocialPushType.setEnabled(.followRequest, enabled: false, in: 0)
        )
        XCTAssertEqual(model.disabledMask, expected)
        let maximumConcurrentCalls = await gate.maximumConcurrentCalls
        let requestedMasks = await gate.requestedMasks
        XCTAssertEqual(maximumConcurrentCalls, 1)
        XCTAssertEqual(requestedMasks, [
            SocialPushType.setEnabled(.followRequest, enabled: false, in: 0),
            expected
        ])
    }

    func testFailedSaveRollsBackToConfirmedMask() async {
        let profile = SocialProfile(userId: "user", handle: "handle", displayName: "Name")
        let model = SocialNotificationSettingsViewModel(profile: profile, updateProfile: { _ in nil })

        model.set(.followRequest, enabled: false)
        await model.waitForPendingSave()

        XCTAssertEqual(model.disabledMask, profile.socialPushDisabled)
        XCTAssertNotNil(model.saveError)
    }
}

@MainActor
final class SocialCoordinatorCommentsTests: DBTestCase {
    func testCommentsViewModelRefreshesMissingEpisodeAndPopulatesTitles() async {
        let episodeUuid = "push-episode-\(UUID().uuidString)"
        let podcastUuid = "push-podcast-\(UUID().uuidString)"
        var refreshCount = 0
        let manager = dataManager!

        let model = await SocialCoordinator.commentsViewModel(
            episodeUuid: episodeUuid,
            podcastUuid: podcastUuid,
            focusCommentId: 42,
            refreshIfNeeded: {
                refreshCount += 1
                var podcast = Podcast()
                podcast.uuid = podcastUuid
                podcast.title = "Resolved Podcast"
                podcast.addedDate = Date()
                let savedPodcast = manager.save(podcast: podcast)

                var episode = Episode()
                episode.uuid = episodeUuid
                episode.podcastUuid = podcastUuid
                episode.podcast_id = savedPodcast.id
                episode.title = "Resolved Episode"
                episode.duration = 100
                episode.playedUpTo = 30
                manager.save(episode: episode)
            }
        )
        if let resolvedPodcast = dataManager.findPodcast(uuid: podcastUuid, includeUnsubscribed: true) {
            track(podcast: resolvedPodcast)
        }
        if let resolvedEpisode = dataManager.findEpisode(uuid: episodeUuid) as? Episode {
            track(episode: resolvedEpisode)
        }

        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(model.episodeTitle, "Resolved Episode")
        XCTAssertEqual(model.podcastTitle, "Resolved Podcast")
        XCTAssertEqual(model.podcastUuid, podcastUuid)
        XCTAssertEqual(model.focusCommentId, 42)
        XCTAssertTrue(model.canSeed)
    }
}

private actor ProfileUpdateGate {
    private var calls: [SocialProfile] = []
    private var pending: [(SocialProfile, CheckedContinuation<SocialProfile?, Never>)] = []
    private var callCountWaiters: [(expected: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var activeCalls = 0
    private(set) var maximumConcurrentCalls = 0

    var callCount: Int { calls.count }
    var requestedMasks: [Int64] { calls.map(\.socialPushDisabled) }

    func update(_ profile: SocialProfile) async -> SocialProfile? {
        calls.append(profile)
        let satisfiedWaiters = callCountWaiters.filter { calls.count >= $0.expected }
        callCountWaiters.removeAll { calls.count >= $0.expected }
        satisfiedWaiters.forEach { $0.continuation.resume() }
        activeCalls += 1
        maximumConcurrentCalls = max(maximumConcurrentCalls, activeCalls)
        let result = await withCheckedContinuation { pending.append((profile, $0)) }
        activeCalls -= 1
        return result
    }

    func waitForCallCount(_ expected: Int) async {
        guard calls.count < expected else { return }

        await withCheckedContinuation { continuation in
            callCountWaiters.append((expected, continuation))
        }
    }

    func releaseNext() {
        guard !pending.isEmpty else { return }
        let (profile, continuation) = pending.removeFirst()
        continuation.resume(returning: profile)
    }
}
