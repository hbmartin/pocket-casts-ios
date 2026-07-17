import SwiftUI
import PocketCastsServer
import PocketCastsUtils

/// Per-field profile visibility (ADR-0006): public/private toggles in Phase 1
/// (`followers-only` unlocks with the Phase-2 graph); every field defaults
/// private and the display name is locked public. Doubles as the post-join
/// privacy nudge (decision 6) via `isNudge`. Distinct from the analytics
/// `PrivacySettingsViewController`.
struct SocialPrivacySettingsView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: SocialPrivacySettingsViewModel
    var isNudge = false
    var onDone: (() -> Void)?

    var body: some View {
        List {
            if isNudge {
                Section {
                    Text(L10n.socialPrivacyNudgeHeader)
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
            }

            Section(header: Text(L10n.socialPrivacyIdentityHeader)) {
                HStack {
                    Text(L10n.socialPrivacyDisplayName)
                    Spacer()
                    Text(L10n.socialPrivacyAlwaysPublic)
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
                fieldRow(L10n.socialPrivacyBio, binding: $viewModel.bioPublic)
            }

            Section(header: Text(L10n.socialPrivacyListeningHeader),
                    footer: Text(L10n.socialPrivacyFooter)
                        .font(.footnote)) {
                fieldRow(L10n.socialPrivacyFollowedShows, binding: $viewModel.followedShowsPublic)
                fieldRow(L10n.socialPrivacyTopPodcasts, binding: $viewModel.topPodcastsPublic)
                fieldRow(L10n.socialPrivacyStats, binding: $viewModel.statsPublic)
                fieldRow(L10n.socialPrivacyHistory, binding: $viewModel.historyPublic)
            }

            if let error = viewModel.saveError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(AppTheme.color(for: .support05, theme: theme))
                }
            }
        }
        .navigationTitle(L10n.socialPrivacyTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    Button(isNudge ? L10n.done : L10n.socialSave) {
                        Task {
                            if await viewModel.save() {
                                onDone?()
                            }
                        }
                    }
                }
            }
        }
        .onDisappear {
            // Non-nudge presentations save on exit too, so a back-swipe
            // doesn't silently discard toggles.
            if !isNudge, viewModel.hasChanges {
                Task { await viewModel.save() }
            }
        }
    }

    private func fieldRow(_ title: String, binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(binding.wrappedValue ? L10n.socialPrivacyPublic : L10n.socialPrivacyPrivate)
                    .font(.footnote)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
        }
    }
}

@MainActor
final class SocialPrivacySettingsViewModel: ObservableObject {
    @Published var bioPublic: Bool
    @Published var followedShowsPublic: Bool
    @Published var topPodcastsPublic: Bool
    @Published var statsPublic: Bool
    @Published var historyPublic: Bool
    @Published private(set) var isSaving = false
    @Published private(set) var saveError: String?

    private var profile: SocialProfile?

    init(profile: SocialProfile? = SocialIdentityStore.cachedProfile) {
        self.profile = profile
        bioPublic = profile?.bioVisibility == .public
        followedShowsPublic = profile?.followedShowsVisibility == .public
        topPodcastsPublic = profile?.topPodcastsVisibility == .public
        statsPublic = profile?.statsVisibility == .public
        historyPublic = profile?.historyVisibility == .public
    }

    var hasChanges: Bool {
        guard let profile else { return false }
        return bioPublic != (profile.bioVisibility == .public)
            || followedShowsPublic != (profile.followedShowsVisibility == .public)
            || topPodcastsPublic != (profile.topPodcastsVisibility == .public)
            || statsPublic != (profile.statsVisibility == .public)
            || historyPublic != (profile.historyVisibility == .public)
    }

    /// Persists the toggles; only public/private are writable in Phase 1.
    @discardableResult
    func save() async -> Bool {
        guard var updated = profile else { return true }
        updated.bioVisibility = bioPublic ? .public : .private
        updated.followedShowsVisibility = followedShowsPublic ? .public : .private
        updated.topPodcastsVisibility = topPodcastsPublic ? .public : .private
        updated.statsVisibility = statsPublic ? .public : .private
        updated.historyVisibility = historyPublic ? .public : .private

        isSaving = true
        saveError = nil
        let saved = await ApiServerHandler.shared.updateSocialProfile(updated)
        isSaving = false
        guard let saved else {
            saveError = L10n.socialPrivacySaveFailed
            return false
        }
        SocialIdentityStore.cachedProfile = saved
        profile = saved
        return true
    }
}
