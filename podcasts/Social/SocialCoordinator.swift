import SwiftUI
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import UIKit

/// Presentation glue for the social surfaces: the Join flow, the owner's
/// profile, and public profiles opened from Profile Links
/// (thcast://profile/<handle> or <backend>/u/<handle>, ADR-0008).
/// All entry points are gated by FeatureFlag.socialProfiles.
@MainActor
enum SocialCoordinator {
    enum RefreshWaitResult: Equatable, Sendable {
        case completed
        case timedOut
        case cancelled
    }

    /// Presents the one-time Join flow. On success, pushes the new profile.
    static func presentJoinFlow(from presenter: UIViewController, navigationController: UINavigationController?) {
        guard SyncManager.isUserLoggedIn() else {
            NavigationManager.sharedManager.navigateTo(NavigationManager.onboardingFlow,
                                                       data: ["flow": OnboardingFlow.Flow.loggedOut])
            return
        }

        let viewModel = SocialJoinViewModel { [weak presenter, weak navigationController] profile in
            presenter?.dismiss(animated: true) {
                if profile != nil, let navigationController {
                    pushOwnProfile(on: navigationController)
                }
            }
        }
        let hosting = ThemedHostingController(rootView: SocialJoinView(viewModel: viewModel))
        hosting.modalPresentationStyle = .formSheet
        presenter.present(hosting, animated: true)
    }

    /// Pushes the owner's profile (requires a joined account).
    static func pushOwnProfile(on navigationController: UINavigationController) {
        guard let profile = SocialIdentityStore.cachedProfile else { return }
        let viewModel = OwnSocialProfileViewModel(profile: profile)
        viewModel.onShare = { [weak navigationController] url in
            guard let presenter = navigationController?.topViewController else { return }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = presenter.view
            presenter.present(activity, animated: true)
        }
        let hosting = ThemedHostingController(rootView: OwnSocialProfileView(viewModel: viewModel))
        navigationController.pushViewController(hosting, animated: true)
    }

    /// Opens another user's profile from a Profile Link.
    static func openPublicProfile(handle: String) {
        guard FeatureFlag.socialProfiles.enabled, !handle.isEmpty else { return }
        let hosting = ThemedHostingController(rootView: PublicProfileView(viewModel: PublicProfileViewModel(handle: handle)))
        push(hosting)
    }

    /// Pushes the Inbox (social push landing for requests + shared items).
    static func openInbox() {
        guard FeatureFlag.socialProfiles.enabled else { return }
        push(ThemedHostingController(rootView: SocialInboxView(viewModel: SocialInboxViewModel())))
    }

    /// Pushes the find-people screen (Slice 9).
    static func openFindPeople() {
        guard FeatureFlag.socialProfiles.enabled else { return }
        push(ThemedHostingController(rootView: FindPeopleView(viewModel: FindPeopleViewModel())))
    }

    /// Pushes the curator directory (Find People hosts it today).
    static func openCurators() {
        // The directory lives atop Find People; one surface, two doors.
        openFindPeople()
    }

    static func openGroups() {
        guard FeatureFlag.socialProfiles.enabled else { return }
        push(ThemedHostingController(rootView: SocialGroupsView(viewModel: SocialGroupsViewModel())))
    }

    static func openGroup(id: Int64) {
        guard FeatureFlag.socialProfiles.enabled else { return }
        push(ThemedHostingController(rootView: GroupDetailView(viewModel: GroupDetailViewModel(groupId: id))))
    }

    /// Pushes the Shared Lists hub (social push landing for list invites).
    static func openSharedLists() {
        guard FeatureFlag.socialProfiles.enabled else { return }
        push(ThemedHostingController(rootView: SharedListsView(viewModel: SharedListsViewModel())))
    }

    /// Presents an episode's comment tree, optionally focused on one subtree
    /// (social push landing for replies — same surface as a Moment pin tap).
    static func openComments(episodeUuid: String, podcastUuid: String, focusCommentId: Int64?) async {
        guard FeatureFlag.socialProfiles.enabled, !episodeUuid.isEmpty else { return }
        let viewModel = await commentsViewModel(
            episodeUuid: episodeUuid,
            podcastUuid: podcastUuid,
            focusCommentId: focusCommentId,
            refreshIfNeeded: refreshPodcasts
        )
        push(ThemedHostingController(rootView: EpisodeCommentsView(viewModel: viewModel)))
    }

