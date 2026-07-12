@preconcurrency import AVFoundation
import CoreAudioTypes
import Foundation
import os
import PocketCastsDataModel
import PocketCastsUtils

/// AVPlayer wrapper driven by PlaybackManager's queues plus KVO/main callbacks;
/// mutable state is confined to that flow by design.
/// @unchecked Sendable: mutable state is confined to PlaybackManager's playback queue and KVO/main callbacks as described above.
nonisolated final class DefaultPlayer: PlaybackProtocol, Hashable, @unchecked Sendable {
    private var audioMix: AVAudioMix?
    private var assetTrack: AVAssetTrack?
    private var assetTrackLoadTask: Task<Void, Never>?
    private var loadingPlayerItem: AVPlayerItem?

    private(set) var player: AVPlayer?

    private var requiredPlaybackRate: Double = 0
    private var shouldKeepPlaying = false
    private var volumeBoostEnabled = false

    private var lastBackgroundedDate: Date?

    /// Internal flag that keeps track of whether we're waiting for the initial playback to begin
    private var isWaitingForInitialPlayback = false

    private var isPlayingLocalFile = false

    // Keep track of the previous playback and waiting state
    private var previousReasonForWaiting: AVPlayer.WaitingReason?
    private var previousTimeControlStatus: AVPlayer.TimeControlStatus?

    private var durationObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var playerStatusObserver: NSKeyValueObservation?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var timeControlStatusObserver: NSKeyValueObservation?

    private var playToEndObserver: NSObjectProtocol?
    private var playFailedObserver: NSObjectProtocol?
    private var playStalledObserver: NSObjectProtocol?

    private var episodeUuid: String?
    private var podcastUuid: String?


#if !APPCLIP && !os(tvOS)
    private var cellularTracker: StreamingCellularTracker?
#endif

    @MainActor
    private lazy var episodeArtwork = EpisodeArtwork()

    private var peakLimiter: AudioUnit?
    private var highPassFilter: AudioUnit?
    private var dynamicsProcessor: AudioUnit?
    private var sampleCount: Float64 = 0
    private var backgroundTaskId: UIBackgroundTaskIdentifier
    private var voiceBoostNState: OpaquePointer?
    private var cachedSampleRate: Double = 0
    /// Integrated LUFS precomputed for this episode; 0 = unknown (adapt live).
    /// Written before playback starts, read by the tap on VBN state creation.
    private var cachedLoudness: Double = 0

    /// Snapshot the real-time tap thread consumes.
    private struct TapConfig: Sendable {
        var useVoiceBoostN: Bool
        var vbnConfig: VBNConfig
        var generation: UInt64
    }

    /// Tuning snapshot for the tap thread: written on the playback flow
    /// (loadEpisode / effectsDidChange) via a blocking `withLock`, and read from the
    /// real-time render callback via a non-blocking `withLockIfAvailable` so that
    /// thread never blocks. An `OSAllocatedUnfairLock` (not a `Mutex`) precisely
    /// because one side is real-time and must use a trylock.
    private let tapConfig = OSAllocatedUnfairLock<TapConfig>(
        initialState: TapConfig(useVoiceBoostN: false, vbnConfig: VBN_GetDefaultConfig(), generation: 0)
    )
    /// Tap-thread only: last snapshot successfully read from `tapConfig`; reused when a
    /// writer momentarily holds the lock so the render callback proceeds without blocking.
    private var lastTapConfig = TapConfig(useVoiceBoostN: false, vbnConfig: VBN_GetDefaultConfig(), generation: 0)
    /// Tap-thread only: the generation last pushed into the VBN state.
    private var appliedTapConfigGeneration: UInt64 = 0
    /// Tap-thread only: whether VBN processing ran last buffer (enable-edge detection).
    private var tapVoiceBoostNActive = false
    /// Tap-thread only: a one-shot nil meter publication that must be retried when the
    /// UI reader momentarily owns the non-blocking meter lock.
    private var tapVoiceBoostMetersNeedClear = false

    init() {
        backgroundTaskId = .invalid
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        refreshTapTuning()
    }

    deinit {
        // The didEnterBackground selector observer is added in init; remove it explicitly
        // for symmetry with the block observers cleaned up in cleanupPlayer.
        NotificationCenter.default.removeObserver(self)
    }

    /// Re-snapshots the tuning-derived values the tap thread consumes. Runs on the
    /// playback flow / main thread (never real-time), so a blocking `withLock` is fine.
    private func refreshTapTuning() {
        let tuning = PlaybackManager.engineState.tuning
        tapConfig.withLock { config in
            config.useVoiceBoostN = tuning.voiceBoost.useVoiceBoostN
            config.vbnConfig = tuning.vbnConfig()
            config.generation &+= 1
        }
    }

    func loadEpisode(_ episode: BaseEpisode) {
        if player != nil {
            cleanupPlayer()
            player = nil
        }

        if let url = EpisodeManager.urlForEpisode(episode) {
            isPlayingLocalFile = url.isFileURL
        } else {
            isPlayingLocalFile = false
        }

        guard let playerItem = DownloadManager.shared.downloadParallelToStream(of: episode) else {
            handlePlaybackError("Unable to create playback item")
            return
        }

        isWaitingForInitialPlayback = true

        player = AVPlayer(playerItem: playerItem)

        episodeUuid = episode.uuid
        podcastUuid = episode.parentIdentifier()
        cachedLoudness = DataManager.sharedManager.findLoudness(episode: episode)
        refreshTapTuning()

        // Start cellular tracking for remote streaming
        // MediaExporterResourceLoaderDelegate handles its own tracking for cache+stream,
        // but for direct AVPlayer streaming we use StreamingCellularTracker
        #if !APPCLIP && !os(tvOS)
        // AVPlayerItem.asset is main-actor in current SDKs; bridge the read
        let boxedAsset: PocketCastsUtils.UncheckedSendable<AVURLAsset?> = if Thread.isMainThread {
            MainActor.assumeIsolated { PocketCastsUtils.UncheckedSendable(playerItem.asset as? AVURLAsset) }
        } else {
            DispatchQueue.main.sync { MainActor.assumeIsolated { PocketCastsUtils.UncheckedSendable(playerItem.asset as? AVURLAsset) } }
        }
        if let urlAsset = boxedAsset.value,
           !urlAsset.url.isFileURL,
           !(urlAsset.url.scheme?.hasPrefix(MediaExporterResourceLoaderDelegate.schemePrefix) ?? false) {
            cellularTracker = StreamingCellularTracker()
            cellularTracker?.startTracking(
                playerItem: playerItem,
                episodeUuid: episode.uuid,
                podcastUuid: episode.parentIdentifier()
            )
        }
        #endif

        configurePlayer(videoPodcast: episode.videoPodcast())
    }

    func isReadyToPlay() -> Bool {
        player != nil
    }

    func playing() -> Bool {
        (player?.rate ?? 0) != 0
    }

    func buffering() -> Bool {
        guard let player else { return false }

        if let item = player.currentItem {
            return item.isPlaybackBufferEmpty || !item.isPlaybackLikelyToKeepUp
        }

        return true
    }

    func futureBufferAvailable() -> TimeInterval {
        guard let loadedTimeRanges = player?.currentItem?.loadedTimeRanges else { return 0 }

        let upTo = currentTime()
        for range in loadedTimeRanges {
            let rangeBuferred = range.timeRangeValue
            if (CMTimeGetSeconds(rangeBuferred.start) + CMTimeGetSeconds(rangeBuferred.duration)) > upTo {
                return CMTimeGetSeconds(rangeBuferred.duration)
            }
        }

        return 0
    }

    func play(completion: (() -> Void)? = nil) {
        startBackgroundTask()

        shouldKeepPlaying = true
        effectsDidChange()
        performSetPlaybackRate()
        jumpToStartingPosition()

        player?.volume = 1

        completion?()
    }

    func pause() {
        shouldKeepPlaying = false
        player?.pause()
    }

    func playbackRate() -> Double {
        if let rate = player?.rate, rate > 0 {
            return Double(rate)
        }

        return requiredPlaybackRate
    }

    func setPlaybackRate(_ rate: Double) {
        requiredPlaybackRate = rate

        if playing() {
            performSetPlaybackRate()
        }
    }

    func seekTo(_ time: TimeInterval, completion: (() -> Void)?) {
        let adjustedTime = fmax(0.1, time)

        let timeToSeekTo = CMTimeMake(value: Int64(adjustedTime * 100), timescale: 100)
        let tolerance = CMTime.zero // in testing setting this to 1 second wasn't honoured and it would sometimes be 10 seconds out. So go for accuracy over seek speed here

        let boxedCompletion = PocketCastsUtils.UncheckedSendable(completion)
        player?.seek(to: timeToSeekTo, toleranceBefore: tolerance, toleranceAfter: tolerance, completionHandler: { finished in
            if finished {
                if !self.playing(), self.shouldKeepPlaying {
                    self.play(completion: nil)
                }
                boxedCompletion.value?()
            }
        })
    }

    func currentTime() -> TimeInterval {
        if let time = player?.currentTime() {
            return CMTimeGetSeconds(time)
        }

        return 0
    }

    func duration() -> TimeInterval {
        guard let duration = player?.currentItem?.duration, !duration.isIndefinite else {
            return -1
        }

        return CMTimeGetSeconds(duration)
    }

    func endPlayback(permanent: Bool) {
        shouldKeepPlaying = false
        if playing() {
            player?.pause()
        }
        cleanupPlayer()

        #if !APPCLIP && !os(tvOS)
        cellularTracker?.stopTracking()
        cellularTracker = nil
        #endif

        audioMix = nil
        assetTrack = nil
        player = nil
    }

    func effectsDidChange() {
        let effects = PlaybackManager.engineState.effects

        setPlaybackRate(effects.playbackSpeed)
        volumeBoostEnabled = effects.volumeBoost
        refreshTapTuning()
    }

    func supportsSilenceRemoval() -> Bool {
        false
    }

    func supportsVolumeBoost() -> Bool {
        true
    }

    func supportsStreaming() -> Bool {
        true
    }

    func supportsAirplay2() -> Bool {
        true
    }

    func shouldBePlaying() -> Bool {
        shouldKeepPlaying
    }

    func routeDidChange(shouldPause: Bool) {
        if shouldPause {
            Task { @MainActor in PlaybackManager.shared.pause(userInitiated: false) }
        }
    }

    func interruptionDidStart() {
        // we don't need to do anything here, iOS handles this
    }

    func internalPlayerForVideoPlayback() -> AVPlayer? {
        player
    }

    @objc private func didEnterBackground() {
        lastBackgroundedDate = Date()
    }

    private func checkIfPlayerFailed() -> Bool {
        guard let player, player.currentItem?.status == .failed  || player.status == .failed else {
            return false
        }
        let playerErrorMessage =  (player.error as? NSError)?.debugDescription ?? ""
        let playerItemErrorMessage = (player.currentItem?.error as? NSError)?.debugDescription ?? ""
        FileLog.shared.addMessage("[DefaultPlayer] Playback did fail with error: \(playerErrorMessage) | \(playerItemErrorMessage)")

        // Give priority to player item error
        let playerError: Error? = (player.currentItem?.error ?? player.error)
        let playerNSError = playerError as? NSError

        var retryUuid: String?
        if let playerNSError, playerNSError.domain == NSURLErrorDomain, playerNSError.code != NSURLErrorNotConnectedToInternet,
           let episodeUuid {
            retryUuid = episodeUuid
        }
        let logMessage = "AVPlayerItemStatusFailed on currentItem: \(playerErrorMessage) - \(playerItemErrorMessage)"
        var error: PlaybackManager.PlaybackError = .playbackError(logMessage: logMessage, isLocalFile: isPlayingLocalFile)
        if let playerNSError,
           playerNSError.domain == NSURLErrorDomain {
            if PlaybackManager.PlaybackError.knownURLErrors.contains(playerNSError.code) {
                error = .episodeNotAvailable(errorCode: playerNSError.code, logMessage: logMessage)
            } else if playerNSError.code == NSURLErrorNotConnectedToInternet {
                error = .internetConnection(logMessage: logMessage)
            } else {
                error = .episodeNotAvailable(errorCode: playerNSError.code, logMessage: logMessage)
            }
        }
        let failure = error
        Task { @MainActor in
            // a successful URL retry supersedes the failure report; the retried load fires its own updates
            if let retryUuid, PlaybackManager.shared.retryUrlLoad(for: retryUuid) { return }
            PlaybackManager.shared.playbackDidFail(error: failure)
        }

        return true
    }

    private func playerStatusDidChange() {
        guard !checkIfPlayerFailed() else {
            return
        }

        if assetTrack == nil,
           let currentItem = player?.currentItem,
           loadingPlayerItem !== currentItem,
           currentItem.status == .readyToPlay {
            loadAssetTrack(for: currentItem)
        }

        Task { @MainActor in PlaybackManager.shared.playerDidChangeNowPlayingInfo() }
    }

    private func loadAssetTrack(for currentItem: AVPlayerItem) {
        assetTrackLoadTask?.cancel()
        loadingPlayerItem = currentItem
        assetTrackLoadTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let boxedTrackAsset = await MainActor.run { PocketCastsUtils.UncheckedSendable(currentItem.asset) }
                let tracks = try await boxedTrackAsset.value.load(.tracks)
                try Task.checkCancellation()
                await self.applyLoadedTracks(currentItem: currentItem, tracks: tracks)
            } catch is CancellationError {
                await self.clearAssetTrackLoadTask(for: currentItem)
                return
            } catch {
                await self.clearAssetTrackLoadTask(for: currentItem)
            }
        }
    }

    @MainActor
    private func clearAssetTrackLoadTask(for currentItem: AVPlayerItem) {
        guard loadingPlayerItem === currentItem else { return }
        assetTrackLoadTask = nil
        loadingPlayerItem = nil
    }

    @MainActor
    private func applyLoadedTracks(currentItem: AVPlayerItem, tracks: [AVAssetTrack]) {
        guard player?.currentItem === currentItem else {
            clearAssetTrackLoadTask(for: currentItem)
            return
        }

        assetTrackLoadTask = nil
        loadingPlayerItem = nil
        loadEmbeddedImage(for: currentItem)
        assetTrack = tracks.first { $0.mediaType == .audio }

            createAudioMix()
            currentItem.audioMix = audioMix

        isWaitingForInitialPlayback = false
        Task { @MainActor in PlaybackManager.shared.playerDidChangeNowPlayingInfo() }
    }

    // MARK: - Audio Mix
    private class AudioProcessingTapProxy {
        weak var input: DefaultPlayer?

        init(input: DefaultPlayer) {
            self.input = input
        }

        deinit {
            FileLog.shared.console("[AudioProcessingTapProxy] Deinit proxy")
        }
    }

    private static func unretainedDefaultPlayer(for tap: MTAudioProcessingTap) -> DefaultPlayer? {
        return DefaultPlayer.unretainedDefaultPlayer(for: MTAudioProcessingTapGetStorage(tap))
    }

    private static func unretainedDefaultPlayer(for pointer: UnsafeMutableRawPointer) -> DefaultPlayer? {
        let cookie = Unmanaged<AudioProcessingTapProxy>.fromOpaque(pointer).takeUnretainedValue()
        guard let player = cookie.input else { return nil }
        return player
    }

        private func createAudioMix() {
            guard audioMix == nil else { return }

            let mutableMix = AVMutableAudioMix()
            let audioMixInputParameters = AVMutableAudioMixInputParameters(track: assetTrack)

            let tapCookie = AudioProcessingTapProxy(input: self)
            let clientInfo = UnsafeMutableRawPointer(Unmanaged.passRetained(tapCookie).toOpaque())

            var callbacks = MTAudioProcessingTapCallbacks(
                version: kMTAudioProcessingTapCallbacksVersion_0,
                clientInfo: clientInfo,
                init: tapInit,
                finalize: tapFinalize,
                prepare: tapPrepare,
                unprepare: tapUnprepare,
                process: tapProcess
            )

#if compiler(>=6.2)
            var audioProcessingTap: MTAudioProcessingTap?
            if noErr == MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &audioProcessingTap) {
                audioMixInputParameters.audioTapProcessor = audioProcessingTap
                mutableMix.inputParameters = [audioMixInputParameters]
                audioMix = mutableMix
            }
