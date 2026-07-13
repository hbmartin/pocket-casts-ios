#if os(iOS)
import AVFoundation
import Foundation
import Speech

/// `TranscriptionEngineMode.appleBuiltIn`: on-device ASR via the iOS 26
/// `SpeechAnalyzer`/`SpeechTranscriber` stack. Ships no diarizer — pair with a
/// `SpeakerDiarizing` implementation, or run with empty turns for untagged cues.
///
/// Wrapped in `#if os(iOS)` so the module still builds for host-side
/// (macOS) `swift test` runs, which exercise the pure alignment/serialization code.
public struct AppleSpeechEngine: SpeechToTextEngine {
    public let id = "apple.speechanalyzer"

    /// How often the asset-download progress is sampled while installing.
    private static let progressSampleInterval: Duration = .milliseconds(250)

    public init() {}

    // MARK: - SpeechToTextEngine

    public func prepare(locale: Locale?, progress: @escaping @Sendable (Double) -> Void) async throws {
        let resolved = try await Self.resolveLocale(preferring: locale)
        let transcriber = Self.makeTranscriber(locale: resolved)

        let status = await AssetInventory.status(forModules: [transcriber])
        guard status != .unsupported else { throw TranscriptionError.engineFailure }

        // Reserving keeps this locale's assets installed across the system's asset
        // housekeeping. Hitting the reservation cap is not fatal — the install
        // below can still succeed for this run.
        _ = try? await AssetInventory.reserve(locale: resolved)

        let request: AssetInstallationRequest?
        do {
            request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
        } catch is CancellationError {
            throw TranscriptionError.cancelled
        } catch {
            throw TranscriptionError.modelDownloadFailed
        }

        guard let request else {
            // Nothing to install — assets are already on device.
            progress(1)
            return
        }

        let installationProgress = request.progress
        let sampler = Task {
            while true {
                progress(min(max(installationProgress.fractionCompleted, 0), 1))
                do {
                    try await Task.sleep(for: Self.progressSampleInterval)
                } catch {
                    break
                }
            }
        }
        defer { sampler.cancel() }

        do {
            try await request.downloadAndInstall()
        } catch is CancellationError {
            throw TranscriptionError.cancelled
        } catch {
            throw TranscriptionError.modelDownloadFailed
        }
        progress(1)
    }

    public func transcribe(audioFile: URL, language: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> [ASRSegment] {
        let locale = try await Self.resolveLocale(preferring: language.map(Locale.init(identifier:)))
        let transcriber = Self.makeTranscriber(locale: locale)

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: audioFile)
        } catch {
            throw TranscriptionError.audioUnreadable
        }
        let sampleRate = file.processingFormat.sampleRate
        let audioDuration = sampleRate > 0 ? Double(file.length) / sampleRate : 0

        // Start draining results before feeding audio so nothing backs up. The
        // stream finishes when the analyzer finalizes below.
        let collector = Task {
            var segments: [ASRSegment] = []
            for try await result in transcriber.results {
                try Task.checkCancellation()
                guard let segment = Self.makeSegment(from: result) else { continue }
                segments.append(segment)
                if audioDuration > 0 {
                    progress(min(max(segment.end / audioDuration, 0), 1))
                }
            }
            return segments
        }

        do {
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            _ = try await analyzer.analyzeSequence(from: file)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            collector.cancel()
            throw Self.mapped(error)
        }

        do {
            let segments = try await collector.value
            progress(1)
            return segments.sorted { $0.start < $1.start }
        } catch {
            throw Self.mapped(error)
        }
    }

    // MARK: - Locale resolution

    /// Resolves the transcription locale against `SpeechTranscriber`'s supported
    /// set: the language override first, then the device locale. Throws
    /// `.engineFailure` when neither is supported on this device.
    static func resolveLocale(preferring preferred: Locale?) async throws -> Locale {
        var candidates: [Locale] = []
        if let preferred {
            candidates.append(preferred)
        }
        candidates.append(Locale.current)

        for candidate in candidates {
            if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: candidate) {
                return supported
            }
        }
        throw TranscriptionError.engineFailure
    }

    // MARK: - Helpers

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [], // Final results only — no volatile/alternative noise.
            attributeOptions: [.audioTimeRange]
        )
    }

    /// Converts one time-indexed transcriber result into an `ASRSegment`, pulling
    /// word-level timings from the `audioTimeRange` runs of the attributed text.
    private static func makeSegment(from result: SpeechTranscriber.Result) -> ASRSegment? {
        let attributed = result.text
        let text = String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var words: [TranscriptWord] = []
        for run in attributed.runs {
            guard let timeRange = run.audioTimeRange else { continue }
            let start = timeRange.start.seconds
            let end = timeRange.end.seconds
            guard start.isFinite, end.isFinite else { continue }
            let runText = String(attributed[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !runText.isEmpty else { continue }
            words.append(TranscriptWord(text: runText, start: start, end: max(end, start)))
        }

        var start = result.range.start.seconds
        var end = result.range.end.seconds
        if !start.isFinite || !end.isFinite {
            // Fall back to word timings when the segment range is invalid.
            guard let first = words.first, let last = words.last else { return nil }
            start = first.start
            end = last.end
        }
        return ASRSegment(text: text, start: start, end: max(end, start), words: words.isEmpty ? nil : words)
    }

    private static func mapped(_ error: Error) -> TranscriptionError {
        switch error {
        case is CancellationError:
            .cancelled
        case let transcriptionError as TranscriptionError:
            transcriptionError
        default:
            .engineFailure
        }
    }
}
#endif
