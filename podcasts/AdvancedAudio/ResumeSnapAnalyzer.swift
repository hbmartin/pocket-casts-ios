import AVFoundation
import Foundation
import PocketCastsUtils

/// Seam for Smart Resume's silence analysis so PlaybackCatchUpHelper can be
/// tested with a mock analyzer.
nonisolated protocol ResumeSnapAnalyzing: Sendable {
    /// Finds the inter-word silence nearest each target time in the downloaded
    /// file, calling `completion` on the main actor with a target → snapped-time
    /// dictionary. Targets with no usable gap are absent from the result.
    func snapCandidates(for fileURL: URL, targets: [TimeInterval], completion: @escaping @MainActor @Sendable ([TimeInterval: TimeInterval]) -> Void)
}

/// Decodes a short PCM window around each requested resume target on a
/// background queue and snaps the target to the nearest inter-word silence via
/// `SilenceGapFinder`. Mirrors `EpisodeLoudnessScanner`'s serial-queue shape so
/// at most one decode runs at a time; a full three-target pass over a downloaded
/// file takes on the order of 100ms, which comfortably beats the five-minute
/// minimum before any snap candidate is consumed.
nonisolated final class ResumeSnapAnalyzer: ResumeSnapAnalyzing, Sendable {
    /// Serial utility queue: one analysis at a time keeps CPU/battery bounded.
    private let analysisQueue = DispatchQueue(label: "au.com.pocketcasts.ResumeSnapAnalysis", qos: .utility, autoreleaseFrequency: .workItem)
    private let parameters: SilenceGapFinder.Parameters

    init(parameters: SilenceGapFinder.Parameters = SilenceGapFinder.Parameters()) {
        self.parameters = parameters
    }

    func snapCandidates(for fileURL: URL, targets: [TimeInterval], completion: @escaping @MainActor @Sendable ([TimeInterval: TimeInterval]) -> Void) {
        // Strong capture: an in-flight analysis must deliver its completion even
        // if the owner releases the analyzer while the queue item waits — a weak
        // capture here silently swallows the callback.
        analysisQueue.async {
            let snaps = self.snappedTimes(in: fileURL, targets: targets)
            Task { @MainActor in
                completion(snaps)
            }
        }
    }

    /// Synchronous analysis core; internal so tests can drive it directly
    /// against synthesized audio files.
    func snappedTimes(in fileURL: URL, targets: [TimeInterval]) -> [TimeInterval: TimeInterval] {
        guard !targets.isEmpty else { return [:] }

        guard let audioFile = try? AVAudioFile(forReading: fileURL, commonFormat: .pcmFormatFloat32, interleaved: false) else {
            FileLog.shared.addMessage("[SmartResume] could not open \(fileURL.lastPathComponent) for analysis")
            return [:]
        }

        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, audioFile.length > 0 else { return [:] }

        let windowFrames = AVAudioFrameCount((parameters.windowBefore + parameters.windowAfter) * sampleRate)
        guard windowFrames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: windowFrames) else { return [:] }

        var snaps = [TimeInterval: TimeInterval]()
        for target in targets {
            let windowStart = max(0, target - parameters.windowBefore)
            let startFrame = AVAudioFramePosition(windowStart * sampleRate)
            guard startFrame < audioFile.length else { continue }

            audioFile.framePosition = startFrame
            buffer.frameLength = 0
            do {
                try audioFile.read(into: buffer, frameCount: windowFrames)
            } catch {
                // reads throw at EOF on some formats; analyze what was decoded
            }
            guard buffer.frameLength > 0 else { continue }

            let levelsDB = hopLevelsDB(from: buffer, sampleRate: sampleRate)
            if let snap = SilenceGapFinder.snapTime(levelsDB: levelsDB, windowStart: windowStart, hopDuration: parameters.hopDuration, target: target, parameters: parameters) {
                snaps[target] = snap
            }
        }

        FileLog.shared.addMessage("[SmartResume] analyzed \(fileURL.lastPathComponent): snapped \(snaps.count)/\(targets.count) targets")
        return snaps
    }

    /// RMS level in dBFS for each hop-sized slice of the buffer, averaged
    /// across channels.
    private func hopLevelsDB(from buffer: AVAudioPCMBuffer, sampleRate: Double) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }

        let channelCount = Int(buffer.format.channelCount)
        let totalFrames = Int(buffer.frameLength)
        let hopFrames = max(1, Int(parameters.hopDuration * sampleRate))
        guard channelCount > 0, totalFrames >= hopFrames else { return [] }

        var levels = [Float]()
        levels.reserveCapacity(totalFrames / hopFrames)

        var frame = 0
        while frame + hopFrames <= totalFrames {
            var rmsSum: Float = 0
            for channel in 0 ..< channelCount {
                let hopBuffer = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(hopFrames * MemoryLayout<Float32>.stride),
                    mData: UnsafeMutableRawPointer(channelData[channel] + frame)
                )
                rmsSum += AudioUtils.calculateRms(hopBuffer)
            }

            let rms = rmsSum / Float(channelCount)
            levels.append(20 * log10(max(rms, 1e-6))) // clamp digital silence to -120dB
            frame += hopFrames
        }

        return levels
    }
}
