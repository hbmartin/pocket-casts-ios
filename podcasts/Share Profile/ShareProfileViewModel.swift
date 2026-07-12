import Dependencies
import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
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

    @Dependency(\.podcastRepository) private var podcastRepository
    @Dependency(\.episodeRepository) private var episodeRepository
    @Dependency(\.playlistRepository) private var playlistRepository

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
        // Run the synchronous repository reads off the main actor (the class is @MainActor), then
        // hop back to assign the @Published state. All three result types are Sendable.
        Task.detached { [podcastRepository, episodeRepository, playlistRepository] in
            let podcasts = podcastRepository.allPodcasts(includeUnsubscribed: false)
            let episodes = episodeRepository.episodesWithListenHistory(limit: 10)
            let filters = playlistRepository.allPlaylists(includeDeleted: false)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.followedPodcasts = podcasts
                self.recentEpisodes = episodes
                self.playlists = filters
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
        @Dependency(\.podcastRepository) var podcastRepository
        return podcastRepository.findPodcast(uuid: episode.podcastUuid, includeUnsubscribed: true)?.title
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
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documentsPath.appendingPathComponent("share_profile_photo.jpg")
    }

    nonisolated static let photoDidChangeNotification = Notification.Name("ShareProfilePhotoDidChange")

    /// The saved share-profile photo changed on disk. Bridges with
    /// `photoDidChangeNotification`, so the string-based `notifications(named:)`
    /// observer in `SubscriptionProfileImage` keeps working. No payload.
    nonisolated struct PhotoDidChange: NotificationCenter.MainActorMessage {
        typealias Subject = AnyObject
        static var name: Notification.Name { ShareProfileViewModel.photoDidChangeNotification }

        static func makeMessage(_ notification: Notification) -> Self? {
            Self()
        }

        static func makeNotification(_ message: Self) -> Notification {
            Notification(name: Self.name)
        }
    }

    nonisolated private static let photoIOQueue = DispatchQueue(label: "au.com.pocketcasts.shareprofile.photo-io", qos: .background)

    nonisolated private static func saveProfilePhoto(_ image: UIImage?) {
        photoIOQueue.async {
            if let image, let data = image.jpegData(compressionQuality: 0.85) {
                try? data.write(to: photoURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: photoURL)
            }
            NotificationCenter.postOnMainThread(PhotoDidChange())
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
