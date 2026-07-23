import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import SwiftUI

/// Drives the "Mentioned in this episode" card: validated entity mentions with
/// tap-to-seek anchors. The detail screen only attaches the card when the list
/// is non-empty, so this model just renders and reports taps.
@MainActor
class EpisodeMentionsViewModel: ObservableObject {
    let mentions: [EntityMention]
    let episodeUuid: String
    let podcastUuid: String?
    let usedModel: Bool

    private var hasTrackedShown = false

    init(mentions: [EntityMention], episodeUuid: String, podcastUuid: String?, usedModel: Bool) {
        self.mentions = mentions
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.usedModel = usedModel
    }

    func cardAppeared() {
        guard !hasTrackedShown else { return }
        hasTrackedShown = true
        Analytics.track(.episodeDetailMentionsShown, properties: [
            "episode_uuid": episodeUuid,
            "count": mentions.count,
            "method": usedModel ? "ai" : "fallback"
        ])
    }

    /// Seeks-and-plays at the mention (the canonical deep-link path, loading the
    /// episode first when it isn't the one now playing).
    func mentionTapped(_ mention: EntityMention) {
        Analytics.track(.episodeDetailMentionTapped, properties: [
            "episode_uuid": episodeUuid,
            "kind": mention.kind.rawValue,
            "seconds": Int(mention.startTime)
        ])
        PlaybackManager.shared.play(episodeUuid: episodeUuid, podcastUuid: podcastUuid, at: mention.startTime)
    }

    static func icon(for kind: EntityMention.Kind) -> String {
        switch kind {
        case .person: "person"
        case .book: "book"
        case .product: "shippingbox"
        case .website: "globe"
        case .place: "mappin.and.ellipse"
        case .organization: "building.2"
        case .other: "tag"
        }
    }
}

/// The card itself: one row per mention with a kind icon and a tappable
/// "Mentioned at m:ss" seek link.
struct EpisodeMentionsCardView: View {
    @EnvironmentObject private var theme: Theme
    @ObservedObject var viewModel: EpisodeMentionsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.episodeMentionsTitle)
                .font(style: .footnote, weight: .semibold)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                .textCase(.uppercase)

            ForEach(viewModel.mentions, id: \.self) { mention in
                Button {
                    viewModel.mentionTapped(mention)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: EpisodeMentionsViewModel.icon(for: mention.kind))
                            .font(.footnote)
                            .frame(width: 20)
                            .foregroundColor(AppTheme.color(for: .primaryIcon02, theme: theme))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(mention.name)
                                .font(style: .subheadline, weight: .medium)
                                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                                .lineLimit(1)
                            Text(L10n.episodeMentionsAtTime(TranscriptChapterGenerator.timestampString(for: mention.startTime)))
                                .font(style: .caption, weight: .semibold)
                                .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
                        }

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.color(for: .primaryUi02, theme: theme))
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .onAppear { viewModel.cardAppeared() }
    }
}
