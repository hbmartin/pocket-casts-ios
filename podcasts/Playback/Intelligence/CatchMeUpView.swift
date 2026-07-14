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

    /// Runs the sheet's whole load inside the view's `.task`, so dismissing the
    /// sheet cancels transcript loading and model generation instead of leaving
    /// them running detached.
    func sheetAppeared() async {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        Analytics.track(.catchMeUpShown, properties: ["episode_uuid": episodeUuid, "podcast_uuid": podcastUuid])
        await load()
    }

    private func load() async {
        var cues: [TimedCueText] = []
        if let model = try? await Self.loadTranscript(transcriptManager) {
            cues = SummaryTakeawayGenerator.timedCues(from: model)
        }
        guard !Task.isCancelled else {
            hasStartedLoading = false
            return
        }

        // `playedUpTo` is on the playback timeline; non-local transcript cues
        // are on the reference timeline. Convert before the generator compares
        // them (mirrors `EpisodeSummaryViewModel.seek(to:)`, which maps the
        // other way). Valid to read `isDisplayingLocalTranscription` here —
        // `loadTranscript()` has completed.
        let timingManager = FingerprintTimingManager.shared
        var isTimingActive = false
        if case .active = timingManager.state { isTimingActive = true }
        let effectivePlayedUpTo = Self.effectivePlayedUpTo(
            playedUpTo,
            isLocalTranscript: transcriptManager.value.isDisplayingLocalTranscription,
            isTimingActive: isTimingActive,
            referenceTime: { timingManager.referenceTime(forPlaybackTime: $0, episodeUuid: episodeUuid) }
        )

        do {
            let summary = try await generator.catchUp(cues: cues, playedUpTo: effectivePlayedUpTo)
            guard !Task.isCancelled else {
                hasStartedLoading = false
                return
            }
            phase = .loaded(summary)
        } catch {
            guard !Task.isCancelled else {
                hasStartedLoading = false
                return
            }
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

    /// Which played-up-to value the cue filter should use: the raw playback
    /// time for locally generated transcripts (cut from the played audio, so
    /// natively aligned), or the fingerprint-mapped reference time when the
    /// transcript is podcast-provided/server and the alignment is active for
    /// this episode. Falls back to the raw value when no mapping is available.
    nonisolated static func effectivePlayedUpTo(
        _ playedUpTo: TimeInterval,
        isLocalTranscript: Bool,
        isTimingActive: Bool,
        referenceTime: (TimeInterval) -> TimeInterval?
    ) -> TimeInterval {
        guard !isLocalTranscript, isTimingActive, let mapped = referenceTime(playedUpTo) else {
            return playedUpTo
        }
        return mapped
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
        // `.task` (not `.onAppear` + unstored Task) so dismissing the sheet
        // cancels the in-flight transcript load and recap generation.
        .task { await model.sheetAppeared() }
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
