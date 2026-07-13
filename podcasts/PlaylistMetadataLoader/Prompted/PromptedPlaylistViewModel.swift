import Foundation
import PocketCastsDataModel

/// Drives the "Describe your playlist" sheet: interprets the description
/// (on-device model with deterministic fallback), applies the draft over a
/// fresh `PlaylistManager.createNewPlaylist()` base, and hands the configured
/// — still unsaved — filter back for the preview screen. The description text
/// itself is never persisted.
@MainActor
final class PromptedPlaylistViewModel: ObservableObject {
    @Published var prompt: String = ""
    @Published private(set) var isGenerating = false
    /// Show names the fuzzy matcher couldn't resolve against the library,
    /// surfaced inline; generating again with the same description proceeds
    /// without them.
    @Published private(set) var unmatchedPodcastNames: [String] = []

    /// Captured once per sheet: drives the "simpler interpreter" notice when
    /// the on-device model can't run.
    let intelligenceAvailable: Bool

    static let examplePrompts: [String] = [
        L10n.promptedPlaylistExample1,
        L10n.promptedPlaylistExample2,
        L10n.promptedPlaylistExample3
    ]

    private let interpreter: PlaylistPromptInterpreter
    private let typedName: String
    private let onDraftReady: (EpisodeFilter) -> Void

    /// The application awaiting confirmation after unmatched names were
    /// surfaced, keyed by the description it was generated from.
    private var pendingFilter: EpisodeFilter?
    private var pendingPrompt: String?

    init(
        typedName: String,
        interpreter: PlaylistPromptInterpreter = PlaylistPromptInterpreter(),
        onDraftReady: @escaping (EpisodeFilter) -> Void
    ) {
        self.typedName = typedName
        self.interpreter = interpreter
        self.onDraftReady = onDraftReady
        self.intelligenceAvailable = interpreter.intelligenceIsAvailable()
    }

    var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    func generate() async {
        let description = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty, !isGenerating else { return }

        // Second tap after unmatched names were surfaced for this same
        // description: continue with the podcasts that did match.
        if let pendingFilter, pendingPrompt == description {
            onDraftReady(pendingFilter)
            return
        }
        pendingFilter = nil
        pendingPrompt = nil

        isGenerating = true
        defer { isGenerating = false }

        let interpretation = await interpreter.interpret(prompt: description)
        if let reason = interpretation.fallbackReason {
            Analytics.track(.promptedPlaylistGenerationFailed, properties: ["reason": reason])
        }

        var base = PlaylistManager.createNewPlaylist()
        base.setTitle(title(suggested: interpretation.draft.suggestedName), defaultTitle: L10n.playlistsDefaultNewPlaylist.localizedCapitalized)

        let candidates = DataManager.sharedManager.allPodcasts(includeUnsubscribed: false).map {
            PodcastMatchCandidate(uuid: $0.uuid, title: $0.title ?? "")
        }
        let application = interpretation.draft.applied(to: base, podcasts: candidates)

        Analytics.track(.promptedPlaylistGenerated, properties: [
            "used_fm": interpretation.usedFoundationModels,
            "rules_count": application.appliedRuleCount
        ])

        unmatchedPodcastNames = application.unmatchedPodcastNames
        if application.unmatchedPodcastNames.isEmpty {
            onDraftReady(application.filter)
        } else {
            pendingFilter = application.filter
            pendingPrompt = description
        }
    }

    /// A name the user actually typed on the creation screen wins; otherwise
    /// the model's suggestion; otherwise the default.
    private func title(suggested: String?) -> String {
        let typed = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty, typed != L10n.playlistsDefaultNewPlaylist {
            return typed
        }
        return suggested ?? L10n.playlistsDefaultNewPlaylist
    }
}
