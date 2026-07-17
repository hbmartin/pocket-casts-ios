import SwiftUI
import PocketCastsServer
import PocketCastsUtils

/// The owner's view of their Social Profile: identity header, edit entry,
/// Profile Link sharing, privacy entry, and the local-data sections — the
/// listening heatmap renders here only (no per-day series exists server-side;
/// see ADR-0006/0008 and docs/SocialRoadmap.md).
struct OwnSocialProfileView: View {
    @EnvironmentObject var theme: Theme
    @StateObject var viewModel: OwnSocialProfileViewModel
    @StateObject private var heatmapModel = ListeningHeatmapViewModel()
    @State private var showingEdit = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.profile.displayName)
                        .font(.title2.bold())
                    Text("@" + viewModel.profile.handle)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                    if !viewModel.profile.bio.isEmpty {
                        Text(viewModel.profile.bio)
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)

                Button(L10n.socialProfileEdit) { showingEdit = true }
            }

            Section {
                Button {
                    viewModel.shareLink()
                } label: {
                    Label(L10n.socialProfileShareLink, systemImage: "square.and.arrow.up")
                }
                NavigationLink(destination: SocialPrivacySettingsView(viewModel: SocialPrivacySettingsViewModel())
                    .environmentObject(theme)) {
                    Label(L10n.socialPrivacyTitle, systemImage: "lock")
                }
            }

            Section(header: Text(L10n.socialSectionHeatmap),
                    footer: Text(L10n.socialHeatmapLocalNote)
                        .font(.footnote)) {
                ListeningHeatmapView(viewModel: heatmapModel)
                    .padding(.vertical, 4)
            }
        }
        .navigationTitle(L10n.socialProfileTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEdit) {
            SocialProfileEditView(viewModel: viewModel)
                .environmentObject(theme)
        }
        .task { await viewModel.refresh() }
    }
}

/// Edit sheet for the mutable identity fields (display name + bio). The
/// handle is immutable and deliberately absent (ADR-0005); the server re-runs
/// the text pre-filter on save (ADR-0007).
struct SocialProfileEditView: View {
    @EnvironmentObject var theme: Theme
    @ObservedObject var viewModel: OwnSocialProfileViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(L10n.socialPrivacyDisplayName)) {
                    TextField(L10n.socialDisplayNamePlaceholder, text: $viewModel.editedDisplayName)
                }
                Section(header: Text(L10n.socialPrivacyBio)) {
                    TextEditor(text: $viewModel.editedBio)
                        .frame(minHeight: 90)
                }
                if let error = viewModel.saveError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(AppTheme.color(for: .support05, theme: theme))
                    }
                }
            }
            .navigationTitle(L10n.socialProfileEdit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button(L10n.socialSave) {
                            Task {
                                if await viewModel.saveEdits() { dismiss() }
                            }
                        }
                        .disabled(viewModel.editedDisplayName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .onAppear { viewModel.beginEditing() }
    }
}

@MainActor
final class OwnSocialProfileViewModel: ObservableObject {
    @Published private(set) var profile: SocialProfile
    @Published var editedDisplayName = ""
    @Published var editedBio = ""
    @Published private(set) var isSaving = false
    @Published private(set) var saveError: String?

    /// Presents the system share sheet; injected so the view stays testable.
    var onShare: ((URL) -> Void)?

    init(profile: SocialProfile, onShare: ((URL) -> Void)? = nil) {
        self.profile = profile
        self.onShare = onShare
    }

    /// The canonical web Profile Link (ADR-0008): the backend's base + /u/<handle>.
    var profileLink: URL? {
        URL(string: "\(ServerConstants.Urls.api())u/\(profile.handle)")
    }

    func shareLink() {
        guard let profileLink else { return }
        Analytics.track(.socialProfileLinkShared)
        onShare?(profileLink)
    }

    func refresh() async {
        if let fresh = await ApiServerHandler.shared.getSocialProfile() {
            profile = fresh
            SocialIdentityStore.cachedProfile = fresh
        }
    }

    func beginEditing() {
        editedDisplayName = profile.displayName
        editedBio = profile.bio
        saveError = nil
    }

    func saveEdits() async -> Bool {
        var updated = profile
        updated.displayName = editedDisplayName.trimmingCharacters(in: .whitespaces)
        updated.bio = editedBio

        isSaving = true
        saveError = nil
        let saved = await ApiServerHandler.shared.updateSocialProfile(updated)
        isSaving = false
        guard let saved else {
            saveError = L10n.socialEditRejected
            return false
        }
        profile = saved
        SocialIdentityStore.cachedProfile = saved
        return true
    }
}
