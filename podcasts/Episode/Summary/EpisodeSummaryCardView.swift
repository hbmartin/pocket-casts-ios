import PocketCastsUtils
import SwiftUI

/// AI episode summary card on the episode detail screen: header with sparkle +
/// "AI-generated" caption, the linkified summary text (timestamps tap to
/// seek), and key-takeaway rows with mm:ss chips
/// (plans/AI UX Improvements.md Phase 2).
struct EpisodeSummaryCardView: View {
    @EnvironmentObject var theme: Theme
    @ObservedObject private var viewModel: EpisodeSummaryViewModel

    init(viewModel: EpisodeSummaryViewModel) {
        self.viewModel = viewModel
    }

    @ScaledMetric(relativeTo: .body) private var iconSize = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summary
            catchMeUp
            takeaways
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.primaryUi02Active)
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 14)
        .onAppear {
            viewModel.cardAppeared()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(theme.primaryIcon02)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.episodeSummaryCardTitle)
                    .font(size: 15, style: .body, weight: .semibold)
                    .foregroundStyle(theme.primaryText01)
                Text(L10n.episodeSummaryCardGeneratedDisclaimer)
                    .font(size: 11, style: .caption, weight: .regular)
                    .foregroundStyle(theme.primaryText02)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Summary text

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.linkifiedSummary)
                .font(size: 14, style: .subheadline, weight: .regular)
                .foregroundStyle(theme.primaryText01)
                .tint(theme.primaryInteractive01)
                .lineLimit(viewModel.isExpanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.openURL, OpenURLAction { url in
                    guard let seconds = EpisodeSummaryViewModel.seekSeconds(from: url) else {
                        return .systemAction
                    }
                    viewModel.seek(to: seconds, source: "summary_link")
                    return .handled
                })

            if viewModel.isExpandable {
                Button {
                    viewModel.toggleExpanded()
                } label: {
                    Text(viewModel.isExpanded ? L10n.episodeSummaryCardShowLess : L10n.episodeSummaryCardShowMore)
                        .font(size: 13, style: .footnote, weight: .semibold)
                        .foregroundStyle(theme.primaryInteractive01)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Catch Me Up

    /// "Catch Me Up" for in-progress episodes: recaps the already-played
    /// portion in a sheet (Deferred Item 19). Shares the generator with the
    /// player shelf action.
    @ViewBuilder
    private var catchMeUp: some View {
        if viewModel.isCatchMeUpAvailable {
            Button {
                viewModel.catchMeUpTapped()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                    Text(L10n.catchMeUpTitle)
                        .font(size: 13, style: .footnote, weight: .semibold)
                }
                .foregroundStyle(theme.primaryInteractive01)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(theme.primaryUi05))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $viewModel.isShowingCatchMeUp) {
                CatchMeUpView(model: CatchMeUpViewModel(
                    episodeUuid: viewModel.episodeUuid,
                    podcastUuid: viewModel.podcastUuid,
                    episodeTitle: viewModel.episodeTitle,
                    playedUpTo: viewModel.playedUpTo
                ))
                .environmentObject(theme)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Takeaways

    @ViewBuilder
    private var takeaways: some View {
        switch viewModel.takeawayState {
        case .loading:
            EmptyView()
        case .loaded(let takeaways, let layer):
            if !takeaways.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Rectangle()
                        .fill(theme.primaryUi05)
                        .frame(height: 1)

                    if layer == .generatedChapters {
                        Text(L10n.episodeSummaryCardKeyMoments)
                            .font(size: 12, style: .caption, weight: .semibold)
                            .foregroundStyle(theme.primaryText02)
                    }

                    ForEach(takeaways, id: \.startTime) { takeaway in
                        takeawayRow(takeaway)
                    }
                }
            }
        }
    }

    private func takeawayRow(_ takeaway: Takeaway) -> some View {
        Button {
            viewModel.seek(to: takeaway.startTime, source: "takeaway_row")
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(TimeFormatter.shared.playTimeFormat(time: takeaway.startTime))
                    .font(size: 12, style: .caption, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(theme.primaryInteractive01)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(theme.primaryUi05))
                Text(takeaway.text)
                    .font(size: 14, style: .subheadline, weight: .regular)
                    .foregroundStyle(theme.primaryText01)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Takeaways") {
    EpisodeSummaryCardView(
        viewModel: EpisodeSummaryViewModel(
            fixtureSummary: "A deep dive into how small teams ship fast: the hosts break down why fewer meetings (2:30) and stronger written culture beat headcount, and what changed after the 45:10 rewrite.",
            takeaways: [
                Takeaway(text: "Small teams move faster when writing replaces meetings.", startTime: 150),
                Takeaway(text: "The rewrite only worked because scope was frozen first.", startTime: 2710)
            ],
            layer: .foundationModels
        )
    )
    .environmentObject(Theme(previewTheme: .light))
}

#Preview("Key moments fallback") {
    EpisodeSummaryCardView(
        viewModel: EpisodeSummaryViewModel(
            fixtureSummary: "A shorter summary with no model available.",
            takeaways: [
                Takeaway(text: "Introduction", startTime: 0),
                Takeaway(text: "Interview", startTime: 620)
            ],
            layer: .generatedChapters
        )
    )
    .environmentObject(Theme(previewTheme: .dark))
}

#Preview("Summary only") {
    EpisodeSummaryCardView(
        viewModel: EpisodeSummaryViewModel(
            fixtureSummary: "Just the summary, no transcript or generated chapters available for this episode.",
            takeaways: [],
            layer: .summaryOnly
        )
    )
    .environmentObject(Theme(previewTheme: .light))
}
