import PhotosUI
import SwiftUI
import UIKit
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
                    if let avatarURL = URL(string: viewModel.profile.avatarURL), !viewModel.profile.avatarURL.isEmpty {
                        AsyncImage(url: avatarURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                        // Decorative: the display name right below already
                        // identifies the profile for VoiceOver.
                        .accessibilityHidden(true)
                    }
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

            // Own follower/following lists (the backend only serves the
            // caller's lists; other profiles show counts only — Slice 5).
            Section {
                NavigationLink(destination: FollowListView(viewModel: FollowListViewModel(kind: .followers))
                    .environmentObject(theme)) {
                    Label(L10n.socialFollowersTitle, systemImage: "person.2")
                }
                NavigationLink(destination: FollowListView(viewModel: FollowListViewModel(kind: .following))
                    .environmentObject(theme)) {
                    Label(L10n.socialFollowingTitle, systemImage: "person.2.wave.2")
                }
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
    /// Avatar upload exists only when the capability manifest reports it
    /// (docs/SocialAvatars.md). Fails closed: the section stays hidden until
    /// the manifest confirms support.
    @State private var avatarFeatureAvailable = false

    var body: some View {
        NavigationView {
            Form {
                if avatarFeatureAvailable {
                    Section(header: Text(L10n.settingsChangeAvatar)) {
                        PhotosPicker(selection: $viewModel.selectedAvatarItem, matching: .images) {
                            Label(L10n.settingsChangeAvatar, systemImage: "photo")
                        }
                        .disabled(viewModel.isAvatarUpdating)
                        if !viewModel.profile.avatarURL.isEmpty {
                            Button(role: .destructive) {
                                Task { await viewModel.removeAvatar() }
                            } label: {
                                Label(L10n.remove, systemImage: "trash")
                            }
                            .disabled(viewModel.isAvatarUpdating)
                        }
                        if viewModel.isAvatarUpdating {
                            ProgressView()
                        }
                    }
                }
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
        .task {
            avatarFeatureAvailable = await ServerCapabilitiesClient.shared.load()?.features.avatar == true
        }
    }
}

@MainActor
final class OwnSocialProfileViewModel: ObservableObject {
    @Published private(set) var profile: SocialProfile
    @Published var editedDisplayName = ""
    @Published var editedBio = ""
    @Published private(set) var isSaving = false
    @Published private(set) var isAvatarUpdating = false
    @Published private(set) var saveError: String?
    @Published var selectedAvatarItem: PhotosPickerItem? {
        didSet { loadSelectedAvatar() }
    }

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

    func removeAvatar() async {
        guard !isAvatarUpdating else { return }
        isAvatarUpdating = true
        saveError = nil
        defer { isAvatarUpdating = false }
        guard await SocialAvatarUploadSender().remove() else {
            saveError = L10n.socialProfileAvatarRemoveFailed
            return
        }
        profile.avatarURL = ""
        SocialIdentityStore.cachedProfile = profile
        selectedAvatarItem = nil
    }

    private func loadSelectedAvatar() {
        guard let item = selectedAvatarItem, !isAvatarUpdating else { return }
        Task { [weak self, item] in
            guard let self else { return }
            isAvatarUpdating = true
            saveError = nil
            defer { isAvatarUpdating = false }
            do {
                guard let picked = try await item.loadTransferable(type: Data.self) else {
                    saveError = L10n.socialProfileAvatarReadFailed
                    return
                }
                guard let data = Self.avatarUploadData(from: picked) else {
                    saveError = L10n.socialProfileAvatarInvalidFormat
                    return
                }
                guard data.count <= Self.avatarMaxBytes else {
                    saveError = L10n.socialProfileAvatarTooLarge
                    return
                }
                switch await SocialAvatarUploadSender().upload(imageData: data) {
                case let .accepted(avatarURL):
                    profile.avatarURL = avatarURL
                    SocialIdentityStore.cachedProfile = profile
                case .rejectedScan:
                    saveError = L10n.socialProfileAvatarScanRejected
                case .rejectedFormat:
                    saveError = L10n.socialProfileAvatarInvalidFormat
                case .failed:
                    saveError = L10n.socialProfileAvatarUploadFailed
                }
            } catch {
                saveError = L10n.socialProfileAvatarReadFailed
            }
        }
    }

    // MARK: - Avatar transcoding

    private static let avatarMaxBytes = 10 * 1024 * 1024
    private static let avatarMaxDimension: CGFloat = 1024

    /// The backend accepts only raw JPEG or PNG bytes with a 10 MiB cap
    /// (docs/SocialAvatars.md), but PhotosPicker hands back camera photos as
    /// HEIC. Pass JPEG/PNG bytes through untouched; re-encode anything else as
    /// JPEG, downscaling very large images first so the result fits the cap.
    private static func avatarUploadData(from data: Data) -> Data? {
        if isJPEG(data) || isPNG(data) {
            return data
        }
        guard let image = UIImage(data: data) else { return nil }
        return downscale(image, toFit: avatarMaxDimension).jpegData(compressionQuality: 0.9)
    }

    private static func isJPEG(_ data: Data) -> Bool {
        data.prefix(3).elementsEqual([0xFF, 0xD8, 0xFF])
    }

    private static func isPNG(_ data: Data) -> Bool {
        data.prefix(8).elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    private static func downscale(_ image: UIImage, toFit maxDimension: CGFloat) -> UIImage {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension else { return image }
        let scale = maxDimension / largestSide
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
