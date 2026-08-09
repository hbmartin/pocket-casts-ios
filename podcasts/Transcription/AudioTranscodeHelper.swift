import AVFoundation
import Foundation
import PocketCastsTranscription
import PocketCastsUtils
import Synchronization

/// Shrinks episode audio for upload-based remote transcription providers:
/// re-encodes to mono AAC (~48kbps) in an .m4a container, written to a temp
/// file the queue deletes after the upload.
///
/// Speech survives 48kbps mono easily, and the size drop is what makes provider
/// caps workable (~21MB/hour vs ~60MB/hour for typical stereo MP3 podcasts).
/// Sources that are already small .m4a files pass through untouched.
nonisolated struct AudioTranscodeHelper: Sendable {
    struct Output: Sendable {
        let url: URL
        let mimeType: String
        /// True when `url` is a temp file the caller must delete after use.
        let isTemporary: Bool
    }

    /// An .m4a at or under this size is uploaded as-is — re-encoding it would
    /// burn battery to save nothing that matters.
    static let passthroughLimitBytes: Int64 = 24 * 1024 * 1024

    private static let outputBitRate = 48_000

    /// Container extensions that are already AAC-in-MP4 and can pass through.
    private static let passthroughExtensions: Set<String> = ["m4a", "mp4", "m4b"]

    /// Returns an upload-ready audio file for `sourceURL`. The transcode loop
    /// runs on AVFoundation's own queue; cancellation is coarse — the caller's
    /// `Task.checkCancellation()` before/after bounds a stale job to one encode.
    func transcodeForUpload(sourceURL: URL) async throws -> Output {
        try Task.checkCancellation()
        if Self.passthroughExtensions.contains(sourceURL.pathExtension.lowercased()),
           let size = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? Int64,
           size <= Self.passthroughLimitBytes {
            try Task.checkCancellation()
            return Output(url: sourceURL, mimeType: "audio/mp4", isTemporary: false)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-upload-\(UUID().uuidString).m4a")

        do {
            try await Self.encodeToMonoAAC(asset: AVURLAsset(url: sourceURL), outputURL: outputURL, bitRate: Self.outputBitRate)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: outputURL)
                throw CancellationError()
            }
            throw TranscriptionError.audioUnreadable
        }

        return Output(url: outputURL, mimeType: "audio/mp4", isTemporary: true)
    }

    /// Encodes any asset's audio to mono AAC in an `.m4a` at `outputURL`.
    ///
    /// Split out of `transcodeForUpload` so Read Aloud can reuse it over an
    /// `AVMutableComposition` of synthesized chunks (ADR-0019) instead of a file
    /// on disk — the reader/writer loop never cared where the asset came from,
    /// and duplicating it would mean two copies of the ready-callback and
    /// single-shot-continuation handling to keep correct.
    ///
    /// Mono is right for both callers: speech, and smaller files.
    static func encodeToMonoAAC(asset: AVAsset, outputURL: URL, bitRate: Int) async throws {
        let audioTracks: [AVAssetTrack]
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw AudioEncodeError.failed
        }
        try Task.checkCancellation()
        guard let audioTrack = audioTracks.first else { throw AudioEncodeError.failed }

        try? FileManager.default.removeItem(at: outputURL)

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        } catch {
            throw AudioEncodeError.failed
        }

        // Decode to PCM; the writer input converts (downmix + resample + AAC).
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
        ])
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw AudioEncodeError.failed }
        reader.add(readerOutput)

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: bitRate,
        ])
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { throw AudioEncodeError.failed }
        writer.add(writerInput)

        guard reader.startReading() else { throw AudioEncodeError.failed }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw AudioEncodeError.failed
        }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "au.com.pocketcasts.transcription.transcode")
        // The ready-callback runs on `queue`; the AVFoundation session objects are
        // used exclusively from that callback while it is installed, so boxing them
        // across the (possibly @Sendable) closure boundary is safe.
        let session = UncheckedSendable((reader: reader, output: readerOutput, input: writerInput))
        // The ready-callback can fire again around markAsFinished; the flag keeps
        // the continuation resume single-shot.
        let finished = Mutex(false)
        // Set by the task-cancellation handler; the ready-callback polls it so a
        // cancelled task stops encoding instead of running the file to the end.
        let cancelled = Mutex(false)
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.value.input.requestMediaDataWhenReady(on: queue) {
                    let (reader, output, input) = session.value
                    guard finished.withLock({ !$0 }) else { return }
                    while input.isReadyForMoreMediaData {
                        if cancelled.withLock({ $0 }) {
                            finished.withLock { $0 = true }
                            reader.cancelReading()
                            input.markAsFinished()
                            continuation.resume()
                            return
                        }
                        guard let sampleBuffer = output.copyNextSampleBuffer() else {
                            finished.withLock { $0 = true }
                            input.markAsFinished()
                            continuation.resume()
                            return
                        }
                        if !input.append(sampleBuffer) {
                            finished.withLock { $0 = true }
                            reader.cancelReading()
                            input.markAsFinished()
                            continuation.resume()
                            return
                        }
                    }
                }
            }
        } onCancel: {
            cancelled.withLock { $0 = true }
        }

        if cancelled.withLock({ $0 }) {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        }

        await writer.finishWriting()

        if Task.isCancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        }

        // Both sides must have finished cleanly — a reader that stopped early
        // (failed OR cancelled) with a completed writer is a truncated file.
        guard reader.status == .completed, writer.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioEncodeError.failed
        }
    }
}

/// The shared encoder's only failure. Callers map it onto their own taxonomy —
/// `TranscriptionError.audioUnreadable` for uploads, `ReadAloudError.assemblyFailed`
/// for narrations — so neither feature's error surface leaks into the other's.
nonisolated enum AudioEncodeError: Error, Sendable {
    case failed
}
