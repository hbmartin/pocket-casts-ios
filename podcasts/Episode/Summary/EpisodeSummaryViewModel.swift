import Foundation
import PocketCastsUtils
import SwiftUI

/// Drives the AI episode summary card on the episode detail screen
/// (plans/AI UX Improvements.md Phase 2).
///
/// The summary text renders immediately; key takeaways stream in behind it
/// through `SummaryTakeawayGenerator`'s layered pipeline (FoundationModels →
/// generated chapters as "Key moments" → summary only).
class EpisodeSummaryViewModel: ObservableObject {
    enum TakeawayState: Equatable {
        case loading
        case loaded([Takeaway], layer: SummaryTakeawayLayer)
    }

    @Published private(set) var takeawayState: TakeawayState = .loading
    @Published var isExpanded = false

    let episodeUuid: String
    let podcastUuid: String
    let summaryText: String

    private let episodeDuration: TimeInterval
    private let generator: SummaryTakeawayGenerator
    /// Boxed: `loadTranscript()` runs off the main actor by design.
    private let transcriptManager: PocketCastsUtils.UncheckedSendable<TranscriptManager>
    private var hasStartedLoading = false
    private var hasTrackedShown = false

    init(
        summary: String,
        episodeUuid: String,
        podcastUuid: String,
        duration: TimeInterval,
        intelligence: any IntelligenceProviding = OnDeviceIntelligence.shared
    ) {
        self.summaryText = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.episodeDuration = duration
        self.generator = SummaryTakeawayGenerator(intelligence: intelligence)
        self.transcriptManager = PocketCastsUtils.UncheckedSendable(
            TranscriptManager(episodeUUID: episodeUuid, podcastUUID: podcastUuid)
        )
    }

    /// Fixture initializer for previews and snapshot tests: the takeaway state
    /// is preset and `cardAppeared()` neither loads nor tracks anything.
    init(
        fixtureSummary: String,
        takeaways: [Takeaway],
        layer: SummaryTakeawayLayer,
        isExpanded: Bool = false
    ) {
        self.summaryText = fixtureSummary
        self.episodeUuid = ""
        self.podcastUuid = ""
        self.episodeDuration = 0
        self.generator = SummaryTakeawayGenerator()
        self.transcriptManager = PocketCastsUtils.UncheckedSendable(
            TranscriptManager(episodeUUID: "", podcastUUID: "")
        )
        self.takeawayState = .loaded(takeaways, layer: layer)
        self.isExpanded = isExpanded
        self.hasStartedLoading = true
        self.hasTrackedShown = true
    }

    // MARK: - Summary text

    /// Heuristic for offering expand/collapse without measuring rendered lines:
    /// summaries short enough to fit the collapsed line limit skip the button.
    var isExpandable: Bool {
        summaryText.count > 280
    }

    var linkifiedSummary: AttributedString {
        TimestampLinkifier.linkified(summaryText) { seconds in
            Self.seekURL(for: seconds)
        }
    }

    func toggleExpanded() {
        isExpanded.toggle()
    }

    // MARK: - Lifecycle

    func cardAppeared() {
        if !hasTrackedShown {
            hasTrackedShown = true
            track(.episodeDetailSummaryCardShown)
        }
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        Task { [weak self] in
            await self?.loadTakeaways()
        }
    }

    private func loadTakeaways() async {
        var cues: [TimedCueText] = []
        if let model = try? await Self.loadTranscript(transcriptManager) {
            cues = SummaryTakeawayGenerator.timedCues(from: model)
        }

        let generatedChapters = (try? await ShowInfoCoordinator.shared.loadChapters(
            podcastUuid: podcastUuid,
            episodeUuid: episodeUuid
        ))?.generated ?? []
        let keyMoments = generatedChapters.map { Takeaway(text: $0.title, startTime: $0.startTime) }

        let result = await generator.takeaways(cues: cues, keyMoments: keyMoments, duration: episodeDuration)

        takeawayState = .loaded(result.takeaways, layer: result.layer)

        if let reason = result.fallbackReason {
            track(.episodeDetailSummaryGenerationFailed, extraProperties: [
                "fallback_layer": result.layer.rawValue,
                "reason": reason
            ])
        }
    }

    nonisolated private static func loadTranscript(
        _ manager: PocketCastsUtils.UncheckedSendable<TranscriptManager>
    ) async throws -> TranscriptModel {
        try await manager.value.loadTranscript()
    }

    // MARK: - Seek

    /// Seek path per plan Phase 2: takeaway times live on the reference
    /// timeline, so when the episode is playing and the fingerprint mapping is
    /// active we translate to playback time (matches transcript tap-to-seek);
    /// otherwise a raw seek (matches today's generated-chapter seeks). A
    /// not-loaded episode cold-loads through the canonical
    /// `PlaybackManager.play(episodeUuid:podcastUuid:at:)`.
    func seek(to referenceTime: TimeInterval, source: String) {
        track(.episodeDetailSummaryTakeawayTapped, extraProperties: [
            "seconds": Int(referenceTime),
            "source": source
        ])

        let playbackManager = PlaybackManager.shared
        guard playbackManager.isNowPlayingEpisode(episodeUuid: episodeUuid) else {
            playbackManager.play(episodeUuid: episodeUuid, podcastUuid: podcastUuid, at: referenceTime)
            return
        }

        let timingManager = FingerprintTimingManager.shared
        if case .active = timingManager.state,
           let mapped = timingManager.playbackTime(forReferenceTime: referenceTime) {
            playbackManager.seekTo(time: mapped, startPlaybackAfterSeek: true)
        } else {
            playbackManager.seekTo(time: referenceTime, startPlaybackAfterSeek: true)
        }
    }

    // MARK: - Timestamp links

    /// In-card URLs carried by linkified timestamps in the summary text.
    /// Never leaves the card: the view intercepts them via `OpenURLAction`.
    static let seekURLScheme = "pocketcasts-summary"

    static func seekURL(for seconds: TimeInterval) -> URL? {
        URL(string: "\(seekURLScheme)://seek?t=\(Int(seconds))")
    }

    static func seekSeconds(from url: URL) -> TimeInterval? {
        guard url.scheme == seekURLScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "t" })?.value,
              let seconds = TimeInterval(value), seconds >= 0 else {
            return nil
        }
        return seconds
    }

    // MARK: - Analytics

    private func track(_ event: AnalyticsEvent, extraProperties: [String: Sendable] = [:]) {
        var properties: [String: Sendable] = [
            "episode_uuid": episodeUuid,
            "podcast_uuid": podcastUuid
        ]
        properties.merge(extraProperties) { current, _ in current }
        Analytics.track(event, properties: properties)
    }
}
