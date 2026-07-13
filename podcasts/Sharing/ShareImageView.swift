import SwiftUI
import Kingfisher

struct ShareImageInfo {
    let name: String
    let title: String
    let description: String
    let artwork: URL
    let gradient: Gradient
    /// Smart highlights: the transcript excerpt rendered by the `.quote` style.
    var excerpt: String? = nil
}

enum ShareImageStyle: CaseIterable {
    case quote
    case large
    case medium
    case small
    case audio

    var tabString: String {
        switch self {
        case .quote:
            return "quote"
        case .large:
            return "large"
        case .medium:
            return "medium"
        case .small:
            return "small"
        case .audio:
            return "audio"
        }
    }

    var previewSize: CGSize {
        switch self {
        case .quote:
            CGSize(width: 292, height: 360)
        case .large:
            CGSize(width: 292, height: 422)
        case .medium:
            CGSize(width: 292, height: 292)
        case .small:
            CGSize(width: 324, height: 169)
        case .audio:
            CGSize(width: 100, height: 100)
        }
    }

    func shareDescription(option: SharingModal.Option) -> String? {
        switch (option, self) {
        case (.highlight, .quote):
            L10n.highlightQuoteShareStyle
        case (.episode, _), (.podcast, _):
            L10n.shareDescription
        case (.clip, .audio):
            L10n.createAudioClipDescription
        default:
            nil
        }
    }
}

struct ShareImageView: View {

    let info: ShareImageInfo
    let style: ShareImageStyle

    @Binding var angle: Double

    var body: some View {
        ZStack {
            switch style {
            case .quote:
                background()
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(info.excerpt ?? L10n.highlightExcerptUnavailable)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(8)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.title)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(info.description)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    PocketCastsLogoPill()
                        .frame(maxWidth: .infinity)
                }
                .multilineTextAlignment(.leading)
                .padding(24)
                .aspectRatio(style.previewSize.width/style.previewSize.height, contentMode: .fit)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L10n.highlightQuoteCardA11y(info.excerpt ?? L10n.highlightExcerptUnavailable))
            case .large:
                background()
                VStack(spacing: 32) {
                    image()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 270)
                    text()
                    PocketCastsLogoPill()
                }
                .padding(24)
                .aspectRatio(style.previewSize.width/style.previewSize.height, contentMode: .fit)
            case .medium:
                background()
                VStack(spacing: 24) {
                    image()
                        .aspectRatio(1, contentMode: .fit)
                    text(lineLimit: 1)
                        .frame(alignment: .leading)
                    PocketCastsLogoPill()
                }
                .padding(24)
                .aspectRatio(style.previewSize.width/style.previewSize.height, contentMode: .fit)
            case .small:
                background()
                ZStack {
                    HStack(spacing: 18) {
                        image()
                            .aspectRatio(1, contentMode: .fit)
                        text(alignment: .leading, textAlignment: .leading, lineLimit: 3)
                    }
                    .padding(24)
                    Image("family_pc_logo")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .padding(.top, 10)
                        .padding(.trailing, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                .aspectRatio(style.previewSize.width/style.previewSize.height, contentMode: .fit)
            case .audio:
                Image("music")
            }
        }
    }

    @ViewBuilder func background() -> some View {
        ZStack {
            LinearGradient(gradient: info.gradient, startPoint: .top, endPoint: .bottom)
            let rotationFactor = sin(Angle(degrees: angle).radians)
            KidneyShape()
                .fill(info.gradient.stops.first?.color ?? .black)
                .blur(radius: 100)
                .opacity(0.15 + 0.5 * abs(rotationFactor))
                .frame(width: 230, height: 350)
                .offset(x: -50, y: -20)
                .rotationEffect(.degrees(180 * rotationFactor))
            KidneyShape()
                .fill(.white)
                .blur(radius: 50)
                .opacity(0.15 + 0.5 * abs(rotationFactor))
                .frame(width: 300, height: 350)
                .offset(x: 50, y: 40)
                .rotationEffect(.degrees(-180 * rotationFactor))
                .blendMode(.softLight)
            Color.black.opacity(0.2)
        }
    }

    @ViewBuilder func image() -> some View {
        KFImage(info.artwork)
            .resizable()
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder func text(alignment: HorizontalAlignment = .center, textAlignment: TextAlignment = .center, lineLimit: Int = 2) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(info.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.5))
            Text(info.title)
                .font(Font.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(lineLimit)
            Text(info.description)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.5))
        }
        .multilineTextAlignment(textAlignment)
    }
}

struct KidneyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.minY),
            control2: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY)
        )

        // Indentation
        let indentWidth = rect.width * 0.2
        let indentHeight = rect.height * 0.3
        path.move(to: CGPoint(x: rect.midX - indentWidth, y: rect.minY + rect.height * 0.3))
        path.addCurve(
            to: CGPoint(x: rect.midX + indentWidth, y: rect.minY + rect.height * 0.3),
            control1: CGPoint(x: rect.midX - indentWidth / 2, y: rect.minY + indentHeight),
            control2: CGPoint(x: rect.midX + indentWidth / 2, y: rect.minY + indentHeight)
        )

        return path
    }
}

let previewInfo = ShareImageInfo(name: "This American Life", title: "Dylan Field, Figma Co-founder, Talks Design, Economy, and life after failed Adobe acquisitions", description: Date().formatted(), artwork: URL(string: "https://static.pocketcasts.com/discover/images/280/3782b780-0bc5-012e-fb02-00163e1b201c.jpg")!, gradient: Gradient(colors: [Color.red, Color(hex: "620603")]))

#Preview("large") {
    ShareImageView(info: previewInfo, style: .large, angle: .constant(0))
}

#Preview("medium") {
    ShareImageView(info: previewInfo, style: .medium, angle: .constant(0))
}

#Preview("small") {
    ShareImageView(info: previewInfo, style: .small, angle: .constant(0))
}
