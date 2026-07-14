import AVFoundation
import Foundation
import PocketCastsUtils
import SoundAnalysis
import Synchronization

/// Runs the system sound classifier over the trim-silence read stream and
/// records speech-confidence results by source frame range, so the trim gate
/// can retrospectively veto a trim that would drop speech.
///
/// Analysis runs on its own serial queue (SoundAnalysis is not realtime-safe);
/// the read loop only copies channel 0 and dispatches, then later asks
/// non-blockingly whether speech was detected. Results lag by up to the window
/// duration plus inference time, which is fine because trim decisions are
/// themselves retrospective — silent buffers sit on the gap stack before
/// anything is dropped.
///
/// Frame positions must increase monotonically; recreate the analyzer after a
/// seek. All public methods are safe to call from the read thread.
/// @unchecked Sendable: results are Mutex-guarded; all other stored state is immutable after init.
nonisolated final class TrimVoiceActivityAnalyzer: @unchecked Sendable {
    private struct SpeechResult {
        let frameRange: Range<Int64>
        let confidence: Float
        /// Confidence of the classifier's "music" class over the same window
        /// (drives adaptive effects switching; 0 when the class is absent).
        let musicConfidence: Float
    }

    /// How far analysis may fall behind the read position before results stop
    /// counting as coverage (seconds).
    private static let stalenessWindow: TimeInterval = 2
    private static let maxStoredResults = 64

    /// SoundAnalysis window configuration (seconds). With `overlapFactor` 0.5 the
    /// classifier hops half a window at a time, so the newest position a completed
    /// window can END at trails the live read head by up to a full window plus one hop.
    private static let windowDuration: TimeInterval = 0.5
    private static let windowOverlapFactor = 0.5

    /// How many frames behind the live read head callers should query
    /// (`classification(atFramePosition:)` / `speechConfidence(atFramePosition:)`).
    /// Results are stored as half-open ranges, so a completed window can never
    /// *contain* the read head itself — every window's upperBound is at or behind
    /// it. Lagging the query by one window plus one hop lands it inside the
    /// newest window that has had time to complete.
    let queryLagFrames: Int64

    private let sampleRate: Double
    private let monoFormat: AVAudioFormat
    private let analyzer: SNAudioStreamAnalyzer
    private let observer: Observer
    private let analysisQueue = DispatchQueue(label: "au.com.pocketcasts.TrimVAD", qos: .userInitiated, autoreleaseFrequency: .workItem)

    /// Recorded speech results and the newest analyzed frame, mutated on the analysis
    /// queue and read from the read thread. A `Mutex` makes "only touched under the lock"
    /// compiler-enforced (was an `NSLock` + separate `var`s).
    private struct ResultStore {
        var results = [SpeechResult]()
        var latestAnalyzedFrame: Int64 = 0
    }
    private let store = Mutex(ResultStore())

    /// The observer object SoundAnalysis calls back on the analysis queue.
    /// Kept separate so the analyzer never retains its owner.
    /// @unchecked Sendable: onResult is assigned once in the owner's init before analysis starts; callbacks arrive serially on the analysis queue.
    private final class Observer: NSObject, SNResultsObserving, @unchecked Sendable {
        var onResult: ((_ startSeconds: Double, _ endSeconds: Double, _ confidence: Float, _ musicConfidence: Float) -> Void)?

        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let classification = result as? SNClassificationResult else { return }
            let confidence = Float(classification.classification(forIdentifier: "speech")?.confidence ?? 0)
            // Same classifier pass exposes ~300 classes; reading "music" costs no
            // extra inference and drives adaptive effects switching.
            let musicConfidence = Float(classification.classification(forIdentifier: "music")?.confidence ?? 0)
            let start = classification.timeRange.start.seconds
            let duration = classification.timeRange.duration.seconds
            guard start.isFinite, duration.isFinite, duration > 0 else { return }
            onResult?(start, start + duration, confidence, musicConfidence)
        }

        func request(_ request: SNRequest, didFailWithError error: Error) {
            FileLog.shared.addMessage("[TrimVAD] analysis failed: \(error.localizedDescription)")
        }
    }

    /// Throws when the built-in classifier is unavailable; callers fall back to
    /// the heuristic discriminator.
    init(sampleRate: Double) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
            throw NSError(domain: "TrimVoiceActivityAnalyzer", code: 1, userInfo: [NSLocalizedDescriptionKey: "invalid format"])
        }

        self.sampleRate = sampleRate
        monoFormat = format
        analyzer = SNAudioStreamAnalyzer(format: format)
        observer = Observer()

        let hopDuration = Self.windowDuration * (1 - Self.windowOverlapFactor)
        queryLagFrames = Int64((Self.windowDuration + hopDuration) * sampleRate)

        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: Self.windowDuration, preferredTimescale: CMTimeScale(sampleRate))
        request.overlapFactor = Self.windowOverlapFactor
        try analyzer.add(request, withObserver: observer)

        observer.onResult = { [weak self] startSeconds, endSeconds, confidence, musicConfidence in
            self?.record(startSeconds: startSeconds, endSeconds: endSeconds, confidence: confidence, musicConfidence: musicConfidence)
        }
    }

    /// Internal (not private) so tests can seed synthetic classifier results.
    func record(startSeconds: Double, endSeconds: Double, confidence: Float, musicConfidence: Float) {
        let frameRange = Int64(startSeconds * sampleRate) ..< Int64(endSeconds * sampleRate)
        store.withLock { store in
            store.results.append(SpeechResult(frameRange: frameRange, confidence: confidence, musicConfidence: musicConfidence))
            if store.results.count > Self.maxStoredResults {
                store.results.removeFirst(store.results.count - Self.maxStoredResults)
            }
            store.latestAnalyzedFrame = max(store.latestAnalyzedFrame, frameRange.upperBound)
        }
    }

    /// Copies channel 0 of the buffer and queues it for analysis. Non-blocking.
    func append(_ buffer: AVAudioPCMBuffer, atFramePosition framePosition: Int64) {
        guard let source = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: source, count: frameLength))

        // Only Sendable sample values cross the queue boundary. The non-Sendable
        // AVAudioPCMBuffer and SNAudioStreamAnalyzer remain confined to analysisQueue.
        analysisQueue.async { [self] in
            guard let copy = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(samples.count)),
                  let destination = copy.floatChannelData?[0] else { return }

            copy.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { source in
                guard let baseAddress = source.baseAddress else { return }
                destination.update(from: baseAddress, count: source.count)
            }
            analyzer.analyze(copy, atAudioFramePosition: framePosition)
        }
    }

    /// The freshest speech confidence covering `framePosition`, or nil when no
    /// non-stale result covers it (callers degrade to the heuristic).
    func speechConfidence(atFramePosition framePosition: Int64) -> Float? {
        store.withLock { store in
            guard isFresh(around: framePosition, latestAnalyzedFrame: store.latestAnalyzedFrame) else { return nil }
            return store.results.last(where: { $0.frameRange.contains(framePosition) })?.confidence
        }
    }

    /// The freshest speech/music confidence pair covering `framePosition`, or nil
    /// when no non-stale result covers it (the adaptive classifier then holds its
    /// current state).
    func classification(atFramePosition framePosition: Int64) -> (speech: Float, music: Float)? {
        store.withLock { store in
            guard isFresh(around: framePosition, latestAnalyzedFrame: store.latestAnalyzedFrame),
                  let result = store.results.last(where: { $0.frameRange.contains(framePosition) }) else { return nil }
            return (result.confidence, result.musicConfidence)
        }
    }

    /// Whether any (non-stale) result overlapping the range detects speech above
    /// `threshold`. Returns nil when the range has no coverage at all — the
    /// caller should then not veto.
    func speechDetected(inFrameRange range: Range<Int64>, aboveConfidence threshold: Float) -> Bool? {
        store.withLock { store in
            let overlapping = store.results.filter { $0.frameRange.overlaps(range) }
            guard !overlapping.isEmpty else { return nil }
            return overlapping.contains { $0.confidence > threshold }
        }
    }

    private func isFresh(around framePosition: Int64, latestAnalyzedFrame: Int64) -> Bool {
        latestAnalyzedFrame >= framePosition - Int64(Self.stalenessWindow * sampleRate)
    }

    /// Flushes pending analysis. Call before discarding the analyzer (seek or
    /// shutdown) — stream analyzers cannot rewind, so seeks recreate it.
    func finish() {
        analysisQueue.async { [self] in
            analyzer.completeAnalysis()
        }
    }
}
