import Foundation
import PocketCastsTranscription
import PocketCastsUtils
@preconcurrency import SpeakerKit
@preconcurrency import WhisperKit

/// `SpeakerDiarizing` backed by Argmax SpeakerKit's pyannote CoreML pipeline
/// (~10MB of segmenter/embedder/PLDA models, cached in `WhisperKitModelStore`'s
/// tree). Shared by both local pipeline modes: Apple built-in ASR + SpeakerKit
/// and WhisperKit + SpeakerKit.
///
/// An actor because the package's `SpeakerKit` object graph is a non-Sendable
/// class hierarchy; all touches stay isolated here. Note this shadows the
/// package's own `SpeakerKit.SpeakerKitDiarizer` class inside the app target —
/// the package type is only ever reached through the `SpeakerKit` facade.
actor SpeakerKitDiarizer: SpeakerDiarizing {
    private let modelStore: WhisperKitModelStore
    private var kit: SpeakerKit?

    init(modelStore: WhisperKitModelStore = WhisperKitModelStore()) {
        self.modelStore = modelStore
    }

    // MARK: - SpeakerDiarizing

    /// Downloads (behind the cellular gate) and loads the pyannote models.
    /// Throws `.modelDownloadFailed` when blocked or offline — the queue treats
    /// any diarizer failure as non-fatal and falls back to monologue output.
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        if kit == nil {
            if !modelStore.isDiarizerDownloaded() {
                try modelStore.ensureDownloadPermitted()
            }
            try modelStore.ensureBaseDirectoryExists()
            // download/load: false — both happen below so download progress can
            // be reported; this init just wires the pyannote backend.
            let config = PyannoteConfig(
                downloadBase: modelStore.baseURL.path,
                modelRepo: WhisperKitModelStore.speakerKitRepo,
                download: false,
                load: false,
                verbose: false
            )
            do {
                kit = try await SpeakerKit(config)
            } catch {
                FileLog.shared.addMessage("[Transcription] SpeakerKit init failed: \(error.localizedDescription)")
                throw TranscriptionError.engineFailure
            }
        }
        guard let kit else { throw TranscriptionError.engineFailure }

        do {
            // The pyannote diarizer is a ModelManager; the cast unlocks download
            // progress that the plain `Diarizer` protocol doesn't expose.
            if let manager = kit.diarizer as? ModelManager {
                if !manager.isLoaded {
                    // Downloading dominates preparation; loading is the last ~20%.
                    try await manager.downloadModels { hubProgress in
                        progress(0.8 * min(max(hubProgress.fractionCompleted, 0), 1))
                    }
                    try await manager.loadModels()
                }
            } else {
                try await kit.ensureModelsLoaded()
            }
        } catch is CancellationError {
            throw TranscriptionError.cancelled
        } catch {
            FileLog.shared.addMessage("[Transcription] SpeakerKit model download/load failed: \(error.localizedDescription)")
            throw TranscriptionError.modelDownloadFailed
        }
        progress(1)
    }

    func diarize(audioFile: URL, maxSpeakers: Int?, progress: @escaping @Sendable (Double) -> Void) async throws -> [SpeakerTurn] {
        guard let kit else {
            // The queue always prepares first; reaching here unprepared is a bug.
            throw TranscriptionError.engineFailure
        }

        // SpeakerKit consumes 16kHz mono samples. WhisperKit's loader decodes in
        // 10-minute chunks to bound peak memory, but the final array is still
        // ~230MB per podcast hour — same order as the ASR stage itself.
        let samples: [Float]
        do {
            samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioFile.path)
        } catch {
            throw TranscriptionError.audioUnreadable
        }
        try Task.checkCancellation()

        let result: DiarizationResult
        do {
            // Default options: `numberOfSpeakers` is deliberately not set — see
            // `capping(turns:to:)` for why the user's cap is applied post-hoc.
            result = try await kit.diarize(audioArray: samples, options: PyannoteDiarizationOptions()) { hubProgress in
                progress(min(max(hubProgress.fractionCompleted, 0), 1))
            }
        } catch is CancellationError {
            throw TranscriptionError.cancelled
        } catch {
            FileLog.shared.addMessage("[Transcription] SpeakerKit diarization failed: \(error.localizedDescription)")
            throw TranscriptionError.engineFailure
        }
        // The pipeline runs to completion once started; honor a queue cancel
        // that arrived mid-run before returning.
        try Task.checkCancellation()

        let turns = result.segments.compactMap { segment -> SpeakerTurn? in
            // Unattributed/overlap regions carry no single speaker id; the
            // aligner handles those gaps (nearest turn or inherit previous).
            guard let speakerId = segment.speaker.speakerId else { return nil }
            let start = TimeInterval(segment.startTime)
            let end = TimeInterval(segment.endTime)
            guard start.isFinite, end.isFinite, end > start else { return nil }
            return SpeakerTurn(speakerId: "SPEAKER_\(speakerId)", start: start, end: end)
        }
        progress(1)
        return Self.capping(turns: turns, to: maxSpeakers)
    }

    // MARK: - Speaker cap

    /// Applies the user's max-speakers cap (nil/0 = auto, no cap).
    ///
    /// SpeakerKit's `numberOfSpeakers` option requests an *exact* cluster count
    /// (it re-clusters with K-Means to hit it), which would force phantom
    /// speakers onto episodes with fewer voices. So diarization always runs in
    /// auto mode, and when it finds more speakers than the cap, only the
    /// most-heard `maxSpeakers` keep their turns — the aligner lets the dropped
    /// spans inherit the surrounding speaker.
    static func capping(turns: [SpeakerTurn], to maxSpeakers: Int?) -> [SpeakerTurn] {
        guard let maxSpeakers, maxSpeakers > 0 else { return turns }

        var totalDurations: [String: TimeInterval] = [:]
        for turn in turns {
            totalDurations[turn.speakerId, default: 0] += turn.end - turn.start
        }
        guard totalDurations.count > maxSpeakers else { return turns }

        let keep = Set(totalDurations.sorted { $0.value > $1.value }.prefix(maxSpeakers).map(\.key))
        return turns.filter { keep.contains($0.speakerId) }
    }
}
