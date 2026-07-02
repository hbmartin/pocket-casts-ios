import SwiftUI
import Kingfisher

struct PlaylistArtworkView: View {
    struct ImageItem: Equatable {
        let id: String
        let url: URL
    }

    @EnvironmentObject var theme: Theme
    let items: [ImageItem]

    private let cornerRadius: CGFloat

    init(
        items: [ImageItem],
        cornerRadius: CGFloat = 4
    ) {
        self.items = items
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Rectangle()
                    .foregroundColor(theme.primaryUi05)
                if items.isEmpty {
                    Image("playlist_list_icon")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(theme.primaryIcon03)
                        .frame(width: size.width * 0.4, height: size.height * 0.4)
                } else {
                    switch items.count {
                    case 4:
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                AsyncImageView(url: items[0].url, cacheKey: items[0].id)
                                    .frame(width: size.width / 2, height: size.height / 2)
                                    .clipped()
                                AsyncImageView(url: items[1].url, cacheKey: items[1].id)
                                    .frame(width: size.width / 2, height: size.height / 2)
                                    .clipped()
                            }
                            HStack(spacing: 0) {
                                AsyncImageView(url: items[2].url, cacheKey: items[2].id)
                                    .frame(width: size.width / 2, height: size.height / 2)
                                    .clipped()
                                AsyncImageView(url: items[3].url, cacheKey: items[3].id)
                                    .frame(width: size.width / 2, height: size.height / 2)
                                    .clipped()
                            }
                        }
                    default:
                        AsyncImageView(url: items[0].url, cacheKey: items[0].id)
                            .frame(width: size.width, height: size.height)
                            .clipped()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.accessibilityPlaylistImage)
    }
}

enum PlaylistArtworkHelper {
    static func distinctPodcasts<T>(
        from episodes: [T],
        limit: Int,
        podcastUuid: (T) -> String
    ) -> [T] {
        var seen = Set<String>()
        var results: [T] = []

        for episode in episodes {
            if seen.insert(podcastUuid(episode)).inserted {
                results.append(episode)

                if results.count == limit {
                    break
                }
            }
        }
        if !results.isEmpty, results.count < limit {
            return Array(results.prefix(1))
        }
        return results
    }

    @MainActor
    static func gridArtworkItems<T>(
        from episodes: [T],
        limit: Int,
        podcastUuid: (T) -> String
    ) -> [PlaylistArtworkView.ImageItem] {
        let distinctEpisodes = distinctPodcasts(from: episodes, limit: limit, podcastUuid: podcastUuid)

        return distinctEpisodes.map { episode in
            let uuid = podcastUuid(episode)
            let url = ImageManager.podcastUrl(imageSize: .grid, uuid: uuid)
            return PlaylistArtworkView.ImageItem(id: uuid, url: url)
        }
    }
}
