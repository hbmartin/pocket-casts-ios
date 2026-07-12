import AVFoundation
import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import Synchronization

/// Measures the integrated BS.1770 loudness of downloaded episodes on a
/// background queue and caches it per episode, so VoiceBoostN can seed its gain
/// instantly instead of adapting over the first seconds of playback.
///
/// Triggered from episode-download notifications and from EffectsPlayer when it
/// loads an episode with no cached measurement.
nonisolated final class EpisodeLoudnessScanner: Sendable {
    static let shared = EpisodeLoudnessScanner()

    private static let framesPerRead: AVAudioFrameCount = 32768

    /// Serial utility queue: one scan at a time keeps CPU/battery bounded.
    private let scanQueue = DispatchQueue(label: "au.com.pocketcasts.LoudnessScan", qos: .utility, autoreleaseFrequency: .workItem)
    private let inFlight = Mutex(Set<String>())

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(episodeDownloaded(_:)), name: Constants.Notifications.episodeDownloaded, object: nil)
    }

    @objc private func episodeDownloaded(_ notification: Notification) {
        guard let episodeUuid = notification.object as? String else { return }
        scanIfNeeded(episodeUuid: episodeUuid)
    }

    func scanIfNeeded(episodeUuid: String) {
        let alreadyQueued = inFlight.withLock { !$0.insert(episodeUuid).inserted }
        guard !alreadyQueued else { return }

        scanQueue.async { [weak self] in
            guard let self else { return }
            self.scan(episodeUuid: episodeUuid)
            self.inFlight.withLock { _ = $0.remove(episodeUuid) }
        }
    }

    private func scan(episodeUuid: String) {
        guard let episode = DataManager.sharedManager.findBaseEpisode(uuid: episodeUuid),
              episode.downloaded(pathFinder: DownloadManager.shared),
              DataManager.sharedManager.findLoudness(episode: episode) == 0 else { return }

        let path = episode.pathToDownloadedFile(pathFinder: DownloadManager.shared)
        guard let audioFile = try? AVAudioFile(forReading: URL(fileURLWithPath: path), commonFormat: .pcmFormatFloat32, interleaved: false) else {
            FileLog.shared.addMessage("[LoudnessScan] could not open \(episodeUuid) for measurement")
            return
        }

        let format = audioFile.processingFormat
        guard let meter = VBN_MeterCreate(format.sampleRate, Int32(format.channelCount)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.framesPerRead) else { return }
        defer { VBN_MeterDestroy(meter) }

        var frameCount: Int64 = 0
        do {
            while true {
                try audioFile.read(into: buffer, frameCount: Self.framesPerRead)
                if buffer.frameLength == 0 { break }
                frameCount += Int64(buffer.frameLength)

                if let channelData = buffer.floatChannelData {
                    var channelPointers: [UnsafePointer<Float>?] = (0 ..< Int(format.channelCount)).map { UnsafePointer(channelData[$0]) }
                    channelPointers.withUnsafeMutableBufferPointer { pointers in
                        VBN_MeterProcess(meter, pointers.baseAddress, Int32(buffer.frameLength), Int32(format.channelCount))
                    }
                }
            }
        } catch {
            // reads throw at EOF on some formats; treat what we got as the file
        }

        let lufs = VBN_MeterIntegratedLUFS(meter)
        guard lufs.isFinite, lufs < 0, frameCount > 0 else {
            FileLog.shared.addMessage("[LoudnessScan] no measurable audio in \(episodeUuid)")
            return
        }

        DataManager.sharedManager.saveLoudness(episode: episode, loudness: Double(lufs))
        // we have the frame count in hand; cache it too if it's missing
        if DataManager.sharedManager.findFrameCount(episode: episode) == 0, audioFile.length > 0 {
            DataManager.sharedManager.saveFrameCount(episode: episode, frameCount: audioFile.length)
        }
        FileLog.shared.addMessage("[LoudnessScan] \(episodeUuid) measured at \(String(format: "%.1f", lufs)) LUFS")
    }
}
