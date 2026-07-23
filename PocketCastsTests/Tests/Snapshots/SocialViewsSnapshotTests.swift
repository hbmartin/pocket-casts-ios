import PocketCastsServer
import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshot coverage for the social UI slice (docs/Social.md): the
/// one-time announcement, the Join flow steps, the privacy screen, the profile
/// edit sheet, and the public profile states. Fixtures are fully deterministic:
/// no network (PublicProfileViewModel fixtures skip load), no relative dates
/// (playedAt left nil), and no heatmap (OwnSocialProfileView is excluded —
/// its listening grid is anchored to the current date).
@MainActor
final class SocialViewsSnapshotTests: XCTestCase {
    private static let phone = SwiftUISnapshotLayout.fixed(width: 390, height: 700)

    private static func fixtureProfile() -> SocialProfile {
        var configuration = SocialProfile.Configuration(
            userId: "00000000-0000-0000-0000-000000000001",
            handle: "snapshot_person",
            displayName: "Snapshot Person"
        )
        configuration.bio = "A deterministic bio for image tests."
        configuration.createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        configuration.termsVersion = 1
        configuration.bioVisibility = .public
        configuration.statsVisibility = .public
        return SocialProfile(configuration: configuration)
    }

    func testAnnouncement() {
        assertAppThemedSnapshots(
            of: SocialAnnouncementView(onJoin: {}, onDismiss: {}),
            layout: .fixed(width: 390, height: 420)
        )
    }

    func testJoinTermsStep() {
        let viewModel = SocialJoinViewModel { _ in }
        assertAppThemedSnapshots(
            of: SocialJoinView(viewModel: viewModel),
            layout: Self.phone
        )
    }

    func testJoinHandleStepAvailable() {
        let viewModel = SocialJoinViewModel { _ in }
        viewModel.step = .handle
        viewModel.handleInput = "snapshot_person"
        viewModel.availabilityDisplay = .available(normalized: "snapshot_person")
        assertAppThemedSnapshots(
            of: SocialJoinView(viewModel: viewModel),
            layout: Self.phone
        )
    }

    func testJoinHandleStepTaken() {
        let viewModel = SocialJoinViewModel { _ in }
        viewModel.step = .handle
        viewModel.handleInput = "taken_name"
        viewModel.availabilityDisplay = .unavailable(reason: L10n.socialHandleTaken)
        assertAppThemedSnapshots(
            of: SocialJoinView(viewModel: viewModel),
            layout: Self.phone
        )
    }

    func testJoinConfirmStep() {
        let viewModel = SocialJoinViewModel { _ in }
        viewModel.step = .confirm
        viewModel.claimedHandle = "snapshot_person"
        viewModel.displayNameInput = "Snapshot Person"
        assertAppThemedSnapshots(
            of: SocialJoinView(viewModel: viewModel),
            layout: Self.phone
        )
    }

    func testPrivacyScreen() {
        assertAppThemedSnapshots(
            of: NavigationView {
                SocialPrivacySettingsView(viewModel: SocialPrivacySettingsViewModel(profile: Self.fixtureProfile()))
            }.navigationViewStyle(.stack),
            layout: Self.phone
        )
    }

    func testPrivacyScreenAsNudge() {
        assertAppThemedSnapshots(
            of: NavigationView {
                SocialPrivacySettingsView(viewModel: SocialPrivacySettingsViewModel(profile: Self.fixtureProfile()),
                                          isNudge: true)
            }.navigationViewStyle(.stack),
            layout: Self.phone
        )
    }

    func testProfileEditSheet() {
        let viewModel = OwnSocialProfileViewModel(profile: Self.fixtureProfile())
        viewModel.beginEditing()
        assertAppThemedSnapshots(
            of: SocialProfileEditView(viewModel: viewModel),
            layout: Self.phone
        )
    }

    func testPublicProfileLoaded() {
        // Pin the joined state: the follow button renders only for joined
        // viewers, and the simulator's UserDefaults may carry a profile from
        // manual QA. Deterministically render as a joined non-owner viewer.
        let previousProfile = SocialIdentityStore.cachedProfile
        SocialIdentityStore.cachedProfile = Self.fixtureProfile()
        defer { SocialIdentityStore.cachedProfile = previousProfile }

        let profile = SocialPublicProfile(
            userId: "00000000-0000-0000-0000-000000000002",
            handle: "snapshot_person",
            displayName: "Snapshot Person",
            bio: "A deterministic bio for image tests.",
            avatarURL: "",
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            hasStats: true,
            followedShows: [
                SocialProfilePodcast(uuid: "aaaaaaaa-0000-0000-0000-000000000001", title: "Followed Show", author: "An Author"),
            ],
            topPodcasts: [
                SocialProfilePodcast(uuid: "aaaaaaaa-0000-0000-0000-000000000002", title: "Top Podcast", author: "An Author", playedSeconds: 7200),
            ],
            stats: SocialProfileStats(timeListenedSeconds: 36_000, listeningSince: Date(timeIntervalSince1970: 1_700_000_000)),
            recentlyPlayed: [
                SocialProfileEpisode(uuid: "aaaaaaaa-0000-0000-0000-000000000003",
                                     podcastUuid: "aaaaaaaa-0000-0000-0000-000000000002",
                                     title: "A Recent Episode", playedAt: nil),
            ]
        )
        assertAppThemedSnapshots(
            of: NavigationView {
                PublicProfileView(viewModel: PublicProfileViewModel(handle: "snapshot_person", fixture: .loaded(profile)))
            }.navigationViewStyle(.stack),
            layout: Self.phone
        )
    }

    func testPublicProfileNotFound() {
        assertAppThemedSnapshots(
            of: NavigationView {
                PublicProfileView(viewModel: PublicProfileViewModel(handle: "nobody_here", fixture: .notFound))
            }.navigationViewStyle(.stack),
            layout: Self.phone
        )
    }
}
