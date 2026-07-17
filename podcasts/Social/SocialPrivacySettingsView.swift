import SwiftUI
import PocketCastsServer
import PocketCastsUtils

/// Per-field profile visibility (ADR-0006): with the Phase-2 graph live, every
/// field offers the full three tiers — Private / Followers / Public — and the
/// display name stays locked public. Also hosts the "Approve My Followers"
/// toggle (hybrid follow consent, Slice 5) with honest copy: without it, any
/// follower can see Followers-tier fields. Doubles as the post-join privacy
/// nudge (decision 6) via `isNudge`. Distinct from the analytics
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
                fieldRow(L10n.socialPrivacyBio, selection: $viewModel.bioVisibility)
            }

            Section(header: Text(L10n.socialPrivacyListeningHeader),
                    footer: Text(L10n.socialPrivacyFooter)
                        .font(.footnote)) {
                fieldRow(L10n.socialPrivacyFollowedShows, selection: $viewModel.followedShowsVisibility)
                fieldRow(L10n.socialPrivacyTopPodcasts, selection: $viewModel.topPodcastsVisibility)
                fieldRow(L10n.socialPrivacyStats, selection: $viewModel.statsVisibility)
                fieldRow(L10n.socialPrivacyHistory, selection: $viewModel.historyVisibility)
            }

            Section(footer: Text(L10n.socialPrivacyApproveFollowersFooter)
                .font(.footnote)) {
                Toggle(L10n.socialPrivacyApproveFollowers, isOn: $viewModel.requireFollowApproval)
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
            // doesn't silently discard changes.
            if !isNudge, viewModel.hasChanges {
                Task { await viewModel.save() }
            }
        }
    }

    private func fieldRow(_ title: String, selection: Binding<SocialVisibility>) -> some View {
        Picker(title, selection: selection) {
            ForEach(SocialVisibility.allCases, id: \.self) { tier in
                Text(tier.localizedName).tag(tier)
            }
        }
        .pickerStyle(.menu)
    }
}

extension SocialVisibility {
    var localizedName: String {
        switch self {
        case .private: return L10n.socialPrivacyPrivate
        case .followersOnly: return L10n.socialPrivacyFollowers
        case .public: return L10n.socialPrivacyPublic
        }
    }
}

@MainActor
final class SocialPrivacySettingsViewModel: ObservableObject {
    @Published var bioVisibility: SocialVisibility
    @Published var followedShowsVisibility: SocialVisibility
    @Published var topPodcastsVisibility: SocialVisibility
    @Published var statsVisibility: SocialVisibility
    @Published var historyVisibility: SocialVisibility
    @Published var requireFollowApproval: Bool
    @Published private(set) var isSaving = false
    @Published private(set) var saveError: String?

    private var profile: SocialProfile?

    init(profile: SocialProfile? = SocialIdentityStore.cachedProfile) {
        self.profile = profile
        bioVisibility = profile?.bioVisibility ?? .private
        followedShowsVisibility = profile?.followedShowsVisibility ?? .private
        topPodcastsVisibility = profile?.topPodcastsVisibility ?? .private
        statsVisibility = profile?.statsVisibility ?? .private
        historyVisibility = profile?.historyVisibility ?? .private
        requireFollowApproval = profile?.requireFollowApproval ?? false
    }

    var hasChanges: Bool {
        guard let profile else { return false }
        return bioVisibility != profile.bioVisibility
            || followedShowsVisibility != profile.followedShowsVisibility
            || topPodcastsVisibility != profile.topPodcastsVisibility
            || statsVisibility != profile.statsVisibility
            || historyVisibility != profile.historyVisibility
            || requireFollowApproval != profile.requireFollowApproval
    }

    @discardableResult
    func save() async -> Bool {
        guard var updated = profile else { return true }
        updated.bioVisibility = bioVisibility
        updated.followedShowsVisibility = followedShowsVisibility
        updated.topPodcastsVisibility = topPodcastsVisibility
        updated.statsVisibility = statsVisibility
        updated.historyVisibility = historyVisibility
        updated.requireFollowApproval = requireFollowApproval

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
