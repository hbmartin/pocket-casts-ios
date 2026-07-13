import Foundation
import PocketCastsTranscription
import PocketCastsUtils
@preconcurrency import WhisperKit
// Scoped import: the WhisperKit CLASS shadows the module name, so
// `WhisperKit.TranscriptionSegment` resolves against the class and fails;
// this brings the segment type in under its bare name instead.
@preconcurrency import struct WhisperKit.TranscriptionSegment

/// `TranscriptionEngineMode.localModel`: on-device ASR through WhisperKit's
/// CoreML Whisper models (argmax-oss-swift). An actor because the `WhisperKit`
/// instance is a non-Sendable mutable class; all touches stay isolated here.
///
/// No unit tests — exercising this engine needs real CoreML models — so it stays
/// a thin adapter: model resolution lives in `WhisperKitModelStore`, result
/// mapping in the pure static helpers below.
actor WhisperKitEngine: SpeechToTextEngine {
    nonisolated let id: String

    private let variant: String
    private let modelStore: WhisperKitModelStore
    private var whisperKit: WhisperKit?

    init(variant: String = Settings.transcriptionWhisperModel(),
         modelStore: WhisperKitModelStore = WhisperKitModelStore()) {
        self.variant = variant
        self.modelStore = modelStore
        id = "whisperkit.\(variant)"
    }

    // MARK: - SpeechToTextEngine

    /// Resolves the selected variant (downloading it if missing, behind the
    /// cellular gate) and loads the CoreML models. The `locale` parameter is
    /// unused: Whisper models are multilingual, so language is applied per
    /// transcription via `DecodingOptions`.
    func prepare(locale: Locale?, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard whisperKit == nil else {
            progress(1)
            return
        }

        let modelFolder: URL
        if modelStore.isDownloaded(variant: variant) {
            modelFolder = modelStore.modelFolderURL(variant: variant)
        } else {
            // Downloading dominates preparation; model loading is the last ~10%.
            modelFolder = try await modelStore.download(variant: variant) { progress(0.9 * $0) }
        }
        try Task.checkCancellation()

        // download: false — the model folder is already resolved above. The first
        // run per model family may still fetch its ~2MB tokenizer from the Hub;
        // pointing tokenizerFolder at the store keeps it inside the accounted
        // (and backup-excluded) cache. That small fetch rides along with prepare —
        // the cellular gate covered the model download itself.
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            tokenizerFolder: modelStore.baseURL,
            verbose: false,
            load: true,
            download: false
        )
        do {
            whisperKit = try await WhisperKit(config)
        } catch is CancellationError {
            throw TranscriptionError.cancelled
        } catch {
            FileLog.shared.addMessage("[Transcription] WhisperKit model load failed (\(variant)): \(error.localizedDescription)")
            throw TranscriptionError.engineFailure
        }
        progress(1)
    }

    func transcribe(audioFile: URL, language: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> [ASRSegment] {
        guard let whisperKit else {
            // The queue always prepares first; reaching here unprepared is a bug.
            throw TranscriptionError.engineFailure
        }
        guard FileManager.default.fileExists(atPath: audioFile.path) else {
            throw TranscriptionError.audioUnreadable
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: Self.whisperLanguage(from: language),
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            wordTimestamps: true,
            chunkingStrategy: .vad
        )

        // WhisperKit tracks overall completion on a Foundation `Progress` whose
        // unit count is the VAD chunk count; sample it from the per-decoding-loop
        // callback. Held at <1 until mapping below finishes.
        let overallProgress = whisperKit.progress
        let callback: TranscriptionCallback = { _ in
            progress(min(max(overallProgress.fractionCompleted, 0), 0.99))
            // Returning false stops decoding at the next loop; WhisperKit also
            // checks Task cancellation between windows, so queue cancels land
            // promptly on long files either way.
            return Task.isCancelled ? false : nil
        }

        let results: [TranscriptionResult]
        do {
            results = try await whisperKit.transcribe(audioPath: audioFile.path,
                                                      decodeOptions: options,
                                                      callback: callback)
        } catch is CancellationError {
            throw TranscriptionError.cancelled
        } catch let error as WhisperError {
            FileLog.shared.addMessage("[Transcription] WhisperKit transcribe failed: \(error.localizedDescription)")
            if case .loadAudioFailed = error {
                throw TranscriptionError.audioUnreadable
            }
            throw TranscriptionError.engineFailure
        } catch {
            FileLog.shared.addMessage("[Transcription] WhisperKit transcribe failed: \(error.localizedDescription)")
            throw TranscriptionError.engineFailure
        }
        // An early stop (callback returned false on cancellation) yields partial
        // results without throwing — never let those complete the job.
        try Task.checkCancellation()

        // Merging normalizes per-chunk results into one segment list with
        // absolute (whole-file) timestamps, matching what the aligner expects.
        let merged = TranscriptionUtilities.mergeTranscriptionResults(results)
        let segments = merged.segments
            .sorted { $0.start < $1.start }
            .compactMap(Self.makeSegment(from:))
        guard !segments.isEmpty else { throw TranscriptionError.engineFailure }
        progress(1)
        return segments
    }

    // MARK: - Mapping

    /// Converts a WhisperKit segment (Float seconds, whisper's space-prefixed
    /// word tokens) into the module's `ASRSegment`.
    private static func makeSegment(from segment: TranscriptionSegment) -> ASRSegment? {
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var words: [TranscriptWord] = []
        for timing in segment.words ?? [] {
            let word = timing.word.trimmingCharacters(in: .whitespacesAndNewlines)
            let start = TimeInterval(timing.start)
            let end = TimeInterval(timing.end)
            guard !word.isEmpty, start.isFinite, end.isFinite else { continue }
            words.append(TranscriptWord(text: word, start: start, end: max(end, start)))
        }

        let start = TimeInterval(segment.start)
        let end = TimeInterval(segment.end)
        guard start.isFinite, end.isFinite else { return nil }
        return ASRSegment(text: text, start: start, end: max(end, start), words: words.isEmpty ? nil : words)
    }

    /// Whisper wants bare ISO 639-1 codes ("en"); the app stores BCP-47 tags
    /// ("en-US"). nil stays nil (auto-detect).
    private static func whisperLanguage(from tag: String?) -> String? {
        guard let tag, !tag.isEmpty else { return nil }
        return Locale(identifier: tag).language.languageCode?.identifier ?? String(tag.prefix(2)).lowercased()
    }
}
