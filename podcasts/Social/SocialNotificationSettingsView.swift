import SwiftUI
import PocketCastsServer
import PocketCastsUtils

/// Per-type social push toggles (Slice 8, docs/Social.md). All six types are
/// ON by default; the disabled bitmask lives on the server-side profile so it
/// gates sends at the source and applies across devices. Reached from
/// Settings → Notifications and the social privacy screen.
struct SocialNotificationSettingsView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: SocialNotificationSettingsViewModel

    var body: some View {
        List {
            Section(footer: Text(L10n.socialNotificationsFooter).font(.footnote)) {
                toggleRow(L10n.socialNotificationsFollowRequests, type: .followRequest)
                toggleRow(L10n.socialNotificationsFollowApproved, type: .followApproved)
                toggleRow(L10n.socialNotificationsNewFollowers, type: .newFollower)
                toggleRow(L10n.socialNotificationsSharedItems, type: .sharedItem)
                toggleRow(L10n.socialNotificationsReplies, type: .commentReply)
                toggleRow(L10n.socialNotificationsListInvites, type: .listInvite)
                toggleRow(L10n.socialNotificationsGroupInvites, type: .groupInvite)
                toggleRow(L10n.socialNotificationsGroupPosts, type: .groupPost)
                toggleRow(L10n.socialNotificationsDigest, type: .digest)
            }
            if let error = viewModel.saveError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .support05, theme: theme))
                }
            }
        }
        .navigationTitle(L10n.socialNotificationsHeader)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggleRow(_ title: String, type: SocialPushType) -> some View {
        Toggle(title, isOn: Binding(
            get: { viewModel.isEnabled(type) },
            set: { enabled in viewModel.set(type, enabled: enabled) }
        ))
    }
}

@MainActor
final class SocialNotificationSettingsViewModel: ObservableObject {
    typealias UpdateProfile = (SocialProfile) async -> SocialProfile?

    @Published private(set) var disabledMask: Int64
    @Published private(set) var saveError: String?

    private var profile: SocialProfile?
    private var fixtureLoaded = false
    private var saveTask: Task<Void, Never>?
    private let updateProfile: UpdateProfile

    init(
        profile: SocialProfile? = SocialIdentityStore.cachedProfile,
        updateProfile: @escaping UpdateProfile = { await ApiServerHandler.shared.updateSocialProfile($0) }
    ) {
        self.profile = profile
        self.updateProfile = updateProfile
        disabledMask = profile?.socialPushDisabled ?? 0
    }

    /// Fixture initializer for snapshots/previews; saves then no-op.
    init(fixtureMask: Int64) {
        disabledMask = fixtureMask
        updateProfile = { _ in nil }
        fixtureLoaded = true
    }

    func isEnabled(_ type: SocialPushType) -> Bool {
        SocialPushType.isEnabled(type, in: disabledMask)
    }

    /// Optimistic flip; the profile update persists it server-side (where
    /// sends are gated). Reverts on failure.
    func set(_ type: SocialPushType, enabled: Bool) {
        disabledMask = SocialPushType.setEnabled(type, enabled: enabled, in: disabledMask)
        saveError = nil
        guard !fixtureLoaded, profile != nil else { return }

        Analytics.track(.socialPushPrefChanged)
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            await self?.persistPendingMask()
        }
    }

    func waitForPendingSave() async {
        await saveTask?.value
    }

    /// Serializes full-profile writes and coalesces rapid toggles. Cancelling an
    /// Operation-backed request cannot stop its HTTP write, so one writer is
    /// kept in flight and any newer desired mask is sent immediately after it.
    private func persistPendingMask() async {
        defer { saveTask = nil }
        guard var confirmedProfile = profile else { return }

        while true {
            guard !Task.isCancelled else { return }
            let requestedMask = disabledMask
            var updated = confirmedProfile
            updated.socialPushDisabled = requestedMask

            guard let saved = await updateProfile(updated) else {
                if disabledMask == requestedMask {
                    disabledMask = confirmedProfile.socialPushDisabled
                    saveError = L10n.socialPrivacySaveFailed
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
                continue
            }

            confirmedProfile = saved
            profile = saved
            guard disabledMask == requestedMask else { continue }
            disabledMask = saved.socialPushDisabled
            SocialIdentityStore.cachedProfile = saved
            return
        }
    }
}
