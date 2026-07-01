import SwiftUI
import Kingfisher

struct PodcastImage: View {
    let uuid: String
    let size: PodcastThumbnailSize
    let contentMode: SwiftUI.ContentMode
    let aspectRatio: CGFloat?

    init(uuid: String, size: PodcastThumbnailSize = .list, aspectRatio: CGFloat? = 1, contentMode: SwiftUI.ContentMode = .fit) {
        self.uuid = uuid
        self.size = size
        self.contentMode = contentMode
        self.aspectRatio = aspectRatio
    }

    var body: some View {
        KFImage(ImageManager.podcastUrl(imageSize: size, uuid: uuid))
            .placeholder { _ in
                if let placeholder = ImageManager.sharedManager.placeHolderImage(size) {
                    Image(uiImage: placeholder)
                        .resizable()
                }
            }
            .resizable()
            .aspectRatio(aspectRatio, contentMode: contentMode)
            .accessibilityHidden(true)
    }
}

struct PodcastCover: View {
    let podcastUuid: String
    var big: Bool = false
    var viewBackgroundStyle: ThemeStyle? = nil

    private var rectangleColor: Color {
        guard let viewBackgroundStyle else {
            return .white
        }

        return AppTheme.color(for: viewBackgroundStyle)
    }

    var body: some View {
        ZStack {
            Group {
                if big {
                    Rectangle()
                        .foregroundColor(rectangleColor)
                        .modifier(BigCoverShadow())
                } else {
                    Rectangle()
                        .foregroundColor(rectangleColor)
                        .modifier(NormalCoverShadow())
                }
            }
            .blendMode(.multiply)

            PodcastImage(uuid: podcastUuid, size: .page)
                .cornerRadius(big ? 8 : 4)
        }
    }
}

struct PodcastCoverImage: View {
    let imageName: String
    var big: Bool = false

    var body: some View {
        ZStack {
            Group {
                if big {
                    Rectangle()
                        .modifier(BigCoverShadow())
                } else {
                    Rectangle()
                        .modifier(NormalCoverShadow())
                }
            }

            Image(imageName)
                .resizable()
                .cornerRadius(big ? 8 : 4)
        }
    }
}

struct NormalCoverShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .cornerRadius(4)
            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
            .shadow(color: .black.opacity(0.09), radius: 3, x: 0, y: 3)
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 6)
            .shadow(color: .black.opacity(0.01), radius: 4, x: 0, y: 11)
            .accessibilityHidden(true)
    }
}

struct BigCoverShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 9, x: 0, y: 4)
            .shadow(color: .black.opacity(0.09), radius: 17, x: 0, y: 17)
            .shadow(color: .black.opacity(0.05), radius: 23, x: 0, y: 38)
            .shadow(color: .black.opacity(0.01), radius: 27, x: 0, y: 67)
            .accessibilityHidden(true)
    }
}
