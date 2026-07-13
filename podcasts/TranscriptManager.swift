import Foundation
import PocketCastsDataModel
import PocketCastsUtils
#if !os(tvOS)
import Capture
#endif

/// Which transcript to prefer when both a podcast-provided transcript and a
/// locally generated (on-device) transcript exist for an episode.
nonisolated enum TranscriptSource {
    /// Prefer the locally generated transcript when one exists, otherwise fall
    /// back to the podcast-provided flow.
    case automatic
    case podcastProvided
    case localGenerated
}

enum TranscriptError: Error {
    case notAvailable
    case failedToLoad
    case notSupported(format: String)
    case failedToParse
    case empty

    var localizedDescription: String {
        switch self {
        case .notAvailable:
            return L10n.transcriptErrorNotAvailable
        case .failedToLoad:
            return L10n.transcriptErrorFailedToLoad
        case .notSupported(let format):
            return L10n.transcriptErrorNotSupported(format)
        case .failedToParse:
            return L10n.transcriptErrorFailedToParse
        case .empty:
            return L10n.transcriptErrorEmpty
        }
    }
}

nonisolated class TranscriptManager {

    typealias Transcript = Episode.Metadata.Transcript

    let episodeUUID: String

    let podcastUUID: String

    let showCoordinator: ShowInfoCoordinating

    private(set) var hasGeneratedTranscripts: Bool = false
    private(set) var isDisplayingGeneratedTranscript: Bool = false

    /// Which transcript source `loadTranscript()` should prefer. Set by the
    /// transcript UI's source switcher before loading.
    var sourcePreference: TranscriptSource = .automatic

    /// True when a completed locally generated transcription record exists for
    /// this episode (regardless of which source is being displayed).
    private(set) var hasLocalTranscription: Bool = false

    /// True when the model returned by the last `loadTranscript()` call came from
    /// the locally generated VTT artifact. Local transcripts are cut from the
    /// exact audio file the user plays, so callers skip fingerprint timing.
    private(set) var isDisplayingLocalTranscription: Bool = false

    /// True when the episode metadata advertises at least one podcast-provided
    /// transcript. Best-effort when a local transcript short-circuits the load.
    private(set) var hasPodcastProvidedTranscripts: Bool = false

    private let artifactStore = TranscriptionArtifactStore()

    init(episodeUUID: String, podcastUUID: String, showCoordinator: ShowInfoCoordinating = ShowInfoCoordinator.shared) {
        self.episodeUUID = episodeUUID
        self.podcastUUID = podcastUUID
        self.showCoordinator = showCoordinator
    }

    public func loadTranscript() async throws -> TranscriptModel {
        isDisplayingLocalTranscription = false

        if FeatureFlag.diarizedTranscription.enabled {
            let record = DataManager.sharedManager.transcriptions.find(episodeUuid: episodeUUID)
            hasLocalTranscription = record?.transcriptionStatus == .completed
            if sourcePreference != .podcastProvided,
               let record, record.transcriptionStatus == .completed,
               let localModel = loadLocalTranscript(record: record) {
                // Best-effort probe so the source switcher knows whether a
                // podcast-provided transcript also exists; failures just mean
                // the switcher won't offer the podcast source this time.
                let metadata = try? await showCoordinator.loadTranscriptsMetadata(podcastUuid: podcastUUID, episodeUuid: episodeUUID)
                hasPodcastProvidedTranscripts = metadata.map { !$0.transcripts.isEmpty } ?? false
                isDisplayingLocalTranscription = true
                return localModel
            }
        }

        guard
            let metadata = try? await showCoordinator.loadTranscriptsMetadata(podcastUuid: podcastUUID, episodeUuid: episodeUUID),
            !metadata.transcripts.isEmpty else {
            throw TranscriptError.notAvailable
        }
        hasPodcastProvidedTranscripts = true
        var transcriptsAvailable = metadata.transcripts
        hasGeneratedTranscripts = metadata.hasGeneratedTranscripts
        isDisplayingGeneratedTranscript = metadata.isDisplayingGeneratedTranscript
        while let transcript = TranscriptFormat.bestTranscript(from: transcriptsAvailable) {
            do {
                let model = try await loadTranscript(transcript)
                return model
            } catch TranscriptError.empty, TranscriptError.failedToParse {
                transcriptsAvailable.removeAll { other in
                    other.transcriptFormat == transcript.transcriptFormat
                }
            } catch {
                throw error
            }
        }
        throw TranscriptError.failedToLoad
    }

    /// Builds a model from the locally generated VTT artifact, applying any user
    /// speaker renames on the raw VTT before parsing. Returns nil (falling back
    /// to the podcast-provided flow) when the artifact is missing or unparseable.
    private func loadLocalTranscript(record: EpisodeTranscriptionRecord) -> TranscriptModel? {
        guard let rawVTT = artifactStore.read(episodeUuid: episodeUUID) else {
            return nil
        }
        let vtt = TranscriptionArtifactStore.applyingSpeakerNames(vtt: rawVTT, namesJSON: record.speakerNames)
        guard let model = TranscriptModel.makeModel(from: vtt, format: .vtt), !model.isEmtpy else {
            return nil
        }
        return model
    }

    private func loadTranscript(_ transcript: Transcript) async throws -> TranscriptModel {
        guard let transcriptFormat = transcript.transcriptFormat else {
            throw TranscriptError.notSupported(format: transcript.type)
        }

        guard
            let transcriptURL = URL(string: transcript.url),
            let transcriptText = try? await dataRetriever.loadTranscript(url: transcriptURL)
        else {
            throw TranscriptError.failedToLoad
        }

        #if !os(tvOS)
        await MainActor.run {
            let fields: Fields = [
                "category": "transcript",
                "url": transcriptURL.absoluteString
            ]

            Capture.Logger.logInfo(
                "Transcript file loaded",
                fields: fields
            )
        }
        #endif
        guard let model = TranscriptModel.makeModel(from: transcriptText, format: transcriptFormat) else {
            throw TranscriptError.failedToParse
        }

        if model.isEmtpy {
            throw TranscriptError.empty
        }

        return model
    }

    private lazy var dataRetriever: TranscriptsDataRetriever = {
        return TranscriptsDataRetriever()
    }()
}
