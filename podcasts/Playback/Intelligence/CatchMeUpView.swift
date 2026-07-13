import PocketCastsUtils
import SwiftUI

/// Drives the Catch Me Up sheet: loads the episode transcript, generates the
/// played-portion recap and publishes the phase the view renders.
class CatchMeUpViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded(CatchUpSummary)
        case failed
    }

    @Published private(set) var phase: Phase = .loading

    let episodeTitle: String

    private let episodeUuid: String
    private let podcastUuid: String
    private let playedUpTo: TimeInterval
    private let generator: CatchMeUpGenerator
    /// Boxed: `loadTranscript()` runs off the main actor by design.
    private let transcriptManager: PocketCastsUtils.UncheckedSendable<TranscriptManager>
    private var hasStartedLoading = false

    init(
        episodeUuid: String,
        podcastUuid: String,
        episodeTitle: String,
        playedUpTo: TimeInterval,
        intelligence: any IntelligenceProviding = OnDeviceIntelligence.shared
    ) {
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.episodeTitle = episodeTitle
        self.playedUpTo = playedUpTo
        self.generator = CatchMeUpGenerator(intelligence: intelligence)
        self.transcriptManager = PocketCastsUtils.UncheckedSendable(
            TranscriptManager(episodeUUID: episodeUuid, podcastUUID: podcastUuid)
        )
    }

    func sheetAppeared() {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        Analytics.track(.catchMeUpShown, properties: ["episode_uuid": episodeUuid, "podcast_uuid": podcastUuid])
        Task { [weak self] in
            await self?.load()
        }
    }

    private func load() async {
        var cues: [TimedCueText] = []
        if let model = try? await Self.loadTranscript(transcriptManager) {
            cues = SummaryTakeawayGenerator.timedCues(from: model)
        }

        do {
            let summary = try await generator.catchUp(cues: cues, playedUpTo: playedUpTo)
            phase = .loaded(summary)
        } catch {
            phase = .failed
            let reason: String = switch error as? CatchUpError {
            case .noTranscript: "no_transcript"
            case .modelUnavailable(let reason): reason
            case .generationFailed(let reason): reason
            case nil: "generation_error"
            }
            Analytics.track(.catchMeUpFailed, properties: [
                "episode_uuid": episodeUuid,
                "podcast_uuid": podcastUuid,
                "reason": reason
            ])
        }
    }

    nonisolated private static func loadTranscript(
        _ manager: PocketCastsUtils.UncheckedSendable<TranscriptManager>
    ) async throws -> TranscriptModel {
        try await manager.value.loadTranscript()
    }
}

/// The Catch Me Up sheet: sparkle header, recap paragraph and key-moment
/// bullets for the already-played portion of the episode.
struct CatchMeUpView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject var model: CatchMeUpViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                switch model.phase {
                case .loading:
                    loadingState
                case .loaded(let summary):
                    Text(summary.recap)
                        .font(style: .body, weight: .regular)
                        .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                        .textSelection(.enabled)

                    if !summary.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(summary.keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(verbatim: "•")
                                    Text(point)
                                }
                                .font(style: .subheadline, weight: .regular)
                                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                            }
                        }
                    }
                case .failed:
                    Text(L10n.catchMeUpFailed)
                        .font(style: .body, weight: .regular)
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(AppTheme.color(for: .primaryUi01, theme: theme).ignoresSafeArea())
        .onAppear { model.sheetAppeared() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.subheadline)
                Text(L10n.catchMeUpTitle)
                    .font(style: .title3, weight: .bold)
            }
            .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))

            Text(model.episodeTitle)
                .font(style: .footnote, weight: .medium)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                .lineLimit(2)
        }
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(L10n.catchMeUpGenerating)
                .font(style: .subheadline, weight: .regular)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}