#else
            var audioProcessingTap: Unmanaged<MTAudioProcessingTap>?
            if noErr == MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &audioProcessingTap) {
                audioMixInputParameters.audioTapProcessor = audioProcessingTap?.takeRetainedValue()
                mutableMix.inputParameters = [audioMixInputParameters]
                audioMix = mutableMix
            }
#endif
        }

        // MARK: - Tap Callbacks

        let tapInit: MTAudioProcessingTapInitCallback = { tap, clientInfo, tapStorageOut in
            tapStorageOut.pointee = clientInfo

            guard let referenceToSelf = DefaultPlayer.unretainedDefaultPlayer(for: tap) else {
                return
            }

            referenceToSelf.peakLimiter = nil
            referenceToSelf.highPassFilter = nil
            referenceToSelf.dynamicsProcessor = nil
            referenceToSelf.sampleCount = 0
            referenceToSelf.voiceBoostNState = nil
        }

        let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
            FileLog.shared.console("[AudioProcessingTapProxy] Finalize tap: \(tap)\n")
            Unmanaged<AudioProcessingTapProxy>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
        }

        let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, maxFrames, processingFormat in
            guard let referenceToSelf = DefaultPlayer.unretainedDefaultPlayer(for: tap) else {
                return
            }

            guard let filter = referenceToSelf.createHighPassFilter(maxFrames: maxFrames, processingFormat: processingFormat.pointee, tap: tap) else {
                referenceToSelf.handlePlaybackError("Setup high pass filter failed")
                return
            }
            referenceToSelf.highPassFilter = filter

            guard let dynamics = referenceToSelf.createDynamicsProcessor(maxFrames: maxFrames, processingFormat: processingFormat.pointee, tap: tap) else {
                referenceToSelf.handlePlaybackError("Setup dynamics processor failed")
                return
            }
            referenceToSelf.dynamicsProcessor = dynamics

            guard let limiter = referenceToSelf.createPeakLimiter(maxFrames: maxFrames, processingFormat: processingFormat.pointee, tap: tap) else {
                referenceToSelf.handlePlaybackError("Setup peak limiter failed")
                return
            }
            referenceToSelf.peakLimiter = limiter

            // Store sample rate for VoiceBoostN creation
            referenceToSelf.cachedSampleRate = Double(processingFormat.pointee.mSampleRate)

            // Create the VoiceBoostN state HERE (prepare runs once, before the first
            // real-time render callback) rather than lazily inside `tapProcess`, so the
            // render thread never allocates. It is always created because the feature can
            // be toggled on during any playback; `tapProcess` gates actual processing on
            // the live `useVoiceBoostN` flag. Seeded from the precomputed loudness so
            // playback starts at the right level instead of adapting over the first seconds.
            if referenceToSelf.voiceBoostNState == nil {
                let snapshot = referenceToSelf.tapConfig.withLock { $0 }
                referenceToSelf.lastTapConfig = snapshot
                var config = snapshot.vbnConfig
                if let state = VBN_CreateWithConfig(referenceToSelf.cachedSampleRate, &config) {
                    referenceToSelf.voiceBoostNState = state
                    referenceToSelf.appliedTapConfigGeneration = snapshot.generation
                    if referenceToSelf.cachedLoudness != 0 {
                        VBN_SetInitialGainDB(state, config.targetLUFS - Float(referenceToSelf.cachedLoudness))
                    }
                    FileLog.shared.addMessage("[DefaultPlayer] VoiceBoostN state created at \(referenceToSelf.cachedSampleRate) Hz")
                }
            }
        }

        let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { tap in
            guard let referenceToSelf = DefaultPlayer.unretainedDefaultPlayer(for: tap) else {
                return
            }

            if let vbnState = referenceToSelf.voiceBoostNState {
                VBN_Destroy(vbnState)
                referenceToSelf.voiceBoostNState = nil
                referenceToSelf.tapVoiceBoostNActive = false
                referenceToSelf.tapVoiceBoostMetersNeedClear = false
                PlaybackManager.engineState.clearVoiceBoostMeters()
                FileLog.shared.addMessage("[DefaultPlayer] VoiceBoostN state destroyed")
            }

            if let peakLimiter = referenceToSelf.peakLimiter {
                AudioUnitUninitialize(peakLimiter)
                AudioComponentInstanceDispose(peakLimiter)
                referenceToSelf.peakLimiter = nil
            }

            if let dynamicsProcessor = referenceToSelf.dynamicsProcessor {
                AudioUnitUninitialize(dynamicsProcessor)
                AudioComponentInstanceDispose(dynamicsProcessor)
                referenceToSelf.dynamicsProcessor = nil
            }

            if let highPassFilter = referenceToSelf.highPassFilter {
                AudioUnitUninitialize(highPassFilter)
                AudioComponentInstanceDispose(highPassFilter)
                referenceToSelf.highPassFilter = nil
            }
        }

        let tapProcess: MTAudioProcessingTapProcessCallback = { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
            guard let referenceToSelf = DefaultPlayer.unretainedDefaultPlayer(for: tap) else {
                return
            }

            let currentSampleCount = referenceToSelf.sampleCount
            referenceToSelf.sampleCount += Float64(numberFrames)
            guard referenceToSelf.volumeBoostEnabled, let peakLimiter = referenceToSelf.peakLimiter, referenceToSelf.highPassFilter != nil, referenceToSelf.dynamicsProcessor != nil else {
                // no effects enabled, so just play normally
                guard MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut) == noErr else {
                    referenceToSelf.handlePlaybackError("MTAudioProcessingTapGetSourceAudio failed")
                    return
                }
                return
            }

            // Real-time-safe read of the published tuning snapshot. A non-blocking
            // trylock: if a writer momentarily holds the lock we reuse the last
            // snapshot rather than block the render thread. The VBN state itself was
            // created in `tapPrepare`, so nothing is allocated, freed, or logged here.
            let snapshot = referenceToSelf.tapConfig.withLockIfAvailable { $0 } ?? referenceToSelf.lastTapConfig
            referenceToSelf.lastTapConfig = snapshot
            let shouldUseVoiceBoostN = snapshot.useVoiceBoostN

            if shouldUseVoiceBoostN, let vbnState = referenceToSelf.voiceBoostNState {
                referenceToSelf.tapVoiceBoostMetersNeedClear = false

                // Live-apply any staged tuning change (allocation-free).
                if referenceToSelf.appliedTapConfigGeneration != snapshot.generation {
                    var config = snapshot.vbnConfig
                    VBN_SetConfig(vbnState, &config)
                    referenceToSelf.appliedTapConfigGeneration = snapshot.generation
                }

                // Enable edge: restart adaptation from the loudness seed so a
                // mid-playback toggle behaves like a fresh start (matches the old
                // destroy/recreate path, but without allocating on the render thread).
                if !referenceToSelf.tapVoiceBoostNActive {
                    VBN_Reset(vbnState)
                    if referenceToSelf.cachedLoudness != 0 {
                        var config = snapshot.vbnConfig
                        VBN_SetInitialGainDB(vbnState, config.targetLUFS - Float(referenceToSelf.cachedLoudness))
                    }
                    referenceToSelf.tapVoiceBoostNActive = true
                }

                // Use VoiceBoostN processing
                guard MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut) == noErr else {
                    referenceToSelf.handlePlaybackError("MTAudioProcessingTapGetSourceAudio failed")
                    return
                }

                // Process through VoiceBoostN
                let bufferList = UnsafeMutableAudioBufferListPointer(bufferListInOut)
                let channelCount = Int32(bufferList.count)

                var channelPointers: [UnsafeMutablePointer<Float>?] = bufferList.compactMap { buffer in
                    buffer.mData?.assumingMemoryBound(to: Float.self)
                }

                channelPointers.withUnsafeMutableBufferPointer { ptr in
                    VBN_Process(vbnState, ptr.baseAddress, Int32(numberFrames), channelCount)
                }

                PlaybackManager.engineState.publishVoiceBoostMeters(.init(
                    gainDB: VBN_GetCurrentGainDB(vbnState),
                    measuredLUFS: VBN_GetMeasuredLUFS(vbnState),
                    limiterReductionDB: VBN_GetLimiterReductionDB(vbnState)
                ))

                numberFramesOut.pointee = numberFrames
            } else {
                // VoiceBoostN inactive: begin a one-shot clear on the disable edge, then
                // retry every buffer until the non-blocking publication succeeds.
                if referenceToSelf.tapVoiceBoostNActive {
                    referenceToSelf.tapVoiceBoostNActive = false
                    referenceToSelf.tapVoiceBoostMetersNeedClear = true
                }
                if referenceToSelf.tapVoiceBoostMetersNeedClear,
                   PlaybackManager.engineState.publishVoiceBoostMeters(nil) {
                    referenceToSelf.tapVoiceBoostMetersNeedClear = false
                }

                // Use previous voice boost (AudioUnit chain): the peak limiter is
                // the end of the pull chain source → high-pass → dynamics → limiter,
                // matching EffectsPlayer's legacy graph
                var audioTimeStamp = AudioTimeStamp()
                audioTimeStamp.mSampleTime = currentSampleCount
                audioTimeStamp.mFlags = AudioTimeStampFlags.sampleTimeValid
                guard AudioUnitRender(peakLimiter, nil, &audioTimeStamp, 0, UInt32(numberFrames), bufferListInOut) == noErr else {
                    referenceToSelf.handlePlaybackError("AudioUnitRender failed")
                    return
                }

                numberFramesOut.pointee = numberFrames
            }
        }

        // MARK: - Peak Limter

        func createPeakLimiter(maxFrames: CMItemCount, processingFormat: AudioStreamBasicDescription, tap: MTAudioProcessingTap) -> AudioUnit? {
            guard let referenceToSelf = DefaultPlayer.unretainedDefaultPlayer(for: tap) else {
                return nil
            }
            var componentDescription = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                                                 componentSubType: kAudioUnitSubType_PeakLimiter,
                                                                 componentManufacturer: kAudioUnitManufacturer_Apple,
                                                                 componentFlags: 0,
                                                                 componentFlagsMask: 0)

            var unit: AudioUnit?
            guard let audioComponent = AudioComponentFindNext(nil, &componentDescription) else { return nil }
            guard AudioComponentInstanceNew(audioComponent, &unit) == noErr, let createdUnit = unit else { return nil }

            // Set audio unit input/output stream format to processing format
            var format = processingFormat
            guard AudioUnitSetProperty(createdUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)) == noErr else { return nil }
            guard AudioUnitSetProperty(createdUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)) == noErr else { return nil }

            // Set audio unit render callback
            let inputProcRefCon = Unmanaged<AudioProcessingTapProxy>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
            var renderCallback = AURenderCallbackStruct(inputProc: referenceToSelf.peakLimiterRenderCallback, inputProcRefCon: inputProcRefCon.toOpaque())

            guard AudioUnitSetProperty(createdUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &renderCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.stride)) == noErr else { return nil }

            // Set audio unit maximum frames per slice to max frames
            var maximumFramesPerSlice = UInt32(maxFrames)
            guard AudioUnitSetProperty(createdUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFramesPerSlice, UInt32(MemoryLayout<UInt32>.stride)) == noErr else { return nil }

            // Initialize audio unit
            guard AudioUnitInitialize(createdUnit) == noErr else {
                AudioComponentInstanceDispose(createdUnit)
                return nil
            }

            AudioUnitSetParameter(createdUnit, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.002, 0)
            AudioUnitSetParameter(createdUnit, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, 0.005, 0)
            AudioUnitSetParameter(createdUnit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, 11, 0)

            return createdUnit
        }

        let peakLimiterRenderCallback: AURenderCallback = { inRefCon, _, inTimeStamp, _, inNumberFrames, ioData -> OSStatus in
            guard
                let referenceToSelf = DefaultPlayer.unretainedDefaultPlayer(for: inRefCon),
                let dynamicsProcessor = referenceToSelf.dynamicsProcessor,
                let ioData
            else {
                return -1
            }

            var audioTimeStamp = AudioTimeStamp()
            audioTimeStamp.mSampleTime = inTimeStamp.pointee.mSampleTime
            audioTimeStamp.mFlags = AudioTimeStampFlags.sampleTimeValid

            // The peak limiter pulls from the dynamics processor
            var actionFlags = AudioUnitRenderActionFlags()
            return AudioUnitRender(dynamicsProcessor, &actionFlags, &audioTimeStamp, 0, inNumberFrames, ioData)
        }

        // MARK: - Dynamics Processor

        func createDynamicsProcessor(maxFrames: CMItemCount, processingFormat: AudioStreamBasicDescription, tap: MTAudioProcessingTap) -> AudioUnit? {
            guard let referenceToSelf = DefaultPlayer.unretainedDefaultPlayer(for: tap) else {
                return nil
            }
            var componentDescription = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                                                 componentSubType: kAudioUnitSubType_DynamicsProcessor,
                                                                 componentManufacturer: kAudioUnitManufacturer_Apple,
                                                                 componentFlags: 0,
                                                                 componentFlagsMask: 0)

            var unit: AudioUnit?
            guard let audioComponent = AudioComponentFindNext(nil, &componentDescription) else { return nil }
            guard AudioComponentInstanceNew(audioComponent, &unit) == noErr, let createdUnit = unit else { return nil }

            // Set audio unit input/output stream format to processing format
            var format = processingFormat
            guard AudioUnitSetProperty(createdUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)) == noErr else { return nil }
            guard AudioUnitSetProperty(createdUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)) == noErr else { return nil }

            // Set audio unit render callback
            let inputProcRefCon = Unmanaged<AudioProcessingTapProxy>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
            var renderCallback = AURenderCallbackStruct(inputProc: referenceToSelf.dynamicsProcessorRenderCallback, inputProcRefCon: inputProcRefCon.toOpaque())
            guard AudioUnitSetProperty(createdUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &renderCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.stride)) == noErr else { return nil }

            // Set audio unit maximum frames per slice to max frames
            var maximumFramesPerSlice = UInt32(maxFrames)
            guard AudioUnitSetProperty(createdUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFramesPerSlice, UInt32(MemoryLayout<UInt32>.stride)) == noErr else { return nil }

            // Initialize audio unit
            guard AudioUnitInitialize(createdUnit) == noErr else {
                AudioComponentInstanceDispose(createdUnit)
                return nil
            }

            // same parameters as EffectsPlayer's legacy volume-boost chain
            AudioUnitSetParameter(createdUnit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -41, 0)
            AudioUnitSetParameter(createdUnit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 40, 0)
            AudioUnitSetParameter(createdUnit, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, 1, 0)
            AudioUnitSetParameter(createdUnit, kDynamicsProcessorParam_ExpansionThreshold, kAudioUnitScope_Global, 0, -100, 0)
            AudioUnitSetParameter(createdUnit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.05, 0)
            AudioUnitSetParameter(createdUnit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.2, 0)
            AudioUnitSetParameter(createdUnit, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, 0, 0)
            AudioUnitSetParameter(createdUnit, kDynamicsProcessorParam_CompressionAmount, kAudioUnitScope_Global, 0, 0, 0)
            AudioUnitSetParameter(createdUnit, kDynamicsProcessorParam_InputAmplitude, kAudioUnitScope_Global, 0, -120, 0)
            AudioUnitSetParameter(createdUnit, kDynamicsProcessorParam_OutputAmplitude, kAudioUnitScope_Global, 0, -120, 0)

            return createdUnit
        }

        let dynamicsProcessorRenderCallback: AURenderCallback = { inRefCon, _, inTimeStamp, _, inNumberFrames, ioData -> OSStatus in
            guard
                let referenceToSelf = DefaultPlayer.unretainedDefaultPlayer(for: inRefCon),
                let highPassFilter = referenceToSelf.highPassFilter,
                let ioData
            else {
                return -1
            }

            var audioTimeStamp = AudioTimeStamp()
            audioTimeStamp.mSampleTime = inTimeStamp.pointee.mSampleTime
            audioTimeStamp.mFlags = AudioTimeStampFlags.sampleTimeValid

            // The dynamics processor pulls from the high pass filter
            var actionFlags = AudioUnitRenderActionFlags()
            return AudioUnitRender(highPassFilter, &actionFlags, &audioTimeStamp, 0, inNumberFrames, ioData)
        }

        // MARK: - High Pass Filter

    private func createHighPassFilter(maxFrames: CMItemCount, processingFormat: AudioStreamBasicDescription, tap: MTAudioProcessingTap) -> AudioUnit? {
            guard let referenceToSelf = DefaultPlayer.unretainedDefaultPlayer(for: tap) else {
                return nil
            }
            var componentDescription = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                                                 componentSubType: kAudioUnitSubType_HighPassFilter,
                                                                 componentManufacturer: kAudioUnitManufacturer_Apple,
                                                                 componentFlags: 0,
                                                                 componentFlagsMask: 0)

            var unit: AudioUnit?
            guard let audioComponent = AudioComponentFindNext(nil, &componentDescription) else { return nil }
            guard AudioComponentInstanceNew(audioComponent, &unit) == noErr, let createdUnit = unit else { return nil }

            // Set audio unit input/output stream format to processing format
            var format = processingFormat
            guard AudioUnitSetProperty(createdUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)) == noErr else { return nil }
            guard AudioUnitSetProperty(createdUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)) == noErr else { return nil }

            // Set audio unit render callback
            let inputProcRefCon = Unmanaged<AudioProcessingTapProxy>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
            var renderCallback = AURenderCallbackStruct(inputProc: referenceToSelf.highPassFilterRenderCallback, inputProcRefCon: inputProcRefCon.toOpaque())
            guard AudioUnitSetProperty(createdUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &renderCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.stride)) == noErr else { return nil }

            // Set audio unit maximum frames per slice to max frames
            var maximumFramesPerSlice = UInt32(maxFrames)
            guard AudioUnitSetProperty(createdUnit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFramesPerSlice, UInt32(MemoryLayout<UInt32>.stride)) == noErr else { return nil }

            // Initialize audio unit
            guard AudioUnitInitialize(createdUnit) == noErr else {
                AudioComponentInstanceDispose(createdUnit)
                return nil
            }

            AudioUnitSetParameter(createdUnit, kHipassParam_CutoffFrequency, kAudioUnitScope_Global, 0, 180, 0)
            AudioUnitSetParameter(createdUnit, kHipassParam_Resonance, kAudioUnitScope_Global, 0, 0, 0)

            return createdUnit
        }

        let highPassFilterRenderCallback: AURenderCallback = { inRefCon, _, _, _, inNumberFrames, ioData -> OSStatus in
            guard
                let referenceToSelf = DefaultPlayer.unretainedDefaultPlayer(for: inRefCon),
                // TODO(A2d): this reads `self.audioMix` on the real-time render thread while
                // cleanupPlayer nils it on main — an unsynchronized ARC read/release. Deferred
                // fix: cache the tap as `Unmanaged<MTAudioProcessingTap>` set in createAudioMix
                // and read that here. Gate on on-device Thread Sanitizer verification first.
                let tap = referenceToSelf.audioMix?.inputParameters.first?.audioTapProcessor,
                let ioData
            else {
                return -1
            }

            // The high pass filter is the start of the chain, so it pulls the source audio
            return MTAudioProcessingTapGetSourceAudio(tap, CMItemCount(inNumberFrames), ioData, nil, nil, nil)
        }

    // MARK: - Helpers

    private func performSetPlaybackRate() {
        if requiredPlaybackRate == 0 {
            // never set: default to normal speed
            requiredPlaybackRate = 1.0
        } else if requiredPlaybackRate < 0.5 {
            // clamp instead of the old silent snap back to 1.0
            requiredPlaybackRate = 0.5
        }

        player?.rate = Float(requiredPlaybackRate)

        player?.currentItem?.audioTimePitchAlgorithm = PlaybackManager.engineState.tuning.timeStretch.defaultPlayerAlgorithm.avAlgorithm
    }

    private func jumpToStartingPosition() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let startingTime = PlaybackManager.shared.requiredStartingPosition()

            // there's a bug that when playing over AirPlay to a HomePod, seeking in stream that's already where you are up to sometimes doesn't work, this is a weird workaround for that case
            // https://github.com/shiftyjelly/pocketcasts-ios/issues/1936 is worth a read if you ever come here thinking you want to change this code
            if round(startingTime) != round(self.currentTime()) {
                self.seekTo(startingTime, completion: nil)
            }

            PlaybackManager.shared.playerDidFinishPreparing()
        }
    }

    private func startBackgroundTask() {
            // Playback can call this from its own queues (including AVPlayer KVO callbacks
            // delivered on an internal AVFoundation queue). A blocking `main.sync` from
            // there risks deadlock, so bounce off-main callers to the main queue async and
            // keep `backgroundTaskId` main-thread-only, which also closes the double-start race.
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self] in self?.startBackgroundTask() }
                return
            }
            MainActor.assumeIsolated {
                guard backgroundTaskId == .invalid else { return } // already started

                backgroundTaskId = UIApplication.shared.beginBackgroundTask(expirationHandler: { [weak self] in
                    self?.endBackgroundTask()
                })

                // schedule a timer to cancel the background task as soon as bufferring is done or we don't need to play anymore
                Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                    guard let self else {
                        timer.invalidate()
                        return
                    }

                    if !self.buffering() || !self.shouldKeepPlaying {
                        self.endBackgroundTask()
                        timer.invalidate()
                    }
                }
            }
    }

    private func endBackgroundTask() {
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self] in self?.endBackgroundTask() }
                return
            }
            MainActor.assumeIsolated {
                if backgroundTaskId == .invalid { return } // already cancelled

                let task = backgroundTaskId
                backgroundTaskId = .invalid
                UIApplication.shared.endBackgroundTask(task)
            }
    }

    // MARK: - Error Handling

    private func handlePlaybackError(_ message: String) {
        // only reports errors if we're meant to be playing
        if shouldKeepPlaying {
            shouldKeepPlaying = false
            let error = PlaybackManager.PlaybackError.playbackError(logMessage: message, isLocalFile: isPlayingLocalFile)
            Task { @MainActor in PlaybackManager.shared.playbackDidFail(error: error) }
        }
    }

    // MARK: - Player Setup/Cleanup

    private func configurePlayer(videoPodcast: Bool) {
            player?.allowsExternalPlayback = videoPodcast

        durationObserver = player?.currentItem?.observe(\.duration) { _, _ in
            Task { @MainActor in PlaybackManager.shared.playerDidCalculateDuration() }
        }

        // Listen for changes to the timeControlStatus to determine if the system has decided to pause the playback
        // and if we need to try playing again. This seems to only happen when streaming on AirPlay for some reason.
        //
        // This should fix: https://github.com/Automattic/pocket-casts-ios/issues/47
        timeControlStatusObserver = player?.observe(\.timeControlStatus) { [weak self] player, _ in
            // We're going to be very explicit about the trigger for this to prevent triggering it when we don't want to

            // Only apply the logic when playing over AirPlay
            guard PlaybackManager.isPlayingOverAirplay(), let self else { return }

            // We'll keep track of the previous statuses and compare against them in the check below
            defer {
                self.previousReasonForWaiting = player.reasonForWaitingToPlay
                self.previousTimeControlStatus = player.timeControlStatus
            }

            guard
                // Verify that we indeed want to keep playing, ie: the user hasn't manually paused
                // And that we're waiting for the initial playback to begin
                self.shouldKeepPlaying, self.isWaitingForInitialPlayback,
                // Verify playback has stopped now, but we were waiting to play the audio
                player.timeControlStatus == .paused, self.previousTimeControlStatus == .waitingToPlayAtSpecifiedRate,
                // Verify that while we were waiting to play the reason switched to no item to play, and that currently there is no current reason
                player.reasonForWaitingToPlay == nil, self.previousReasonForWaiting == .noItemToPlay
            else {
                return
            }

            FileLog.shared.addMessage("[DefaultPlayer] Detected that playback was paused while trying to play the next item. Attempting to resume playback...")
            self.play()
        }

        rateObserver = player?.observe(\.rate) { [weak self] player, _ in
            guard let self else { return }

            if player.rate == 1 {
                // there's a bug where playback can be resumed from outside our app, and Apple sets the wrong playback rate, fix that here
                // the easiest way to repeat this is to play a video at 2x, and press pause once it's in picture in picture mode
                let requiredSpeed = PlaybackManager.engineState.effects.playbackSpeed
                if requiredSpeed != 1 {
                    self.performSetPlaybackRate()
                }
            }

            if let lastBackgroundedDate = self.lastBackgroundedDate {
                let timeintervalSinceBackground = fabs(lastBackgroundedDate.timeIntervalSinceNow)
                // we were backgrounded in the last 2 seconds, then the rate has changed, sounds like iOS is pausing video
                if player.rate <= 0, self.shouldKeepPlaying, timeintervalSinceBackground > 0, timeintervalSinceBackground < 2 {
                    FileLog.shared.addMessage("Playback was paused by iOS, but it looks like we're still meant to be playing, calling play")
                    self.play(completion: nil)
                }
            }

            Task { @MainActor in PlaybackManager.shared.playerDidChangeNowPlayingInfo() }
        }

        playerStatusObserver = player?.observe(\.status) { [weak self] _, _ in
            self?.playerStatusDidChange()
        }
        playerItemStatusObserver = player?.currentItem?.observe(\.status) { [weak self] _, _ in
            self?.playerStatusDidChange()
        }

        let nc = NotificationCenter.default
        playToEndObserver = nc.addObserver(forName: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil, queue: nil) { [weak self] notification in
            guard let self else { return }

            if let itemThatFinished = notification.object as? AVPlayerItem {
                let duration = CMTimeGetSeconds(itemThatFinished.duration)
                let upTo = CMTimeGetSeconds(itemThatFinished.currentTime())

                let buffered = self.futureBufferAvailable()
                let isBuffering = self.buffering()

                // Check if this is a spurious notification (more than 5% away from end)
                // If it is, we do not want to reset shouldKeepPlaying and will let the player continue on its way
                if duration > upTo + (duration * 0.05) {
                    FileLog.shared.addMessage("Item didn't actually finish got to \(upTo) of \(duration). Buffered: \(buffered)s, isBuffering: \(isBuffering), loadedTimeRanges: \(itemThatFinished.loadedTimeRanges)")

                    // If buffer is empty, this is likely a streaming issue - let the stall handler deal with it
                    if itemThatFinished.isPlaybackBufferEmpty {
                        FileLog.shared.addMessage("Spurious end notification detected: buffer empty, treating as playback stall")
                    }

                    return
                }

                // Additional safeguard: check if buffer is empty (shouldn't be if truly finished)
                // A truly finished item should have reached the end naturally, not due to buffer exhaustion
                if itemThatFinished.isPlaybackBufferEmpty && !itemThatFinished.isPlaybackLikelyToKeepUp {
                    FileLog.shared.addMessage("Item reports finished but buffer is empty and playback unlikely to keep up - ignoring")
                    return
                }
            }

            self.shouldKeepPlaying = false

            Task { @MainActor in PlaybackManager.shared.playerDidFinishPlayingEpisode() }
        }

        playFailedObserver = nc.addObserver(forName: NSNotification.Name.AVPlayerItemFailedToPlayToEndTime, object: nil, queue: nil) { [weak self] notification in
            guard let self else { return }

            self.shouldKeepPlaying = false

            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            let errorMessage = error?.localizedDescription ?? "Unknown item did fail to finish error"
            let playbackError = PlaybackManager.PlaybackError.playbackError(logMessage: errorMessage, isLocalFile: isPlayingLocalFile)
            Task { @MainActor in PlaybackManager.shared.playbackDidFail(error: playbackError) }
        }

        playStalledObserver = nc.addObserver(forName: NSNotification.Name.AVPlayerItemPlaybackStalled, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            FileLog.shared.addMessage("Received notification of playback stall")
            if self.shouldKeepPlaying {
                FileLog.shared.addMessage("Trying to recover from stall by playing")
                self.play(completion: nil)
            }
        }
    }

    private func cleanupPlayer() {
        assetTrackLoadTask?.cancel()
        assetTrackLoadTask = nil
        loadingPlayerItem = nil
        // AVPlayerItem.audioMix is main-actor in current SDKs; bridge the clear
        let boxedItem = PocketCastsUtils.UncheckedSendable(player?.currentItem)
        let clearMix: @Sendable () -> Void = { MainActor.assumeIsolated { boxedItem.value?.audioMix = nil } }
        if Thread.isMainThread { clearMix() } else { DispatchQueue.main.sync(execute: clearMix) }
        audioMix = nil
        assetTrack = nil
        durationObserver = nil
        rateObserver = nil
        playerStatusObserver = nil
        playerItemStatusObserver = nil
        timeControlStatusObserver = nil

        if let endObserver = playToEndObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failedObserver = playFailedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
        }
        if let stalledObserver = playStalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
        }

        playToEndObserver = nil
        playFailedObserver = nil
        playStalledObserver = nil

        endBackgroundTask()
    }

    // MARK: Hashable

    static func == (lhs: DefaultPlayer, rhs: DefaultPlayer) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    func loadEmbeddedImage(for currentItem: AVPlayerItem? = nil) {
        guard let episodeUuid, let podcastUuid else {
            return
        }

        // Resolve the asset on the main actor, where AVPlayerItem.asset lives
        let boxedItem = PocketCastsUtils.UncheckedSendable((currentItem, player?.currentItem))
        Task { @MainActor in
            let (explicitItem, playerItem) = boxedItem.value
            guard let asset = explicitItem?.asset ?? playerItem?.asset else { return }
            episodeArtwork.loadEmbeddedImage(asset: asset, podcastUuid: podcastUuid, episodeUuid: episodeUuid)
        }
    }

    // MARK: - Volume

    func setVolume(_ volume: Float) {
        player?.volume = volume
    }
}
