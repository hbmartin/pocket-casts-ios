import SwiftUI

struct SmartPlaylistCreationView: View {
    @EnvironmentObject var theme: Theme

    let icon: String
    let title: String
    let subtitle: String
    let onTap: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) var iconSize: CGFloat = 24

    init(
        icon: String = "cs-sparkle-black",
        title: String = L10n.playlistCreationCreateSmartPlaylistButtonTitle,
        subtitle: String = L10n.playlistCreationCreateSmartPlaylistButtonSubtitle,
        onTap: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.onTap = onTap
    }

    var body: some View {
        Button {
            onTap()
        }  label: {
            HStack(spacing: 12.0) {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(theme.primaryText01)
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                VStack(alignment: .leading, spacing: 2.0) {
                    Text(title)
                        .font(size: 15.0, style: .body, weight: .medium)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(theme.primaryText01)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(size: 13.0, style: .body, weight: .regular)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(theme.primaryText02)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.8)
                }
                .padding(.vertical, 2.0)
                Spacer()
                Image("cs-chevron")
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(theme.primaryText02)
                    .frame(width: iconSize, height: iconSize)
            }
            .frame(minHeight: 59.0)
            .padding(.horizontal, 16.0)
        }
        .background(theme.primaryUi02Active)
        .cornerRadius(12.0)
    }
}
