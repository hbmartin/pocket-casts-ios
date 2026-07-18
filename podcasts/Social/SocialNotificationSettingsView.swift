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
            set: { enabled in Task { await viewModel.set(type, enabled: enabled) } }
        ))
    }
}

@MainActor
final class SocialNotificationSettingsViewModel: ObservableObject {
    @Published private(set) var disabledMask: Int64
    @Published private(set) var saveError: String?

    private var profile: SocialProfile?
    private var fixtureLoaded = false

    init(profile: SocialProfile? = SocialIdentityStore.cachedProfile) {
        self.profile = profile
        disabledMask = profile?.socialPushDisabled ?? 0
    }

    /// Fixture initializer for snapshots/previews; saves then no-op.
    init(fixtureMask: Int64) {
        disabledMask = fixtureMask
        fixtureLoaded = true
    }

    func isEnabled(_ type: SocialPushType) -> Bool {
        SocialPushType.isEnabled(type, in: disabledMask)
    }

    /// Optimistic flip; the profile update persists it server-side (where
    /// sends are gated). Reverts on failure.
    func set(_ type: SocialPushType, enabled: Bool) async {
        let previous = disabledMask
        disabledMask = SocialPushType.setEnabled(type, enabled: enabled, in: disabledMask)
        saveError = nil
        guard !fixtureLoaded, var updated = profile else { return }

        Analytics.track(.socialPushPrefChanged)
        updated.socialPushDisabled = disabledMask
        guard let saved = await ApiServerHandler.shared.updateSocialProfile(updated) else {
            disabledMask = previous
            saveError = L10n.socialPrivacySaveFailed
            return
        }
        SocialIdentityStore.cachedProfile = saved
        profile = saved
    }
}
