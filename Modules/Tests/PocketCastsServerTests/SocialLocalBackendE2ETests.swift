import CryptoKit
import XCTest
import SwiftProtobuf
@testable import PocketCastsServer

/// End-to-end proof of the Swift↔Go social wire contract against the REAL
/// local backend (docs/Social.md "backend live before ship"). Run it with
/// `mise run test:e2e-social`, which checks the Docker backend is up and
/// exports `POCKET_CASTS_SERVER_BASE_URL` the correct way (a true environment
/// variable — passed as an xcodebuild *argument* it becomes a build setting
/// and never reaches the process).
///
/// A missing env var is a hard FAILURE, not a skip: a skipped E2E suite reads
/// as green while proving nothing, which already bit one session. The class is
/// excluded from the UnitTests plan (`skippedTests`) so plan sweeps and CI —
/// which have no backend — never touch it; every explicit run must have the
/// var or it errors.
///
/// Uses URLSession + the generated `Api_*` messages directly (no app global
/// state), registering throwaway accounts per run. Mirrors the backend's
/// `TestSocialIdentityLoop` e2e test.
final class SocialLocalBackendE2ETests: XCTestCase {
    private struct MissingBackendConfiguration: Error {}

    private var baseURL: URL!

    override func setUpWithError() throws {
        guard let raw = ProcessInfo.processInfo.environment["POCKET_CASTS_SERVER_BASE_URL"],
              let url = URL(string: raw) else {
            XCTFail("""
            POCKET_CASTS_SERVER_BASE_URL is not set — this E2E suite must run against the live \
            local backend and refuses to silently skip. Use `mise run test:e2e-social` (or export \
            TEST_RUNNER_POCKET_CASTS_SERVER_BASE_URL as an ENVIRONMENT VARIABLE to xcodebuild — \
            as a command-line argument it becomes a build setting and never reaches the tests).
            """)
            throw MissingBackendConfiguration()
        }
        baseURL = url
    }

    func testSocialFoundationLoop() async throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let handle = "ios_e2e_\(suffix)"

        // Register two throwaway accounts.
        let (tokenA, _) = try await register(email: "ios-social-a-\(suffix)@e2e.test")
        let (tokenB, uuidB) = try await register(email: "ios-social-b-\(suffix)@e2e.test")

        // Availability: fresh handle claimable, normalization applied, reserved word refused.
        var availability = Api_HandleAvailabilityRequest()
        availability.handle = "  @\(handle.uppercased()) "
        var (status, body) = try await post("social/handle/availability", token: tokenA, message: availability)
        XCTAssertEqual(status, 200)
        var availResponse = try Api_HandleAvailabilityResponse(serializedBytes: body)
        XCTAssertEqual(availResponse.status, .available)
        XCTAssertEqual(availResponse.normalizedHandle, handle)

        availability.handle = "admin"
        (status, body) = try await post("social/handle/availability", token: tokenA, message: availability)
        XCTAssertEqual(status, 200)
        availResponse = try Api_HandleAvailabilityResponse(serializedBytes: body)
        XCTAssertEqual(availResponse.status, .reserved)

        // Join as A: profile created, all visibility private by default (ADR-0006).
        var join = Api_JoinRequest()
        join.handle = handle
        join.acceptedTermsVersion = 1
        join.displayName = "iOS E2E Person"
        (status, body) = try await post("social/join", token: tokenA, message: join)
        XCTAssertEqual(status, 200)
        let joined = try Api_JoinResponse(serializedBytes: body)
        XCTAssertEqual(joined.profile.handle, handle)
        XCTAssertEqual(joined.profile.bioVisibility, .private)
        XCTAssertEqual(joined.profile.statsVisibility, .private)
        XCTAssertTrue(joined.profile.avatarURL.isEmpty, "avatars are deferred from this slice")

        // Same handle is now taken; B's claim loses with 409.
        availability.handle = handle
        (status, body) = try await post("social/handle/availability", token: tokenB, message: availability)
        XCTAssertEqual(status, 200)
        availResponse = try Api_HandleAvailabilityResponse(serializedBytes: body)
        XCTAssertEqual(availResponse.status, .taken)

        (status, _) = try await post("social/join", token: tokenB, message: join)
        XCTAssertEqual(status, 409)

        // Own-profile get, then update making the bio public.
        (status, body) = try await post("social/profile/get", token: tokenA, message: Api_ProfileGetRequest())
        XCTAssertEqual(status, 200)
        let fetched = try Api_ProfileResponse(serializedBytes: body)
        XCTAssertEqual(fetched.profile.displayName, "iOS E2E Person")

        var update = Api_ProfileUpdateRequest()
        update.displayName = "iOS E2E Person"
        update.bio = "hello from the iOS e2e suite"
        update.bioVisibility = .public
        (status, body) = try await post("social/profile/update", token: tokenA, message: update)
        XCTAssertEqual(status, 200)
        let updated = try Api_ProfileResponse(serializedBytes: body)
        XCTAssertEqual(updated.profile.bioVisibility, .public)
        XCTAssertEqual(updated.profile.statsVisibility, .private, "unspecified folds to private")
        XCTAssertEqual(updated.profile.handle, handle, "handle is immutable")

        // Public read as B: public bio visible, private stats absent, and all
        // sections empty while their visibility fields are private.
        var publicRequest = Api_PublicProfileRequest()
        publicRequest.handle = handle
        (status, body) = try await post("social/profile/public", token: tokenB, message: publicRequest)
        XCTAssertEqual(status, 200)
        let publicProfile = try Api_PublicProfileResponse(serializedBytes: body)
        XCTAssertEqual(publicProfile.bio, "hello from the iOS e2e suite")
        XCTAssertFalse(publicProfile.hasStats_p)
        XCTAssertTrue(publicProfile.followedShows.isEmpty)
        XCTAssertTrue(publicProfile.topPodcasts.isEmpty)
        XCTAssertTrue(publicProfile.recentlyPlayed.isEmpty)
        XCTAssertFalse(publicProfile.hasStats)

        // Making stats public exposes the totals section to other viewers.
        var statsUpdate = Api_ProfileUpdateRequest()
        statsUpdate.displayName = "iOS E2E Person"
        statsUpdate.bio = "hello from the iOS e2e suite"
        statsUpdate.bioVisibility = .public
        statsUpdate.statsVisibility = .public
        (status, _) = try await post("social/profile/update", token: tokenA, message: statsUpdate)
        XCTAssertEqual(status, 200)

        (status, body) = try await post("social/profile/public", token: tokenB, message: publicRequest)
        XCTAssertEqual(status, 200)
        let withStats = try Api_PublicProfileResponse(serializedBytes: body)
        XCTAssertTrue(withStats.hasStats_p)
        XCTAssertTrue(withStats.hasStats, "stats message present when visible")

        // The web Profile Link page renders for anonymous viewers (ADR-0008).
        var pageRequest = URLRequest(url: baseURL.appendingPathComponent("u/\(handle)"))
        pageRequest.httpMethod = "GET"
        let (pageData, pageResponse) = try await URLSession.shared.data(for: pageRequest)
        XCTAssertEqual((pageResponse as? HTTPURLResponse)?.statusCode, 200)
        let html = String(data: pageData, encoding: .utf8) ?? ""
        XCTAssertTrue(html.contains("@" + handle))
        XCTAssertTrue(html.contains("thcast://profile/" + handle))

        // A blocks B: mutual invisibility — B's read of A becomes not-found.
        var block = Api_BlockRequest()
        block.targetUserID = uuidB
        (status, body) = try await post("social/block", token: tokenA, message: block)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        (status, _) = try await post("social/profile/public", token: tokenB, message: publicRequest)
        XCTAssertEqual(status, 404)

