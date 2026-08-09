import AVFoundation
import PocketCastsDataModel
import Combine
import SwiftUI

@MainActor
class ClipPlaybackManager: ObservableObject {

    static let shared = ClipPlaybackManager()

    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval?
    @Published var duration: TimeInterval = 0

    private let normalPlaybackManager = PlaybackManager.shared
    private let downloadManager = DownloadManager.shared

    private var avPlayer: AVPlayer?
    private var timeObserverToken: Any?
    private var isSeeking: Bool = false
    private var cancellables = Set<AnyCancellable>()

    @ObservedObject var clipTime = ClipTime(start: 0, end: 0)

    func play(episode: BaseEpisode, clipTime: ObservedObject<ClipTime>) {
        if avPlayer != nil {
            stop()
            avPlayer = nil
        }

        guard let playerItem = downloadManager.downloadParallelToStream(of: episode) else {
            return
        }

        // Do not interrupt ordinary episode playback unless the clip has a
        // playable item. A failed parallel download should leave the user's
        // current listening session untouched.
        normalPlaybackManager.pause()

        avPlayer = AVPlayer(playerItem: playerItem)

        let startTime = clipTime.projectedValue.start.wrappedValue
        let endTime = clipTime.projectedValue.end.wrappedValue
        let playbackTime = clipTime.projectedValue.playback.wrappedValue

        let playbackCMTime = CMTime(seconds: playbackTime, preferredTimescale: .audio)

        normalPlaybackManager.activateAudioSession(completion: { [weak self] _ in
            if Thread.current.isMainThread {
                self?.startPlayer(at: playbackCMTime)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.startPlayer(at: playbackCMTime)
                }
            }
        })

        isPlaying = true
        duration = endTime - startTime

        self._clipTime = clipTime

        $currentTime.sink(receiveValue: { currentTime in
            if let currentTime, currentTime > 0 {
                clipTime.wrappedValue.playback = currentTime
            }
        }).store(in: &cancellables)
    }

    func startPlayer(at playbackCMTime: CMTime) {
        avPlayer?.seek(to: playbackCMTime)
        avPlayer?.play()
        setupTimeObserver()
        observePlaybackEnd()
    }

    func seek(to time: CMTime) {
        isSeeking = true
        avPlayer?.seek(to: time) { [weak self] _ in
            Task { @MainActor in
                self?.isSeeking = false
            }
        }
    }

    func stop() {
        cancellables.removeAll()
        avPlayer?.pause()
        isPlaying = false
        currentTime = 0
        duration = 0
        removeTimeObserver()
    }

    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = avPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // Delivered on the main queue per the observer's queue parameter
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                // Loops back to the beginning at end of clip range
                guard time.seconds < self.clipTime.end else {
                    self.isSeeking = true
                    self.avPlayer?.seek(to: CMTime(seconds: self.clipTime.start, preferredTimescale: .audio)) { [weak self] _ in
                        Task { @MainActor in
                            guard let self else {
                                return
                            }
                            self.isSeeking = false
                            self.avPlayer?.pause()
                            self.currentTime = self.clipTime.start
                        }
                    }
                    return
                }

                if !self.isSeeking {
                    self.currentTime = time.seconds
                }
            }
        }
    }

    private func removeTimeObserver() {
        if let token = timeObserverToken {
            avPlayer?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    private func observePlaybackEnd() {
        avPlayer?.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                self?.isPlaying = (status == .playing || status == .waitingToPlayAtSpecifiedRate)
            }
            .store(in: &cancellables)
    }
}
