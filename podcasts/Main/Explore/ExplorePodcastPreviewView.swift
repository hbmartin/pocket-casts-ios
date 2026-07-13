import SwiftUI

/// Lightweight preview sheet for a podcast found in Explore: artwork, title,
/// author and a subscribe button. Subscribing runs entirely through the
/// on-device feed pipeline, then navigates to the podcast page.
struct ExplorePodcastPreviewView: View {
    @EnvironmentObject private var theme: Theme

    let podcast: ExplorePodcast
    @ObservedObject var model: ExploreViewModel

    @State private var subscribeFailed = false

    var body: some View {
        // Scrollable with a .large fallback detent: at accessibility text sizes
        // the fixed-height medium sheet can't fit artwork + titles + button, and
        // without scrolling the subscribe button ends up unreachable.
        ScrollView {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.color(for: .primaryUi01, theme: theme).ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        VStack(spacing: 16) {
            ExploreArtworkView(urlString: podcast.artworkURL)
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)

            VStack(spacing: 4) {
                Text(podcast.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.color(for: .primaryText01, theme: theme))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                Text(podcast.author)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, 24)

            subscribeButton

            if subscribeFailed {
                Text(L10n.errorGeneralPodcastNotFound)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.color(for: .support05, theme: theme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 32)
        .frame(maxWidth: .infinity)
    }

    private var isSubscribing: Bool {
        model.subscribingPodcastId == podcast.id
    }

    private var subscribeButton: some View {
        Button {
            subscribeFailed = false
            Task {
                if let uuid = await model.subscribe(to: podcast) {
                    model.previewedPodcast = nil
                    NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey, data: [NavigationManager.podcastKey: uuid])
                } else {
                    subscribeFailed = true
                }
            }
        } label: {
            ZStack {
                Text(L10n.subscribe)
                    .font(.headline)
                    .opacity(isSubscribing ? 0 : 1)

                if isSubscribing {
                    ProgressView()
                        .tint(AppTheme.color(for: .primaryInteractive02, theme: theme))
                }
            }
            .foregroundStyle(AppTheme.color(for: .primaryInteractive02, theme: theme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(AppTheme.color(for: .primaryInteractive01, theme: theme)))
            .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
        .disabled(isSubscribing)
    }
}