        // Unblock restores the read.
        (status, body) = try await post("social/unblock", token: tokenA, message: block)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        (status, _) = try await post("social/profile/public", token: tokenB, message: publicRequest)
        XCTAssertEqual(status, 200)

        // B reports A into the triage queue.
        var report = Api_ReportRequest()
        report.targetUserID = joined.profile.userID
        report.reason = .spam
        report.context = "ios e2e report"
        (status, body) = try await post("social/report", token: tokenB, message: report)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        // Erase A: profile gone, handle tombstoned forever (ADR-0005).
        (status, body) = try await post("social/erase", token: tokenA, message: Api_EraseRequest())
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        (status, _) = try await post("social/profile/get", token: tokenA, message: Api_ProfileGetRequest())
        XCTAssertEqual(status, 404)

        (status, body) = try await post("social/handle/availability", token: tokenB, message: availability)
        XCTAssertEqual(status, 200)
        availResponse = try Api_HandleAvailabilityResponse(serializedBytes: body)
        XCTAssertEqual(availResponse.status, .tombstoned)

        (status, _) = try await post("social/join", token: tokenB, message: join)
        XCTAssertEqual(status, 409, "tombstoned handles are never reissued")
    }

    /// Slice-3 wire contract: attributed review text (join + listen-gated) and
    /// account-level reactions with counts-only reads.
    func testReviewsAndReactionsLoop() async throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let (token, _) = try await register(email: "ios-review-\(suffix)@e2e.test")
        let podcastUuid = "dddddddd-0000-0000-0000-00000000\(String(suffix.prefix(4)))"
        let episodeUuid = "eeeeeeee-0000-0000-0000-00000000\(String(suffix.prefix(4)))"

        // Review submit before joining: forbidden.
        var submit = Api_PodcastReviewSubmitRequest()
        submit.podcastUuid = podcastUuid
        submit.text = "not yet"
        var (status, body) = try await post("social/review/submit", token: token, message: submit)
        XCTAssertEqual(status, 403)

        // Join, sync two played episodes of the podcast, then submit.
        var join = Api_JoinRequest()
        join.handle = "ios_rev_\(suffix)"
        join.acceptedTermsVersion = 1
        join.displayName = "iOS Reviewer"
        (status, _) = try await post("social/join", token: token, message: join)
        XCTAssertEqual(status, 200)

        var sync = Api_SyncUpdateRequest()
        sync.deviceUtcTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
        for index in 0..<2 {
            var episode = Api_SyncUserEpisode()
            episode.uuid = "eeeeeeee-0000-0000-000\(index)-00000000\(String(suffix.prefix(4)))"
            episode.podcastUuid = podcastUuid
            episode.duration = Google_Protobuf_Int64Value(600)
            episode.durationModified = Google_Protobuf_Int64Value(sync.deviceUtcTimeMs)
            episode.playedUpTo = Google_Protobuf_Int64Value(500)
            episode.playedUpToModified = Google_Protobuf_Int64Value(sync.deviceUtcTimeMs)
            var record = Api_Record()
            record.episode = episode
            sync.records.append(record)
        }
        (status, _) = try await post("user/sync/update", token: token, message: sync)
        XCTAssertEqual(status, 200)

        submit.text = "an attributed opinion from iOS"
        (status, body) = try await post("social/review/submit", token: token, message: submit)
        XCTAssertEqual(status, 200)
        let review = try Api_PodcastReview(serializedBytes: body)
        XCTAssertEqual(review.handle, "ios_rev_\(suffix)")

        // Public list carries it + your_review for the author.
        var listRequest = Api_PodcastReviewsRequest()
        listRequest.podcastUuid = podcastUuid
        (status, body) = try await post("podcast/reviews", token: token, message: listRequest)
        XCTAssertEqual(status, 200)
        let page = try Api_PodcastReviewsResponse(serializedBytes: body)
        XCTAssertEqual(page.reviews.count, 1)
        XCTAssertTrue(page.hasYourReview)

        // Reactions: set -> counts + own; clear -> empty.
        var setReaction = Api_EpisodeReactionSetRequest()
        setReaction.episodeUuid = episodeUuid
        setReaction.kind = .fire
        (status, body) = try await post("social/reaction/set", token: token, message: setReaction)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        var reactionsRequest = Api_EpisodeReactionsRequest()
        reactionsRequest.episodeUuid = episodeUuid
        (status, body) = try await post("episode/reactions", token: token, message: reactionsRequest)
        XCTAssertEqual(status, 200)
        var reactions = try Api_EpisodeReactionsResponse(serializedBytes: body)
        XCTAssertEqual(reactions.counts.count, 1)
        XCTAssertEqual(reactions.counts.first?.kind, .fire)
        XCTAssertEqual(reactions.yourReaction, .fire)

        setReaction.kind = .unspecified
        (status, _) = try await post("social/reaction/set", token: token, message: setReaction)
        XCTAssertEqual(status, 200)
        (status, body) = try await post("episode/reactions", token: token, message: reactionsRequest)
        XCTAssertEqual(status, 200)
        reactions = try Api_EpisodeReactionsResponse(serializedBytes: body)
        XCTAssertTrue(reactions.counts.isEmpty)

        // Erase: the attributed review vanishes from the public list.
        (status, _) = try await post("social/erase", token: token, message: Api_EraseRequest())
        XCTAssertEqual(status, 200)
        (status, body) = try await post("podcast/reviews", token: token, message: listRequest)
        XCTAssertEqual(status, 200)
        let afterErase = try Api_PodcastReviewsResponse(serializedBytes: body)
        XCTAssertTrue(afterErase.reviews.isEmpty, "attributed review text dies with the profile")
    }

    /// Slice-4 wire contract: send-to-friend + the shared-item inbox.
    func testSendToFriendAndInboxLoop() async throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let (tokenA, senderUserId) = try await register(email: "ios-send-a-\(suffix)@e2e.test")
        let (tokenB, _) = try await register(email: "ios-send-b-\(suffix)@e2e.test")
        let (blockedToken, _) = try await register(email: "ios-send-blocked-\(suffix)@e2e.test")
        let (tombstonedToken, _) = try await register(email: "ios-send-tombstoned-\(suffix)@e2e.test")

        let blockedHandle = "ios_snd_blk_\(suffix)"
        let tombstonedHandle = "ios_snd_del_\(suffix)"

        for (token, handle, name) in [(tokenA, "ios_snd_a_\(suffix)", "Sender A"),
                                      (tokenB, "ios_snd_b_\(suffix)", "Recipient B"),
                                      (blockedToken, blockedHandle, "Blocked Recipient"),
                                      (tombstonedToken, tombstonedHandle, "Deleted Recipient")] {
            var join = Api_JoinRequest()
            join.handle = handle
            join.acceptedTermsVersion = 1
            join.displayName = name
            let (status, _) = try await post("social/join", token: token, message: join)
            XCTAssertEqual(status, 200)
        }

        // Prepare two privacy-sensitive recipients: one who blocked the
        // sender, and one whose profile/PII was erased but whose handle remains
        // tombstoned.
        var blockSender = Api_BlockRequest()
        blockSender.targetUserID = senderUserId
        var (status, body) = try await post("social/block", token: blockedToken, message: blockSender)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        (status, body) = try await post("social/erase", token: tombstonedToken, message: Api_EraseRequest())
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        var send = Api_SharedItemSendRequest()
        send.recipientHandle = "ios_snd_b_\(suffix)"
        send.episodeUuid = "ios-episode-\(suffix)"
        send.podcastUuid = "ios-podcast-\(suffix)"
        send.episodeTitle = "A Sent Episode"
        send.podcastTitle = "A Sent Podcast"
        send.note = "you'll love this bit"
        send.timestampSeconds = 615
        (status, body) = try await post("social/share/send", token: tokenA, message: send)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        // B's inbox: one unread item, fully attributed.
        (status, body) = try await post("social/inbox", token: tokenB, message: Api_InboxRequest())
        XCTAssertEqual(status, 200)
        var inbox = try Api_InboxResponse(serializedBytes: body)
        XCTAssertEqual(inbox.items.count, 1)
        XCTAssertEqual(inbox.unread, 1)
        let item = try XCTUnwrap(inbox.items.first)
        XCTAssertEqual(item.senderHandle, "ios_snd_a_\(suffix)")
        XCTAssertEqual(item.episodeUuid, send.episodeUuid)
        XCTAssertEqual(item.podcastUuid, send.podcastUuid)
        XCTAssertEqual(item.episodeTitle, send.episodeTitle)
        XCTAssertEqual(item.podcastTitle, send.podcastTitle)
        XCTAssertEqual(item.note, "you'll love this bit")
        XCTAssertEqual(item.timestampSeconds, 615)
        XCTAssertFalse(item.read)

        // Mark read → unread drops.
        var markRead = Api_InboxMarkReadRequest()
        markRead.ids = [item.id]
        (status, _) = try await post("social/inbox/read", token: tokenB, message: markRead)
        XCTAssertEqual(status, 200)
        (status, body) = try await post("social/inbox", token: tokenB, message: Api_InboxRequest())
        XCTAssertEqual(status, 200)
        inbox = try Api_InboxResponse(serializedBytes: body)
        XCTAssertEqual(inbox.unread, 0)
        XCTAssertTrue(try XCTUnwrap(inbox.items.first).read)

        // Unknown, blocked, and tombstoned recipients are deliberately
        // indistinguishable: status and serialized error body must match.
        send.recipientHandle = "nobody_here_\(suffix)"
        let (unknownStatus, unknownBody) = try await post("social/share/send", token: tokenA, message: send)
        XCTAssertEqual(unknownStatus, 404)

        send.recipientHandle = blockedHandle
        let (blockedStatus, blockedBody) = try await post("social/share/send", token: tokenA, message: send)
        XCTAssertEqual(blockedStatus, unknownStatus)
        XCTAssertEqual(blockedBody, unknownBody)

        send.recipientHandle = tombstonedHandle
        let (tombstonedStatus, tombstonedBody) = try await post("social/share/send", token: tokenA, message: send)
        XCTAssertEqual(tombstonedStatus, unknownStatus)
        XCTAssertEqual(tombstonedBody, unknownBody)

        // Slice 15: a show recommendation — podcast, no episode — rides the
        // same pipeline; a send with neither is rejected.
        var recommend = Api_SharedItemSendRequest()
        recommend.recipientHandle = "ios_snd_b_\(suffix)"
        recommend.podcastUuid = "ios-recshow-\(suffix)"
        recommend.podcastTitle = "A Recommended Show"
        recommend.note = "start with the pilot"
        let (recStatus, _) = try await post("social/share/send", token: tokenA, message: recommend)
        XCTAssertEqual(recStatus, 200)
        var invalid = Api_SharedItemSendRequest()
        invalid.recipientHandle = "ios_snd_b_\(suffix)"
        invalid.note = "nothing attached"
        let (invStatus, _) = try await post("social/share/send", token: tokenA, message: invalid)
        XCTAssertEqual(invStatus, 400)

        let inboxCheck = Api_InboxRequest()
        let (recInboxStatus, recBody) = try await post("social/inbox", token: tokenB, message: inboxCheck)
        XCTAssertEqual(recInboxStatus, 200)
        let recInbox = try Api_InboxResponse(serializedBytes: recBody)
        let showItem = recInbox.items.first { $0.episodeUuid.isEmpty }
        XCTAssertNotNil(showItem, "show recommendation must land in the inbox")
        XCTAssertEqual(showItem?.podcastTitle, "A Recommended Show")

        // Sender erases: the delivered item vanishes from B's inbox.
        (status, _) = try await post("social/erase", token: tokenA, message: Api_EraseRequest())
        XCTAssertEqual(status, 200)
        (status, body) = try await post("social/inbox", token: tokenB, message: Api_InboxRequest())
        XCTAssertEqual(status, 200)
        inbox = try Api_InboxResponse(serializedBytes: body)
        XCTAssertTrue(inbox.items.isEmpty, "sent items die with the sender's profile")
    }

    /// Slice-5 wire contract: the follow graph (open + approval-gated) and the
    /// derived activity feed with per-field visibility gating and mute.
    func testFollowGraphAndFeedLoop() async throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let (tokenA, _) = try await register(email: "ios-graph-a-\(suffix)@e2e.test")
        let (tokenB, _) = try await register(email: "ios-graph-b-\(suffix)@e2e.test")
        let (tokenC, _) = try await register(email: "ios-graph-c-\(suffix)@e2e.test")

        let handleA = "ios_gra_a_\(suffix)"
        for (token, handle, name) in [(tokenA, handleA, "Feed Actor A"),
                                      (tokenB, "ios_gra_b_\(suffix)", "Follower B"),
                                      (tokenC, "ios_gra_c_\(suffix)", "Requester C")] {
            var join = Api_JoinRequest()
            join.handle = handle
            join.acceptedTermsVersion = 1
            join.displayName = name
            let (status, _) = try await post("social/join", token: token, message: join)
            XCTAssertEqual(status, 200)
        }

        // B follows A: open by default → immediately active.
        var follow = Api_FollowRequest()
        follow.handle = handleA
        var (status, body) = try await post("social/follow", token: tokenB, message: follow)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(try Api_FollowResponse(serializedBytes: body).state, .active)

        // A's public profile as B: counts + your_follow_state reflect it.
        var publicRequest = Api_PublicProfileRequest()
        publicRequest.handle = handleA
        (status, body) = try await post("social/profile/public", token: tokenB, message: publicRequest)
        XCTAssertEqual(status, 200)
        var profileAsB = try Api_PublicProfileResponse(serializedBytes: body)
        XCTAssertEqual(profileAsB.followerCount, 1)
        XCTAssertEqual(profileAsB.yourFollowState, .active)

        // A syncs a finished episode; history stays private → B's feed shows
        // only the joined event, no listening-derived items (decision 3).
        var sync = Api_SyncUpdateRequest()
        sync.deviceUtcTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
        var episode = Api_SyncUserEpisode()
        episode.uuid = "ffffffff-0000-0000-0000-00000000\(String(suffix.prefix(4)))"
        episode.podcastUuid = "cccccccc-0000-0000-0000-00000000\(String(suffix.prefix(4)))"
        episode.duration = Google_Protobuf_Int64Value(600)
        episode.durationModified = Google_Protobuf_Int64Value(sync.deviceUtcTimeMs)
        episode.playedUpTo = Google_Protobuf_Int64Value(600)
        episode.playedUpToModified = Google_Protobuf_Int64Value(sync.deviceUtcTimeMs)
        episode.playingStatus = Google_Protobuf_Int32Value(3) // completed
        episode.playingStatusModified = Google_Protobuf_Int64Value(sync.deviceUtcTimeMs)
        var record = Api_Record()
        record.episode = episode
        sync.records.append(record)
        (status, _) = try await post("user/sync/update", token: tokenA, message: sync)
        XCTAssertEqual(status, 200)

        (status, body) = try await post("social/feed", token: tokenB, message: Api_FeedRequest())
        XCTAssertEqual(status, 200)
        var feed = try Api_FeedResponse(serializedBytes: body)
        XCTAssertTrue(feed.items.contains { $0.kind == .joined && $0.actorHandle == handleA })
        XCTAssertFalse(feed.items.contains { $0.kind == .finishedEpisode },
                       "private history must not leak into follower feeds")

        // A flips history to followers-only → the finished episode appears.
        var update = Api_ProfileUpdateRequest()
        update.displayName = "Feed Actor A"
        update.historyVisibility = .followersOnly
        (status, _) = try await post("social/profile/update", token: tokenA, message: update)
        XCTAssertEqual(status, 200)

        (status, body) = try await post("social/feed", token: tokenB, message: Api_FeedRequest())
        XCTAssertEqual(status, 200)
        feed = try Api_FeedResponse(serializedBytes: body)
        XCTAssertTrue(feed.items.contains { $0.kind == .finishedEpisode && $0.actorHandle == handleA },
                      "followers-only history is visible to an active follower")

        // B's own lists: following contains A; A's followers contain B.
        var listRequest = Api_FollowListRequest()
        listRequest.followers = false
        (status, body) = try await post("social/follows", token: tokenB, message: listRequest)
        XCTAssertEqual(status, 200)
        let following = try Api_FollowListResponse(serializedBytes: body)
        XCTAssertTrue(following.entries.contains { $0.handle == handleA })

        // A enables the approval toggle; C's follow becomes a pending request.
        update.requireFollowApproval = true
        update.historyVisibility = .followersOnly
        (status, _) = try await post("social/profile/update", token: tokenA, message: update)
        XCTAssertEqual(status, 200)

        (status, body) = try await post("social/follow", token: tokenC, message: follow)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(try Api_FollowResponse(serializedBytes: body).state, .pending)

        // Pending ≠ follower: C cannot see the followers-only feed items yet.
        (status, body) = try await post("social/feed", token: tokenC, message: Api_FeedRequest())
        XCTAssertEqual(status, 200)
        feed = try Api_FeedResponse(serializedBytes: body)
        XCTAssertFalse(feed.items.contains { $0.actorHandle == handleA },
                       "a pending follow contributes nothing to the feed")

        // A sees the request and accepts it; C is now active.
        (status, body) = try await post("social/follow/requests", token: tokenA, message: Api_FollowRequestsRequest())
        XCTAssertEqual(status, 200)
        let requests = try Api_FollowListResponse(serializedBytes: body)
        XCTAssertTrue(requests.entries.contains { $0.handle == "ios_gra_c_\(suffix)" })

        var approval = Api_FollowApprovalRequest()
        approval.requesterHandle = "ios_gra_c_\(suffix)"
        approval.accept = true
        (status, body) = try await post("social/follow/approve", token: tokenA, message: approval)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        (status, body) = try await post("social/feed", token: tokenC, message: Api_FeedRequest())
        XCTAssertEqual(status, 200)
        feed = try Api_FeedResponse(serializedBytes: body)
        XCTAssertTrue(feed.items.contains { $0.kind == .finishedEpisode && $0.actorHandle == handleA },
                      "an approved follower unlocks followers-only items")

        // B mutes A: A's items vanish from B's feed (one-way, unannounced).
        (status, body) = try await post("social/profile/public", token: tokenB, message: publicRequest)
        XCTAssertEqual(status, 200)
        profileAsB = try Api_PublicProfileResponse(serializedBytes: body)
        var mute = Api_MuteRequest()
        mute.targetUserID = profileAsB.userID
        (status, body) = try await post("social/mute", token: tokenB, message: mute)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        (status, body) = try await post("social/feed", token: tokenB, message: Api_FeedRequest())
        XCTAssertEqual(status, 200)
        feed = try Api_FeedResponse(serializedBytes: body)
        XCTAssertFalse(feed.items.contains { $0.actorHandle == handleA },
                       "muted actors are filtered from the feed")

        // B unfollows: A's follower count drops and B's state resets.
        var unfollow = Api_UnfollowRequest()
        unfollow.handle = handleA
        (status, body) = try await post("social/unfollow", token: tokenB, message: unfollow)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        (status, body) = try await post("social/profile/public", token: tokenB, message: publicRequest)
        XCTAssertEqual(status, 200)
        profileAsB = try Api_PublicProfileResponse(serializedBytes: body)
        XCTAssertEqual(profileAsB.followerCount, 1, "only C remains")
        XCTAssertEqual(profileAsB.yourFollowState, .none)

        // Erase A: C's following list empties (follows die with the profile).
        (status, _) = try await post("social/erase", token: tokenA, message: Api_EraseRequest())
        XCTAssertEqual(status, 200)
        (status, body) = try await post("social/follows", token: tokenC, message: listRequest)
        XCTAssertEqual(status, 200)
        let cFollowing = try Api_FollowListResponse(serializedBytes: body)
        XCTAssertFalse(cFollowing.entries.contains { $0.handle == handleA })
    }

    /// Slice-6 wire contract: the episode comment tree (ADR-0010) — seed gate,
    /// ungated replies, grace-window edit, tombstoned delete, inbox replies
    /// watermark, and the commented feed item.
    func testCommentTreeLoop() async throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let (tokenA, _) = try await register(email: "ios-cmt-a-\(suffix)@e2e.test")
        let (tokenB, _) = try await register(email: "ios-cmt-b-\(suffix)@e2e.test")

        let handleA = "ios_cmt_a_\(suffix)"
        for (token, handle, name) in [(tokenA, handleA, "Commenter A"), (tokenB, "ios_cmt_b_\(suffix)", "Replier B")] {
            var join = Api_JoinRequest()
            join.handle = handle
            join.acceptedTermsVersion = 1
            join.displayName = name
            let (status, _) = try await post("social/join", token: token, message: join)
            XCTAssertEqual(status, 200)
        }

        let episodeUuid = "abcdabcd-0000-0000-0000-00000000\(String(suffix.prefix(4)))"
        let podcastUuid = "dcbadcba-0000-0000-0000-00000000\(String(suffix.prefix(4)))"

        // Seed before playing: the listen-gate refuses.
        var submit = Api_CommentSubmitRequest()
        submit.episodeUuid = episodeUuid
        submit.podcastUuid = podcastUuid
        submit.episodeTitle = "A Discussed Episode"
        submit.text = "too soon"
        var (status, body) = try await post("social/comment/submit", token: tokenA, message: submit)
        XCTAssertEqual(status, 403)

        // A syncs ≥25% played, then a timestamped seed (a Moment) lands.
        var sync = Api_SyncUpdateRequest()
        sync.deviceUtcTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
        var episode = Api_SyncUserEpisode()
        episode.uuid = episodeUuid
        episode.podcastUuid = podcastUuid
        episode.duration = Google_Protobuf_Int64Value(600)
        episode.durationModified = Google_Protobuf_Int64Value(sync.deviceUtcTimeMs)
        episode.playedUpTo = Google_Protobuf_Int64Value(200)
        episode.playedUpToModified = Google_Protobuf_Int64Value(sync.deviceUtcTimeMs)
        var record = Api_Record()
        record.episode = episode
        sync.records.append(record)
        (status, _) = try await post("user/sync/update", token: tokenA, message: sync)
        XCTAssertEqual(status, 200)

        // Slice 12: a quote without a timestamp is rejected — quotes are
        // Moments by construction.
        submit.text = "orphan"
        submit.quote = "we shipped it on a friday"
        (status, _) = try await post("social/comment/submit", token: tokenA, message: submit)
        XCTAssertEqual(status, 400)

        submit.text = "this bit at two minutes"
        submit.timestampSeconds = 125
        submit.quoteSource = 1
        submit.quoteSegment = 7
        (status, body) = try await post("social/comment/submit", token: tokenA, message: submit)
        XCTAssertEqual(status, 200)
        let seed = try Api_SocialComment(serializedBytes: body)
        XCTAssertEqual(seed.handle, handleA)
        XCTAssertEqual(seed.timestampSeconds, 125)
        XCTAssertEqual(seed.quote, "we shipped it on a friday")
        XCTAssertEqual(seed.quoteSegment, 7)

        // B replies without playing anything: replies are ungated.
        var reply = Api_CommentSubmitRequest()
        reply.episodeUuid = episodeUuid
        reply.text = "agreed!"
        reply.parentID = seed.id
        (status, body) = try await post("social/comment/submit", token: tokenB, message: reply)
        XCTAssertEqual(status, 200)

        // The public top-level list: one seed carrying one reply.
        var listRequest = Api_EpisodeCommentsRequest()
        listRequest.episodeUuid = episodeUuid
        (status, body) = try await post("episode/comments", token: tokenB, message: listRequest)
        XCTAssertEqual(status, 200)
        var page = try Api_CommentsResponse(serializedBytes: body)
        XCTAssertEqual(page.comments.count, 1)
        XCTAssertEqual(page.comments.first?.replyCount, 1)
        XCTAssertEqual(page.comments.first?.quote, "we shipped it on a friday")
        XCTAssertEqual(page.comments.first?.quoteSource, 1)

        // Edit after reply: grace window shut.
        var edit = Api_CommentEditRequest()
        edit.id = seed.id
        edit.text = "revised"
        (status, _) = try await post("social/comment/edit", token: tokenA, message: edit)
        XCTAssertEqual(status, 409)

        // A's inbox replies: one unread from B; seen resets the watermark.
        (status, body) = try await post("social/inbox/replies", token: tokenA, message: Api_InboxRepliesRequest())
        XCTAssertEqual(status, 200)
        var inbox = try Api_InboxRepliesResponse(serializedBytes: body)
        XCTAssertEqual(inbox.replies.count, 1)
        XCTAssertEqual(inbox.unread, 1)
        XCTAssertEqual(inbox.replies.first?.episodeTitle, "A Discussed Episode")

        (status, _) = try await post("social/inbox/replies/seen", token: tokenA, message: Api_InboxRepliesRequest())
        XCTAssertEqual(status, 200)
        (status, body) = try await post("social/inbox/replies", token: tokenA, message: Api_InboxRepliesRequest())
        inbox = try Api_InboxRepliesResponse(serializedBytes: body)
        XCTAssertEqual(inbox.unread, 0)

        // B follows A: the seed appears as a commented feed item.
        var follow = Api_FollowRequest()
        follow.handle = handleA
        (status, _) = try await post("social/follow", token: tokenB, message: follow)
        XCTAssertEqual(status, 200)
        (status, body) = try await post("social/feed", token: tokenB, message: Api_FeedRequest())
        XCTAssertEqual(status, 200)
        let feed = try Api_FeedResponse(serializedBytes: body)
        XCTAssertTrue(feed.items.contains { $0.kind == .commented && $0.actorHandle == handleA },
                      "the seed must surface as a commented feed item")

        // A deletes the seed: tombstone keeps the reply anchored.
        var deleteRequest = Api_CommentDeleteRequest()
        deleteRequest.id = seed.id
        (status, _) = try await post("social/comment/delete", token: tokenA, message: deleteRequest)
        XCTAssertEqual(status, 200)
        (status, body) = try await post("episode/comments", token: tokenB, message: listRequest)
        page = try Api_CommentsResponse(serializedBytes: body)
        XCTAssertEqual(page.comments.count, 1)
        XCTAssertTrue(page.comments.first?.removed ?? false)
        XCTAssertTrue(page.comments.first?.text.isEmpty ?? false)
        XCTAssertTrue(page.comments.first?.quote.isEmpty ?? false, "tombstones wipe the quote with the text")
        XCTAssertEqual(page.comments.first?.replyCount, 1)
    }

    /// Slice-7 wire contract: shared lists (ADR-0011) — visibility gating,
    /// subscribe, the collaborator invite loop with attributed entries, kick,
    /// the profile Lists section, owner-death — plus the custom-playlist sync
    /// overturn round-trip.
    func testSharedListsLoop() async throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let (tokenA, _) = try await register(email: "ios-lst-a-\(suffix)@e2e.test")
        let (tokenB, _) = try await register(email: "ios-lst-b-\(suffix)@e2e.test")

        let handleA = "ios_lst_a_\(suffix)"
        let handleB = "ios_lst_b_\(suffix)"
        for (token, handle, name) in [(tokenA, handleA, "List Owner"), (tokenB, handleB, "List Friend")] {
            var join = Api_JoinRequest()
            join.handle = handle
            join.acceptedTermsVersion = 1
            join.displayName = name
            let (status, _) = try await post("social/join", token: token, message: join)
            XCTAssertEqual(status, 200)
        }

        // Create private with an initial snapshot; B cannot see it.
        var create = Api_SharedListCreateRequest()
        create.title = "iOS Road Trip"
        create.visibility = .private
        var seedEntry = Api_SharedListEntry()
        seedEntry.episodeUuid = "ep-ios-1"
        seedEntry.episodeTitle = "First"
        create.entries = [seedEntry]
        var (status, body) = try await post("social/list/create", token: tokenA, message: create)
        XCTAssertEqual(status, 200)
        let list = try Api_SharedList(serializedBytes: body)
        XCTAssertEqual(list.yourRole, .owner)

        var entriesRequest = Api_SharedListEntriesRequest()
        entriesRequest.listID = list.id
        (status, _) = try await post("social/list/entries", token: tokenB, message: entriesRequest)
        XCTAssertEqual(status, 404, "private lists must not leak")

        // Publish public: B sees it, subscribes, and it rides A's profile.
        var update = Api_SharedListUpdateRequest()
        update.listID = list.id
        update.title = "iOS Road Trip"
        update.visibility = .public
        (status, _) = try await post("social/list/update", token: tokenA, message: update)
        XCTAssertEqual(status, 200)

        (status, body) = try await post("social/list/entries", token: tokenB, message: entriesRequest)
        XCTAssertEqual(status, 200)
        var page = try Api_SharedListEntriesResponse(serializedBytes: body)
        XCTAssertEqual(page.entries.count, 1)
        XCTAssertEqual(page.entries.first?.addedByHandle, handleA)

        var subscribe = Api_SharedListSubscribeRequest()
        subscribe.listID = list.id
        subscribe.subscribe = true
        (status, _) = try await post("social/list/subscribe", token: tokenB, message: subscribe)
        XCTAssertEqual(status, 200)

        var profileRequest = Api_PublicProfileRequest()
        profileRequest.handle = handleA
        (status, body) = try await post("social/profile/public", token: tokenB, message: profileRequest)
        XCTAssertEqual(status, 200)
        let profile = try Api_PublicProfileResponse(serializedBytes: body)
        XCTAssertTrue(profile.lists.contains { $0.id == list.id }, "public lists ride the profile")

        // Invite → accept → collaborator adds an attributed entry.
        var invite = Api_SharedListInviteRequest()
        invite.listID = list.id
        invite.handle = handleB
        (status, _) = try await post("social/list/invite", token: tokenA, message: invite)
        XCTAssertEqual(status, 200)

        (status, body) = try await post("social/lists", token: tokenB, message: Api_SharedListsRequest())
        XCTAssertEqual(status, 200)
        let overview = try Api_SharedListsResponse(serializedBytes: body)
        XCTAssertTrue(overview.invites.contains { $0.id == list.id })

        var respond = Api_SharedListInviteRespondRequest()
        respond.listID = list.id
        respond.accept = true
        (status, _) = try await post("social/list/invite/respond", token: tokenB, message: respond)
        XCTAssertEqual(status, 200)

        var entryOp = Api_SharedListEntryOpRequest()
        entryOp.listID = list.id
        entryOp.op = .add
        entryOp.episodeUuid = "ep-ios-2"
        entryOp.episodeTitle = "Second"
        entryOp.position = -1
        (status, _) = try await post("social/list/entry", token: tokenB, message: entryOp)
        XCTAssertEqual(status, 200)

        (status, body) = try await post("social/list/entries", token: tokenA, message: entriesRequest)
        page = try Api_SharedListEntriesResponse(serializedBytes: body)
        XCTAssertEqual(page.entries.count, 2)
        XCTAssertEqual(page.entries.last?.addedByHandle, handleB)

        // Kick: B's edits stop with a 403.
        (status, _) = try await post("social/list/member/remove", token: tokenA, message: invite)
        XCTAssertEqual(status, 200)
        entryOp.episodeUuid = "ep-ios-3"
        (status, _) = try await post("social/list/entry", token: tokenB, message: entryOp)
        XCTAssertEqual(status, 403)

        // The custom-playlist overturn: the query envelope round-trips.
        var sync = Api_SyncUpdateRequest()
        sync.deviceUtcTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
        var playlist = Api_SyncUserPlaylist()
        playlist.uuid = "cc00cc00-1111-2222-3333-00000000\(String(suffix.prefix(4)))"
        playlist.title = Google_Protobuf_StringValue("iOS Custom")
        playlist.customQuery = Google_Protobuf_StringValue(#"{"version":1,"mode":"sql"}"#)
        var record = Api_Record()
        record.playlist = playlist
        sync.records.append(record)
        (status, _) = try await post("user/sync/update", token: tokenA, message: sync)
        XCTAssertEqual(status, 200)

        (status, body) = try await post("user/playlist/list", token: tokenA, message: Api_UserPlaylistListRequest())
        XCTAssertEqual(status, 200)
        let playlists = try Api_UserPlaylistListResponse(serializedBytes: body)
        let custom = playlists.playlists.first { $0.uuid.lowercased().hasPrefix("cc00cc00") }
        XCTAssertNotNil(custom)
        XCTAssertEqual(custom?.customQuery.value, #"{"version":1,"mode":"sql"}"#,
                       "custom_query must round-trip through sync")

        // Owner erase: the list dies for everyone.
        (status, _) = try await post("social/erase", token: tokenA, message: Api_EraseRequest())
        XCTAssertEqual(status, 200)
        (status, _) = try await post("social/list/entries", token: tokenB, message: entriesRequest)
        XCTAssertEqual(status, 404)
    }

    /// Slice-8 wire contract: the per-type push-disabled bitmask round-trips
    /// through profile update and decodes leniently. Actual APNs delivery is
    /// asserted by the backend's mock-APNs e2e (this suite can't receive
    /// pushes).
    /// Slice-13 wire contract: groups (ADR-0012) — private no-leak, invites,
    /// posts + replies, public join, succession on owner erasure.
    func testGroupsLoop() async throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let (tokenA, _) = try await register(email: "ios-grp-a-\(suffix)@e2e.test")
        let (tokenB, _) = try await register(email: "ios-grp-b-\(suffix)@e2e.test")

        let handleB = "ios_grp_b_\(suffix)"
        for (token, handle, name) in [(tokenA, "ios_grp_a_\(suffix)", "Group Owner"), (tokenB, handleB, "Group Member")] {
            var join = Api_JoinRequest()
            join.handle = handle
            join.acceptedTermsVersion = 1
            join.displayName = name
            let (status, _) = try await post("social/join", token: token, message: join)
            XCTAssertEqual(status, 200)
        }

        // A creates a public hub; B cannot yet be a member.
        var create = Api_GroupCreateRequest()
        create.title = "iOS Wire Hub"
        create.visibility = .public
        var (status, body) = try await post("social/group/create", token: tokenA, message: create)
        XCTAssertEqual(status, 200)
        let hub = try Api_SocialGroup(serializedBytes: body)
        XCTAssertEqual(hub.yourRole, .owner)

        // A posts; anonymous read of the public hub works and carries the group detail.
        var post_ = Api_GroupPostRequest()
        post_.groupID = hub.id
        post_.text = "welcome to the hub"
        (status, body) = try await post("social/group/post/submit", token: tokenA, message: post_)
        XCTAssertEqual(status, 200)
        let seed = try Api_GroupPost(serializedBytes: body)

        var postsReq = Api_GroupPostsRequest()
        postsReq.groupID = hub.id
        (status, body) = try await post("social/group/posts", token: nil, message: postsReq)
        XCTAssertEqual(status, 200)
        var page = try Api_GroupPostsResponse(serializedBytes: body)
        XCTAssertEqual(page.posts.count, 1)
        XCTAssertEqual(page.group.title, "iOS Wire Hub")

        // B joins one-tap, replies to the seed.
        var joinReq = Api_GroupJoinRequest()
        joinReq.id = hub.id
        (status, _) = try await post("social/group/join", token: tokenB, message: joinReq)
        XCTAssertEqual(status, 200)
        var reply = Api_GroupPostRequest()
        reply.groupID = hub.id
        reply.parentID = seed.id
        reply.text = "glad to be here"
        (status, _) = try await post("social/group/post/submit", token: tokenB, message: reply)
        XCTAssertEqual(status, 200)

        // A creates a private circle; B gets a no-leak 404 on its posts.
        create.title = "iOS Wire Circle"
        create.visibility = .private
        (status, body) = try await post("social/group/create", token: tokenA, message: create)
        XCTAssertEqual(status, 200)
        let circle = try Api_SocialGroup(serializedBytes: body)
        postsReq.groupID = circle.id
        (status, _) = try await post("social/group/posts", token: tokenB, message: postsReq)
        XCTAssertEqual(status, 404)

        // A erases: hub passes to B (succession), circle dies.
        (status, _) = try await post("social/erase", token: tokenA, message: Api_EraseRequest())
        XCTAssertEqual(status, 200)
        (status, body) = try await post("social/groups", token: tokenB, message: Api_GroupsRequest())
        XCTAssertEqual(status, 200)
        let groups = try Api_GroupsResponse(serializedBytes: body)
        let hubAfter = groups.groups.first { $0.id == hub.id }
        XCTAssertEqual(hubAfter?.yourRole, .owner, "hub passes to the longest-tenured member")
        XCTAssertFalse(groups.groups.contains { $0.id == circle.id }, "private circle dies with its owner")
    }

    /// Slice-14 wire contract: milestones (ADR-0013) — sync-detected
    /// crossings, stats-visibility gating, profile line, digest pref bit.
    func testMilestonesLoop() async throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let (tokenA, _) = try await register(email: "ios-mile-a-\(suffix)@e2e.test")
        let (tokenB, _) = try await register(email: "ios-mile-b-\(suffix)@e2e.test")

        let handleA = "ios_mile_a_\(suffix)"
        for (token, handle, name) in [(tokenA, handleA, "Milestone A"), (tokenB, "ios_mile_b_\(suffix)", "Watcher B")] {
            var join = Api_JoinRequest()
            join.handle = handle
            join.acceptedTermsVersion = 1
            join.displayName = name
            let (status, _) = try await post("social/join", token: token, message: join)
            XCTAssertEqual(status, 200)
        }

        // A syncs 12 finished hour-long episodes: tier-10 crossings on both
        // ladders materialize server-side.
        var sync = Api_SyncUpdateRequest()
        sync.deviceUtcTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
        for index in 0 ..< 12 {
            var episode = Api_SyncUserEpisode()
            episode.uuid = String(format: "abcd%04d-00bb-4000-8000-%@", index, String(suffix.prefix(4)) + "00000000")
            episode.podcastUuid = "dcba0000-00bb-4000-8000-000000000001"
            episode.duration = Google_Protobuf_Int64Value(3600)
            episode.durationModified = Google_Protobuf_Int64Value(sync.deviceUtcTimeMs)
            episode.playedUpTo = Google_Protobuf_Int64Value(3600)
            episode.playedUpToModified = Google_Protobuf_Int64Value(sync.deviceUtcTimeMs)
            episode.playingStatus = Google_Protobuf_Int32Value(3)
            episode.playingStatusModified = Google_Protobuf_Int64Value(sync.deviceUtcTimeMs)
            var record = Api_Record()
            record.episode = episode
            sync.records.append(record)
        }
        var (status, body) = try await post("user/sync/update", token: tokenA, message: sync)
        XCTAssertEqual(status, 200)

        // Stats public, B follows: kind-10 items surface with the tier.
        var update = Api_ProfileUpdateRequest()
        update.displayName = "Milestone A"
        update.statsVisibility = .public
        (status, _) = try await post("social/profile/update", token: tokenA, message: update)
        XCTAssertEqual(status, 200)
        var follow = Api_FollowRequest()
        follow.handle = handleA
        (status, _) = try await post("social/follow", token: tokenB, message: follow)
        XCTAssertEqual(status, 200)

        (status, body) = try await post("social/feed", token: tokenB, message: Api_FeedRequest())
        XCTAssertEqual(status, 200)
        let feed = try Api_FeedResponse(serializedBytes: body)
        XCTAssertTrue(feed.items.contains { $0.kind == .milestone && $0.milestoneTier == 10 },
                      "tier-10 crossing must surface as a milestone feed item")

        // The public profile carries the milestones line under the stats gate.
        var publicRequest = Api_PublicProfileRequest()
        publicRequest.handle = handleA
        (status, body) = try await post("social/profile/public", token: tokenB, message: publicRequest)
        XCTAssertEqual(status, 200)
        let profile = try Api_PublicProfileResponse(serializedBytes: body)
        XCTAssertFalse(profile.milestones.isEmpty)

        // Digest pref: disabling bit 9 round-trips through the profile.
        var prefs = Api_ProfileUpdateRequest()
        prefs.displayName = "Milestone A"
        prefs.statsVisibility = .public
        prefs.socialPushDisabled = 1 << 8
        (status, body) = try await post("social/profile/update", token: tokenA, message: prefs)
        XCTAssertEqual(status, 200)
        let updated = try Api_ProfileResponse(serializedBytes: body)
        XCTAssertEqual(updated.profile.socialPushDisabled, 1 << 8)
    }

    func testSocialPushPrefsLoop() async throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let (token, _) = try await register(email: "ios-push-\(suffix)@e2e.test")

        var join = Api_JoinRequest()
        join.handle = "ios_psh_\(suffix)"
        join.acceptedTermsVersion = 1
        join.displayName = "Push Prefs"
        var (status, body) = try await post("social/join", token: token, message: join)
        XCTAssertEqual(status, 200)
        let joined = try Api_JoinResponse(serializedBytes: body)
        XCTAssertEqual(joined.profile.socialPushDisabled, 0, "all types default on")

        // Disable new-follower (bit 2) + comment-reply (bit 4).
        var update = Api_ProfileUpdateRequest()
        update.displayName = "Push Prefs"
        update.socialPushDisabled = (1 << 2) | (1 << 4)
        (status, body) = try await post("social/profile/update", token: token, message: update)
        XCTAssertEqual(status, 200)
        let updated = try Api_ProfileResponse(serializedBytes: body)
        XCTAssertEqual(updated.profile.socialPushDisabled, (1 << 2) | (1 << 4))

        (status, body) = try await post("social/profile/get", token: token, message: Api_ProfileGetRequest())
        XCTAssertEqual(status, 200)
        let fetched = try Api_ProfileResponse(serializedBytes: body)
        XCTAssertEqual(fetched.profile.socialPushDisabled, (1 << 2) | (1 << 4), "the mask persists")
    }

    /// Slice-9 wire contract: search + discoverability opt-out, suggestions
    /// with count-only copy, and the salted contacts match (email matched,
    /// phone hash wire-ready).
    func testFindPeopleLoop() async throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let emailB = "ios-find-b-\(suffix)@e2e.test"
        let (tokenA, _) = try await register(email: "ios-find-a-\(suffix)@e2e.test")
        let (tokenB, _) = try await register(email: emailB)
        let (tokenC, _) = try await register(email: "ios-find-c-\(suffix)@e2e.test")

        let handleB = "ios_fnd_b_\(suffix)"
        let handleC = "ios_fnd_c_\(suffix)"
        for (token, handle, name) in [(tokenA, "ios_fnd_a_\(suffix)", "Finder A"),
                                      (tokenB, handleB, "Findable B"), (tokenC, handleC, "Suggested C")] {
            var join = Api_JoinRequest()
            join.handle = handle
            join.acceptedTermsVersion = 1
            join.displayName = name
            let (status, _) = try await post("social/join", token: token, message: join)
            XCTAssertEqual(status, 200)
        }

        // Slice 15: the curators directory answers with the wire contract
        // (entries need handles; the list may be empty on a fresh backend —
        // designation is an operator act, not seedable from here).
        let (curatorsStatus, curatorsBody) = try await post("social/curators", token: tokenA, message: Api_CuratorsRequest())
        XCTAssertEqual(curatorsStatus, 200)
        let curators = try Api_CuratorsResponse(serializedBytes: curatorsBody)
        for entry in curators.curators {
            XCTAssertFalse(entry.handle.isEmpty)
        }

        // Prefix search finds B; the opt-out removes them.
        var search = Api_SocialSearchRequest()
        search.query = String(handleB.prefix(12))
        var (status, body) = try await post("social/search", token: tokenA, message: search)
        XCTAssertEqual(status, 200)
        var found = try Api_SocialSearchResponse(serializedBytes: body)
        XCTAssertEqual(found.profiles.count, 1)
        XCTAssertEqual(found.profiles.first?.handle, handleB)

        var hide = Api_ProfileUpdateRequest()
        hide.displayName = "Findable B"
        hide.hideFromDiscovery = true
        (status, _) = try await post("social/profile/update", token: tokenB, message: hide)
        XCTAssertEqual(status, 200)
        (status, body) = try await post("social/search", token: tokenA, message: search)
        found = try Api_SocialSearchResponse(serializedBytes: body)
        XCTAssertTrue(found.profiles.isEmpty, "hidden profiles leave search")

        // A→C→B would normally suggest B to A. Keep B hidden while
        // proving both suggestions and contact matching honor the same opt-out.
        var follow = Api_FollowRequest()
        follow.handle = handleC
        (status, _) = try await post("social/follow", token: tokenA, message: follow)
        XCTAssertEqual(status, 200)
        follow.handle = handleB
        (status, _) = try await post("social/follow", token: tokenC, message: follow)
        XCTAssertEqual(status, 200)

        (status, body) = try await post("social/suggestions", token: tokenA, message: Api_SocialSuggestionsRequest())
        XCTAssertEqual(status, 200)
        var suggestions = try Api_SocialSuggestionsResponse(serializedBytes: body)
        XCTAssertFalse(suggestions.profiles.contains { $0.handle == handleB }, "hidden profiles leave suggestions")

        (status, body) = try await post("social/contacts/salt", token: tokenA, message: Api_SocialSuggestionsRequest())
        XCTAssertEqual(status, 200)
        let salt = try Api_ContactsSaltResponse(serializedBytes: body).salt
        XCTAssertFalse(salt.isEmpty)

        var emailHash = Api_ContactHash()
        emailHash.kind = .email
        emailHash.hash = FindPeopleHashHelper.saltedHash(salt: salt, value: emailB.lowercased())
        var phoneHash = Api_ContactHash()
        phoneHash.kind = .phone
        phoneHash.hash = FindPeopleHashHelper.saltedHash(salt: salt, value: "+15550001111")
        var match = Api_ContactsMatchRequest()
        match.hashes = [emailHash, phoneHash]
        (status, body) = try await post("social/contacts/match", token: tokenA, message: match)
        XCTAssertEqual(status, 200)
        var matched = try Api_ContactsMatchResponse(serializedBytes: body)
        XCTAssertFalse(matched.profiles.contains { $0.handle == handleB }, "hidden profiles leave contact matches")

        hide.hideFromDiscovery = false
        (status, _) = try await post("social/profile/update", token: tokenB, message: hide)
        XCTAssertEqual(status, 200)

        (status, body) = try await post("social/search", token: tokenA, message: search)
        found = try Api_SocialSearchResponse(serializedBytes: body)
        XCTAssertEqual(found.profiles.first?.handle, handleB, "unhidden profile returns to search")

        (status, body) = try await post("social/suggestions", token: tokenA, message: Api_SocialSuggestionsRequest())
        XCTAssertEqual(status, 200)
        suggestions = try Api_SocialSuggestionsResponse(serializedBytes: body)
        XCTAssertEqual(suggestions.profiles.first?.handle, handleB)
        XCTAssertEqual(suggestions.profiles.first?.mutualCount, 1)

        (status, body) = try await post("social/contacts/match", token: tokenA, message: match)
        XCTAssertEqual(status, 200)
        matched = try Api_ContactsMatchResponse(serializedBytes: body)
        XCTAssertEqual(matched.profiles.count, 1, "email matches; the phone hash is wire-ready but unmatched")
        XCTAssertEqual(matched.profiles.first?.handle, handleB)
    }

    /// Slice-10 wire contract: trending under history visibility and podcast
    /// proof under followed-shows visibility (named only when visible).
    func testDiscoveryLoop() async throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let (tokenA, _) = try await register(email: "ios-disc-a-\(suffix)@e2e.test")
        let (tokenB, _) = try await register(email: "ios-disc-b-\(suffix)@e2e.test")

        let handleB = "ios_dsc_b_\(suffix)"
        for (token, handle, name) in [(tokenA, "ios_dsc_a_\(suffix)", "Discoverer"), (tokenB, handleB, "Listener")] {
            var join = Api_JoinRequest()
            join.handle = handle
            join.acceptedTermsVersion = 1
            join.displayName = name
            let (status, _) = try await post("social/join", token: token, message: join)
            XCTAssertEqual(status, 200)
        }
        var follow = Api_FollowRequest()
        follow.handle = handleB
        var (status, body) = try await post("social/follow", token: tokenA, message: follow)
        XCTAssertEqual(status, 200)

        // B finishes an episode with followers-only history; the show trends
        // for A (an active follower) and counts one listener.
        let podcastUuid = "abcd\(String(suffix.prefix(4)))-9999-8888-7777-666655554444"
        var sync = Api_SyncUpdateRequest()
        sync.deviceUtcTimeMs = Int64(Date().timeIntervalSince1970 * 1000)
        var episode = Api_SyncUserEpisode()
        episode.uuid = "dcba\(String(suffix.prefix(4)))-9999-8888-7777-666655554444"
        episode.podcastUuid = podcastUuid
        episode.duration = Google_Protobuf_Int64Value(600)
        episode.durationModified = Google_Protobuf_Int64Value(sync.deviceUtcTimeMs)
        episode.playedUpTo = Google_Protobuf_Int64Value(600)
        episode.playedUpToModified = Google_Protobuf_Int64Value(sync.deviceUtcTimeMs)
        episode.playingStatus = Google_Protobuf_Int32Value(3)
        episode.playingStatusModified = Google_Protobuf_Int64Value(sync.deviceUtcTimeMs)
        var record = Api_Record()
        record.episode = episode
        sync.records.append(record)
        (status, _) = try await post("user/sync/update", token: tokenB, message: sync)
        XCTAssertEqual(status, 200)

        var update = Api_ProfileUpdateRequest()
        update.displayName = "Listener"
        update.historyVisibility = .followersOnly
        (status, _) = try await post("social/profile/update", token: tokenB, message: update)
        XCTAssertEqual(status, 200)

        (status, body) = try await post("social/trending", token: tokenA, message: Api_SocialTrendingRequest())
        XCTAssertEqual(status, 200)
        let trending = try Api_SocialTrendingResponse(serializedBytes: body)
        XCTAssertEqual(trending.podcasts.count, 1)
        XCTAssertEqual(trending.podcasts.first?.podcastUuid, podcastUuid)
        XCTAssertEqual(trending.podcasts.first?.listenerCount, 1)

        // Proof: B subscribes with followed-shows private → count only; the
        // public flip names them.
        var podcastSync = Api_SyncUpdateRequest()
        podcastSync.deviceUtcTimeMs = sync.deviceUtcTimeMs + 1
        var podcast = Api_SyncUserPodcast()
        podcast.uuid = podcastUuid
        podcast.subscribed = Google_Protobuf_BoolValue(true)
        var podcastRecord = Api_Record()
        podcastRecord.podcast = podcast
        podcastSync.records.append(podcastRecord)
        (status, _) = try await post("user/sync/update", token: tokenB, message: podcastSync)
        XCTAssertEqual(status, 200)

        var proofRequest = Api_PodcastProofRequest()
        proofRequest.podcastUuid = podcastUuid
        (status, body) = try await post("social/podcast/proof", token: tokenA, message: proofRequest)
        XCTAssertEqual(status, 200)
        var proof = try Api_PodcastProofResponse(serializedBytes: body)
        // QA-corrected contract: a private followed-shows list contributes
        // NOTHING to proof — not even the count.
        XCTAssertEqual(proof.totalCount, 0)
        XCTAssertTrue(proof.visibleHandles.isEmpty)

        update.historyVisibility = .followersOnly
        update.followedShowsVisibility = .public
        (status, _) = try await post("social/profile/update", token: tokenB, message: update)
        XCTAssertEqual(status, 200)
        (status, body) = try await post("social/podcast/proof", token: tokenA, message: proofRequest)
        XCTAssertEqual(status, 200)
        proof = try Api_PodcastProofResponse(serializedBytes: body)
        XCTAssertEqual(proof.visibleHandles, [handleB])
        XCTAssertEqual(proof.totalCount, 1)
    }

    // MARK: - Wire helpers (no app global state)

    private func register(email: String) async throws -> (token: String, uuid: String) {
        var request = Api_RegisterRequest()
        request.email = email
        request.password = "ios-e2e-password" // nosemgrep: hardcoded_secret - throwaway fixture credential for disposable accounts on the local Docker backend
        request.scope = "mobile"
        let (status, body) = try await post("user/register", token: nil, message: request)
        XCTAssertEqual(status, 200, "register must succeed against the local backend")
        let response = try Api_RegisterResponse(serializedBytes: body)
        XCTAssertFalse(response.token.isEmpty)
        return (response.token, response.uuid)
    }

    private func post(_ path: String, token: String?, message: any SwiftProtobuf.Message) async throws -> (Int, Data) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = try message.serializedData()
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.addValue("application/octet-stream", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (status, data)
    }
}


/// Mirrors the app's contact-identifier hashing (FindPeopleViewModel).
enum FindPeopleHashHelper {
    static func saltedHash(salt: String, value: String) -> String {
        SHA256.hash(data: Data((salt + value).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
