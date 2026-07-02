import Foundation
import PocketCastsDataModel
import PocketCastsServer
import SwiftUI
import PhotosUI

@MainActor
class ShareProfileViewModel: ObservableObject {
    @Published var displayName: String = "" {
        didSet { Self.saveDisplayName(displayName) }
    }
    @Published var profilePhoto: UIImage? {
        didSet { Self.saveProfilePhoto(profilePhoto) }
    }
    @Published var shareFollowedPodcasts: Bool = true {
        didSet { UserDefaults.standard.set(shareFollowedPodcasts, forKey: Self.followedPodcastsKey) }
    }
    @Published var shareRecentEpisodes: Bool = true {
        didSet { UserDefaults.standard.set(shareRecentEpisodes, forKey: Self.recentEpisodesKey) }
    }
    @Published var sharePlaylists: Bool = true {
        didSet { UserDefaults.standard.set(sharePlaylists, forKey: Self.playlistsKey) }
    }

    static let followedPodcastsKey = "ShareProfileFollowedPodcasts"
    static let recentEpisodesKey = "ShareProfileRecentEpisodes"
    static let playlistsKey = "ShareProfilePlaylists"
    @Published var selectedPhotoItem: PhotosPickerItem? {
        didSet {
            loadPhoto()
        }
    }
    @Published var showingPhotoPicker = false
    @Published var showingCamera = false

    let email: String?

    @Published var followedPodcasts: [Podcast] = []
    @Published var recentEpisodes: [Episode] = []
    @Published var playlists: [EpisodeFilter] = []

    init() {
        email = SyncManager.isUserLoggedIn() ? ServerSettings.syncingEmail() : nil
        displayName = Self.loadDisplayName() ?? ""
        profilePhoto = Self.loadProfilePhoto()
        shareFollowedPodcasts = UserDefaults.standard.object(forKey: Self.followedPodcastsKey) as? Bool ?? true
        shareRecentEpisodes = UserDefaults.standard.object(forKey: Self.recentEpisodesKey) as? Bool ?? true
        sharePlaylists = UserDefaults.standard.object(forKey: Self.playlistsKey) as? Bool ?? true
        loadData()
    }

    private func loadData() {
        // Run the synchronous DataManager reads off the main actor (the class is @MainActor), then
        // hop back to assign the @Published state. All three result types are Sendable.
        Task.detached { [weak self] in
            let podcasts = DataManager.sharedManager.allPodcasts(includeUnsubscribed: false)
            let episodes = DataManager.sharedManager.episodesWithListenHistory(limit: 10)
            let filters = DataManager.sharedManager.allPlaylists(includeDeleted: false)
            await MainActor.run {
                self?.followedPodcasts = podcasts
                self?.recentEpisodes = episodes
                self?.playlists = filters
            }
        }
    }

    var canContinue: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func removePhoto() {
        profilePhoto = nil
        selectedPhotoItem = nil
    }

    nonisolated func podcastName(for episode: Episode) -> String? {
        DataManager.sharedManager.findPodcast(uuid: episode.podcastUuid, includeUnsubscribed: true)?.title
    }

    @MainActor
    func generateShareItems() -> [Any] {
        let cardView = ShareProfileCardView(viewModel: self)
            .environmentObject(Theme.sharedTheme)
            .frame(width: 340, height: 400)
        return [cardView.snapshot()]
    }

    private func loadPhoto() {
        guard let item = selectedPhotoItem else { return }
        Task { [weak self, item] in
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    self?.profilePhoto = image
                }
            } catch {
                return
            }
        }
    }

    // MARK: - Persistence

    nonisolated private static let displayNameKey = "ShareProfileDisplayName"

    // These persistence helpers touch only UserDefaults/FileManager (no isolated state) and are called
    // from `didSet`, from the @MainActor init, and from outside (SubscriptionProfileImage's `.task`),
    // so they stay `nonisolated` to keep disk I/O off the main actor once the class is @MainActor.
    nonisolated private static func saveDisplayName(_ name: String) {
        UserDefaults.standard.set(name, forKey: displayNameKey)
    }

    nonisolated private static func loadDisplayName() -> String? {
        UserDefaults.standard.string(forKey: displayNameKey)
    }

    nonisolated private static var photoURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("share_profile_photo.jpg")
    }

    nonisolated static let photoDidChangeNotification = Notification.Name("ShareProfilePhotoDidChange")

    nonisolated private static func saveProfilePhoto(_ image: UIImage?) {
        Task.detached(priority: .background) {
            guard let image, let data = image.jpegData(compressionQuality: 0.85) else {
                try? FileManager.default.removeItem(at: photoURL)
                await MainActor.run {
                    NotificationCenter.default.post(name: photoDidChangeNotification, object: nil)
                }
                return
            }
            try? data.write(to: photoURL)
            await MainActor.run {
                NotificationCenter.default.post(name: photoDidChangeNotification, object: nil)
            }
        }
    }

    nonisolated private static func loadProfilePhoto() -> UIImage? {
        loadSavedProfilePhoto()
    }

    nonisolated static func loadSavedProfilePhoto() -> UIImage? {
        guard FileManager.default.fileExists(atPath: photoURL.path) else { return nil }
        guard let data = try? Data(contentsOf: photoURL) else { return nil }
        return UIImage(data: data)
    }
}