    static func commentsViewModel(
        episodeUuid: String,
        podcastUuid: String,
        focusCommentId: Int64?,
        refreshIfNeeded: () async -> Void
    ) async -> EpisodeCommentsViewModel {
        var episode = DataManager.sharedManager.findEpisode(uuid: episodeUuid)
        var resolvedPodcastUuid = episode?.parentIdentifier() ?? podcastUuid
        var podcast = resolvedPodcastUuid.isEmpty ? nil : DataManager.sharedManager.findPodcast(uuid: resolvedPodcastUuid)
        if episode == nil || (!resolvedPodcastUuid.isEmpty && podcast == nil) {
            await refreshIfNeeded()
            episode = DataManager.sharedManager.findEpisode(uuid: episodeUuid)
            resolvedPodcastUuid = episode?.parentIdentifier() ?? podcastUuid
            podcast = resolvedPodcastUuid.isEmpty ? nil : DataManager.sharedManager.findPodcast(uuid: resolvedPodcastUuid)
        }

        let duration = episode?.duration ?? 0
        let canSeed = duration > 0 && (episode?.playedUpTo ?? 0) >= duration * 0.25
        return EpisodeCommentsViewModel(
            episodeUuid: episodeUuid,
            podcastUuid: resolvedPodcastUuid,
            episodeTitle: episode?.displayableTitle() ?? "",
            podcastTitle: podcast?.title ?? "",
            canSeed: canSeed,
            focusCommentId: focusCommentId
        )
    }

    private static func refreshPodcasts() async {
        let result = await waitForRefreshCallback(timeout: .seconds(30)) { completion in
            RefreshManager.shared.refreshPodcasts { _ in completion() }
        }
        if result == .timedOut {
            FileLog.shared.addMessage("SocialCoordinator: podcast refresh timed out while opening comments; continuing with available metadata")
        }
    }

    /// Waits for a callback without allowing a missing callback to strand the task.
    /// The stream is single-consumer and the task group takes the first completion,
    /// timeout, or cancellation result.
    static func waitForRefreshCallback(
        timeout: Duration,
        start: (@escaping @Sendable () -> Void) -> Void
    ) async -> RefreshWaitResult {
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        start {
            pair.continuation.yield()
            pair.continuation.finish()
        }

        return await withTaskGroup(of: RefreshWaitResult.self) { group in
            group.addTask {
                for await _ in pair.stream {
                    return .completed
                }
                return .cancelled
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return .timedOut
                } catch {
                    return .cancelled
                }
            }
            let first = await group.next() ?? .cancelled
            group.cancelAll()
            return first
        }
    }

    private static func push(_ hosting: UIViewController) {
        if let navigationController = SceneHelper.rootViewController()?.presentedNavigationController
            ?? (SceneHelper.rootViewController() as? UINavigationController) {
            navigationController.pushViewController(hosting, animated: true)
        } else {
            SceneHelper.rootViewController()?.present(UINavigationController(rootViewController: hosting), animated: true)
        }
    }

    /// Pushes a shared list (Slice 7) from feed rows and profile sections.
    static func openSharedList(id: Int64) {
        guard FeatureFlag.socialProfiles.enabled else { return }
        let hosting = ThemedHostingController(rootView: SharedListDetailView(viewModel: SharedListDetailViewModel(listId: id)))
        push(hosting)
    }

    /// Recognizes a Profile Link path (`/u/<handle>`) or a thcast profile host
    /// (`thcast://profile/<handle>`) and returns the handle, else nil.
    static func profileHandle(from url: URL) -> String? {
        if url.scheme?.lowercased() == "thcast", url.host?.lowercased() == "profile" {
            let handle = url.pathComponents.dropFirst().first ?? ""
            return handle.isEmpty ? nil : handle.lowercased()
        }
        let components = url.pathComponents
        if components.count >= 3, components[1] == "u" {
            return components[2].lowercased()
        }
        return nil
    }
}

private extension UIViewController {
    var presentedNavigationController: UINavigationController? {
        var top: UIViewController = self
        while let presented = top.presentedViewController { top = presented }
        return (top as? UINavigationController)
            ?? (top as? UITabBarController)?.selectedViewController as? UINavigationController
            ?? top.navigationController
    }
}
