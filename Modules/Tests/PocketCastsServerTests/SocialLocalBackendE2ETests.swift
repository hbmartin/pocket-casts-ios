import XCTest
import SwiftProtobuf
@testable import PocketCastsServer

/// End-to-end proof of the Swift↔Go social wire contract against the REAL
/// local backend (docs/Social.md "backend live before ship"). Runs only when
/// `POCKET_CASTS_SERVER_BASE_URL` is set (the "Pocket Casts Local" scheme
/// points it at the Docker backend on 127.0.0.1:8000) — skipped everywhere
/// else. When the env var IS set, an unreachable backend is a failure: this
/// suite exists to catch contract drift, not to be skipped past.
///
/// Uses URLSession + the generated `Api_*` messages directly (no app global
/// state), registering throwaway accounts per run. Mirrors the backend's
/// `TestSocialIdentityLoop` e2e test.
final class SocialLocalBackendE2ETests: XCTestCase {
    private var baseURL: URL!

    override func setUpWithError() throws {
        guard let raw = ProcessInfo.processInfo.environment["POCKET_CASTS_SERVER_BASE_URL"],
              let url = URL(string: raw) else {
            throw XCTSkip("POCKET_CASTS_SERVER_BASE_URL not set — run under the 'Pocket Casts Local' scheme with the Docker backend up")
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
        let (tokenA, _) = try await register(email: "ios-send-a-\(suffix)@e2e.test")
        let (tokenB, _) = try await register(email: "ios-send-b-\(suffix)@e2e.test")

        for (token, handle, name) in [(tokenA, "ios_snd_a_\(suffix)", "Sender A"),
                                      (tokenB, "ios_snd_b_\(suffix)", "Recipient B")] {
            var join = Api_JoinRequest()
            join.handle = handle
            join.acceptedTermsVersion = 1
            join.displayName = name
            let (status, _) = try await post("social/join", token: token, message: join)
            XCTAssertEqual(status, 200)
        }

        var send = Api_SharedItemSendRequest()
        send.recipientHandle = "ios_snd_b_\(suffix)"
        send.episodeUuid = "ios-episode-\(suffix)"
        send.podcastUuid = "ios-podcast-\(suffix)"
        send.episodeTitle = "A Sent Episode"
        send.podcastTitle = "A Sent Podcast"
        send.note = "you'll love this bit"
        send.timestampSeconds = 615
        var (status, body) = try await post("social/share/send", token: tokenA, message: send)
        XCTAssertEqual(status, 200)
        XCTAssertTrue(try Api_SocialAck(serializedBytes: body).success)

        // B's inbox: one unread item, fully attributed.
        (status, body) = try await post("social/inbox", token: tokenB, message: Api_InboxRequest())
        XCTAssertEqual(status, 200)
        var inbox = try Api_InboxResponse(serializedBytes: body)
        XCTAssertEqual(inbox.items.count, 1)
        XCTAssertEqual(inbox.unread, 1)
        let item = inbox.items[0]
        XCTAssertEqual(item.senderHandle, "ios_snd_a_\(suffix)")
        XCTAssertEqual(item.note, "you'll love this bit")
        XCTAssertEqual(item.timestampSeconds, 615)
        XCTAssertFalse(item.read)

        // Mark read → unread drops.
        var markRead = Api_InboxMarkReadRequest()
        markRead.ids = [item.id]
        (status, _) = try await post("social/inbox/read", token: tokenB, message: markRead)
        XCTAssertEqual(status, 200)
        (status, body) = try await post("social/inbox", token: tokenB, message: Api_InboxRequest())
        inbox = try Api_InboxResponse(serializedBytes: body)
        XCTAssertEqual(inbox.unread, 0)
        XCTAssertTrue(inbox.items[0].read)

        // Unknown recipient: 404 (no leak).
        send.recipientHandle = "nobody_here_\(suffix)"
        (status, _) = try await post("social/share/send", token: tokenA, message: send)
        XCTAssertEqual(status, 404)

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

    // MARK: - Wire helpers (no app global state)

    private func register(email: String) async throws -> (token: String, uuid: String) {
        var request = Api_RegisterRequest()
        request.email = email
        request.password = "ios-e2e-password"
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
