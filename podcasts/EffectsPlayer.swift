import AudioUnit
import AVFoundation
import PocketCastsDataModel
import PocketCastsUtils
import Synchronization
import UIKit

/// AVAudioEngine effects pipeline driven by PlaybackManager; state is guarded
/// by playerLock and the serial seek queue.
/// @unchecked Sendable: mutable state is guarded by playerLock, atomics, or the serial seek queue.
nonisolated final class EffectsPlayer: PlaybackProtocol, Hashable, @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?

    private var timePitch: AVAudioUnitTimePitch?
    // AVAudioUnitTimePitch can be unsafe to query directly; keep a synchronized mirror.
    private let playbackSpeed = Mutex<Double>(0)

    private var audioMixerNode: AVAudioMixerNode?

    // for volume boost
    private var highPassFilter: AVAudioUnitEffect?
    private var dynamicsProcessor: AVAudioUnitEffect?
    private var peakLimiter: AVAudioUnitEffect?
    private let useVoiceBoostN = AtomicBool()
    private let useNormalize = AtomicBool()
    private var audioFileSampleRate: Double = 0

    private var playBufferManager: PlayBufferManager?
    private var audioReadTask: AudioReadTask?
    private var audioPlayTask: AudioPlayTask?
    private var audioFile: AVAudioFile?

    // Read live from the engine-state mirror (thread-safe) instead of keeping
    // locally-mutated copies, so the main-actor `effectsDidChange` writes no longer
    // race the background `play()` reads (A5). Both were only ever re-synced from here.
    private var effects: PlaybackManager.EngineStateMirror.PlaybackEffectsSnapshot { PlaybackManager.engineState.effects }
    private var tuning: AudioTuning { PlaybackManager.engineState.tuning }

    private let shouldKeepPlaying = AtomicBool()
    private var haveFiredDurationNotification = false

    private let aboutToPlay = AtomicBool()
    private var episodePath: String?
    private var episode: BaseEpisode?
    private var cachedFrameCount = 0 as Int64

    private struct SeekState: Sendable {
        var isSeeking = false
        var lastSeekTime: TimeInterval = 0
    }

    private let seekState = Mutex(SeekState())

    // this lock is to avoid race conditions where you're destroying the player while in the middle of setting it up (since the play method does its work asynchronously)
    // Locking contract: play() holds this across AVAudioFile(forReading:) and engine
    // startup, which can take seconds, so it must never be acquired synchronously from
    // the main actor. Main-actor entry points (setPlaybackRate, effectsDidChange) stage
    // the desired rate in `playbackSpeed` and take the lock on `serialGraphApplyQueue`
    // instead (see applyPlaybackSpeedToGraph).
    private let playerLock = NSLock()

    private let serialSeekQueue = DispatchQueue(label: "effectsplayer.serial.queue")

    /// Serializes deferred applications of staged state (currently the playback rate)
    /// onto the live audio graph; see `applyPlaybackSpeedToGraph`.
    private let serialGraphApplyQueue = DispatchQueue(label: "effectsplayer.graphapply.queue")

    @MainActor
    private lazy var episodeArtwork = EpisodeArtwork()

    // MARK: - PlaybackProtocol Impl

    func loadEpisode(_ episode: BaseEpisode) {
        episodePath = episode.pathToDownloadedFile(pathFinder: DownloadManager.shared)
        let podcastUuid = episode.parentIdentifier()
        let episodeUuid = episode.uuid
        Task { @MainActor in
            episodeArtwork.loadEmbeddedImage(asset: nil, podcastUuid: podcastUuid, episodeUuid: episodeUuid)
        }
        self.episode = episode
    }

    func isReadyToPlay() -> Bool {
        audioReadTask != nil && audioPlayTask != nil
    }

    func playing() -> Bool {
        if aboutToPlay.value { return true }

        if let player {
            return player.isPlaying
        }

        return false
    }

    func play(completion: (() -> Void)?) {
        let completion = PocketCastsUtils.UncheckedSendable(completion)
        aboutToPlay.value = true
        shouldKeepPlaying.value = true

        DispatchQueue.global().async { [weak self] in
            guard let strongSelf = self, let episode = strongSelf.episode else { return }

            strongSelf.playerLock.lock()

            strongSelf.engine = AVAudioEngine()
            strongSelf.player = AVAudioPlayerNode()
            strongSelf.engine?.attach(strongSelf.player!)

            strongSelf.playBufferManager = PlayBufferManager()

            // Set useVoiceBoostN before setVolumeBoostSettings so bypass is configured correctly
            strongSelf.useVoiceBoostN.value = Settings.isVoiceBoostNEnabled && strongSelf.effects.volumeBoost
            // Normalize is suppressed whenever Volume Boost is on — boost already
            // normalizes loudness as part of its chain (the documented interlock).
            strongSelf.useNormalize.value = strongSelf.tuning.normalize.enabled && !strongSelf.effects.volumeBoost

            strongSelf.audioMixerNode = strongSelf.createAudioMixerNode()
            strongSelf.engine?.attach(strongSelf.audioMixerNode!)

            // volume boost effects
            strongSelf.highPassFilter = strongSelf.createHighPassUnit()
            strongSelf.engine?.attach(strongSelf.highPassFilter!)

            strongSelf.dynamicsProcessor = strongSelf.createDynamicsProcessorUnit()
            strongSelf.engine?.attach(strongSelf.dynamicsProcessor!)

            strongSelf.peakLimiter = strongSelf.createPeakLimiterUnit()
            strongSelf.engine?.attach(strongSelf.peakLimiter!)
            strongSelf.setVolumeBoostSettings()

            strongSelf.timePitch = strongSelf.createTimePitchUnit()
            strongSelf.playbackSpeed.withLock { $0 = 1.0 }
            strongSelf.timePitch?.rate = 1.0
            strongSelf.engine?.attach(strongSelf.timePitch!)

            let fileURL = URL(fileURLWithPath: strongSelf.episodePath!)
            do {
                strongSelf.audioFile = try AVAudioFile(forReading: fileURL, commonFormat: AVAudioCommonFormat.pcmFormatFloat32, interleaved: false)

                // AVAudioFile.length is an expensive operation (often in the seconds) so here we attempt to load a cached value instead
                strongSelf.cachedFrameCount = DataManager.sharedManager.findFrameCount(episode: episode)
                if strongSelf.cachedFrameCount == 0 {
                    // we haven't cached a frame count for this episode, do that now
                    strongSelf.cachedFrameCount = strongSelf.audioFile!.length
                    if strongSelf.cachedFrameCount == 0 {
                        // If don't have a frameCount we cannot use the effect player
                        throw AVError(_nsError: NSError(domain: AVFoundationErrorDomain, code: AVError.fileFailedToParse.rawValue))
                    }
                    DataManager.sharedManager.saveFrameCount(episode: episode, frameCount: strongSelf.cachedFrameCount)
                }
            } catch {
                strongSelf.playerLock.unlock()
                let message = error.localizedDescription
                Task { @MainActor in PlaybackManager.shared.playbackDidFail(error: .fileCorrupted(logMessage: message), fallbackToDefaultPlayer: true) }
                return
            }

            // iOS 16 has an issue in which if the conditions below are met, the playback will fail:
            // Audio file has a single channel and spatial audio is enabled
            // In order to prevent this issue, we create a two channel format and inside
            // `AudioReadTask` we convert the mono segments to stereo
            // For more info, see: https://github.com/Automattic/pocket-casts-ios/issues/62
            var format: AVAudioFormat
            if let audioFile = strongSelf.audioFile,
               audioFile.processingFormat.channelCount == 1,
               let twoChannelsFormat = AVAudioFormat(standardFormatWithSampleRate: audioFile.processingFormat.sampleRate, channels: 2) {
                FileLog.shared.addMessage("EffectsPlayer: converting mono to stereo")
                format = twoChannelsFormat
            } else {
                format = strongSelf.audioFile!.processingFormat
            }

            strongSelf.engine?.connect(strongSelf.player!, to: strongSelf.audioMixerNode!, format: format)
            strongSelf.engine?.connect(strongSelf.audioMixerNode!, to: strongSelf.timePitch!, format: format)
            strongSelf.engine?.connect(strongSelf.timePitch!, to: strongSelf.highPassFilter!, format: format)
            strongSelf.engine?.connect(strongSelf.highPassFilter!, to: strongSelf.dynamicsProcessor!, format: format)
            strongSelf.engine?.connect(strongSelf.dynamicsProcessor!, to: strongSelf.peakLimiter!, format: format)
            strongSelf.engine?.connect(strongSelf.peakLimiter!, to: strongSelf.engine!.outputNode, format: format)

            // Store sample rate for AudioReadTask (useVoiceBoostN already set above)
            strongSelf.audioFileSampleRate = strongSelf.audioFile!.fileFormat.sampleRate

            strongSelf.startReadAndPlayThreads()
            do {
                strongSelf.engine?.prepare()
                try strongSelf.engine?.start()
            } catch {
                strongSelf.playerLock.unlock()
                let message = error.localizedDescription
                Task { @MainActor in PlaybackManager.shared.playbackDidFail(error: .fileCorrupted(logMessage: message)) }
                return
            }
            // there seem to be cases where the above call succeeds but the engine isn't actually started. Handle that here
            if !(strongSelf.engine?.isRunning ?? false) {
                strongSelf.playerLock.unlock()
                FileLog.shared.addMessage("EffectsPlayer: engine reported not running, calling playbackDidFail")
                Task { @MainActor in PlaybackManager.shared.playbackDidFail(error: .fileCorrupted(logMessage: "AVAudioEngine reported not running")) }
                return
            }

            strongSelf.playAndCatchExceptionIfNeeded()

            strongSelf.playerLock.unlock()

            completion.value?()

            if strongSelf.haveFiredDurationNotification == false {
                strongSelf.haveFiredDurationNotification = true

                Task { @MainActor in PlaybackManager.shared.playerDidCalculateDuration() }
            }

            self?.aboutToPlay.value = false
        }
    }

    // MARK: - Play

    /// Try to play. If an exception happens, just pause it.
    func playAndCatchExceptionIfNeeded() {
        do {
            try SJCommonUtils.catchException {
                self.player?.play()
            }
        } catch {
            FileLog.shared.addMessage("EffectsPlayer: failed to start playback: \(error)")
            self.playerLock.unlock()
            Task { @MainActor in PlaybackManager.shared.pause(userInitiated: false) }
        }
    }

    func pause() {
        shouldKeepPlaying.value = false
        aboutToPlay.value = false

        Task { @MainActor in PlaybackManager.shared.playerDidRequestTermination() }
    }

    func playbackRate() -> Double {
        playbackSpeed.withLock { $0 }
    }

    func setPlaybackRate(_ rate: Double) {
        playbackSpeed.withLock { $0 = rate }
        applyPlaybackSpeedToGraph()
    }

    /// Applies the staged `playbackSpeed` to the live `timePitch` node.
    ///
    /// `playerLock` serializes graph access against `play()`'s background setup and
    /// `endPlayback()`'s teardown, but `play()` holds it across `AVAudioFile(forReading:)`
    /// and engine startup (often seconds). The rate setters run on the main actor —
    /// `PlaybackManager.playerDidFinishPreparing` calls `setPlaybackRate` right after the
    /// read/play threads start — so they must never block on that lock. They stage the
    /// desired rate in the `playbackSpeed` mutex and this method takes the lock on a
    /// serial background queue. Every application re-reads the latest staged value under
    /// the lock, so a queued-up older application is harmless: the graph always converges
    /// on the most recently requested rate, applied once the engine is set up.
    private func applyPlaybackSpeedToGraph() {
        serialGraphApplyQueue.async { [weak self] in
            guard let self else { return }

            playerLock.lock()
            defer { playerLock.unlock() }
            timePitch?.rate = Float(playbackRate())
        }
    }

    func seekTo(_ time: TimeInterval, completion: (() -> Void)?) {
        guard let readOperation = audioReadTask else { return }

        let boxed = PocketCastsUtils.UncheckedSendable((readOperation, completion))
        serialSeekQueue.async { [weak self] in
            guard let self else { return }

            let (readOperation, completion) = boxed.value
            seekState.withLock {
                $0.lastSeekTime = max(0.1, time)
                $0.isSeeking = true
            }
            readOperation.seekTo(time, completion: { [weak self] seekedToEnd in
                if !seekedToEnd {
                    completion?()
                } else if !(self?.playBufferManager?.haveNotifiedPlayer.value ?? false) {
                    self?.playBufferManager?.haveNotifiedPlayer.value = true
                    FileLog.shared.addMessage("EffectsPlayer seeked passed end of episode, calling finished playing")
                    Task { @MainActor in PlaybackManager.shared.playerDidFinishPlayingEpisode() }
                }

                self?.seekState.withLock { $0.isSeeking = false }
            })
        }
    }

    func currentTime() -> TimeInterval {
        let seekSnapshot = seekState.withLock { $0 }
        if seekSnapshot.isSeeking {
            return seekSnapshot.lastSeekTime
        }

        if let audioFile, let curFrame = currentFrame() {
            return Double(curFrame) / audioFile.fileFormat.sampleRate
        }

        return -1
    }

    private func currentFrame() -> AVAudioFramePosition? {
        if let audioPlayTask {
            return audioPlayTask.lastFrameRendered()
        }

        return nil
    }

    func duration() -> TimeInterval {
        if let audioFile {
            return (Double(cachedFrameCount) / audioFile.fileFormat.sampleRate)
        }

        return -1
    }

    func effectsDidChange() {
        audioReadTask?.setTrimSilence(effects.trimSilence)
        audioReadTask?.setTuning(tuning)
        playbackSpeed.withLock { $0 = effects.playbackSpeed }
        applyPlaybackSpeedToGraph()

        // Update VoiceBoostN flag for dynamic switching
        let shouldUseVoiceBoostN = Settings.isVoiceBoostNEnabled && tuning.voiceBoost.useVoiceBoostN && effects.volumeBoost
        if shouldUseVoiceBoostN != useVoiceBoostN.value {
            useVoiceBoostN.value = shouldUseVoiceBoostN
            FileLog.shared.addMessage("[EffectsPlayer] VoiceBoostN flag changed to \(shouldUseVoiceBoostN)")
        }

        let shouldNormalize = tuning.normalize.enabled && !effects.volumeBoost
        if shouldNormalize != useNormalize.value {
            useNormalize.value = shouldNormalize
            FileLog.shared.addMessage("[EffectsPlayer] Normalize flag changed to \(shouldNormalize)")
        }

        setVolumeBoostSettings()
    }

    func endPlayback(permanent: Bool) {
        playerLock.lock()
        defer { playerLock.unlock() }

        shouldKeepPlaying.value = false
        aboutToPlay.value = false

        audioReadTask?.shutdown()
        audioPlayTask?.shutdown()
        playBufferManager?.removeAll()

        if playing() {
            player?.pause()
        }

        player?.stop()

        engine?.stop()
    }

    func supportsSilenceRemoval() -> Bool {
        true
    }

    func supportsVolumeBoost() -> Bool {
        true
    }

    func supportsStreaming() -> Bool {
        false
    }

    func supportsAirplay2() -> Bool {
        false
    }

    // we only ever play downloaded content, so we're never buffering or worry about future buffer
    func buffering() -> Bool {
        false
    }

    func futureBufferAvailable() -> TimeInterval {
        duration() - currentTime()
    }

    func shouldBePlaying() -> Bool {
        shouldKeepPlaying.value
    }

    func internalPlayerForVideoPlayback() -> AVPlayer? {
        nil
    }

    // MARK: - Handle interruptions

    func interruptionDidStart() {
        // AVAudioEngine doesn't handle interruptions as natively as AVPlayer, so we pause manually here to spin things down
        pause()
    }

    func routeDidChange(shouldPause: Bool) {
        shouldKeepPlaying.value = shouldKeepPlaying.value && !shouldPause

        // when this is called, the engine has detected an interruption like a route change. Because this happens on things like bluetooth connect, and not just disconnect, we deal with it here.
        // The audio engine has shut down at this point, so we call pause to destroy all our current state and play to restore it all if we should still be playing
        let keepPlaying = shouldKeepPlaying.value
        Task { @MainActor in
            if keepPlaying, !PlaybackManager.shared.interruptionInProgress() {
                PlaybackManager.shared.pause(userInitiated: false)
                PlaybackManager.shared.play(userInitiated: false)
            } else if !keepPlaying {
                PlaybackManager.shared.pause(userInitiated: false)
            }
        }
    }

    // MARK: - Helper methods

    private func startReadAndPlayThreads() {
        // just in case there are any running
        audioReadTask?.shutdown()
        audioPlayTask?.shutdown()

        guard let audioFile, let player, let playBufferManager else { return }

        // seed VoiceBoostN from the precomputed loudness when we have one, and
        // queue a background measurement when we don't
        var knownLUFS: Double = 0
        if let episode {
            knownLUFS = DataManager.sharedManager.findLoudness(episode: episode)
            if knownLUFS == 0 {
                EpisodeLoudnessScanner.shared.scanIfNeeded(episodeUuid: episode.uuid)
            }
        }

        let requiredStartTime = PlaybackManager.engineState.consumePendingStartingPosition() ?? 0
        audioReadTask = AudioReadTask(
            trimSilence: effects.trimSilence,
            audioFile: audioFile,
            outputFormat: audioFile.processingFormat,
            bufferManager: playBufferManager,
            playPositionHint: requiredStartTime,
            frameCount: cachedFrameCount,
            effects: AudioReadTask.EffectsConfiguration(
                useVoiceBoostN: useVoiceBoostN,
                useNormalize: useNormalize,
                sampleRate: audioFileSampleRate,
                tuning: PlaybackManager.engineState.tuning,
                knownLUFS: knownLUFS
            )
        )
        audioPlayTask = AudioPlayTask(player: player, bufferManager: playBufferManager)

        audioReadTask?.startup()
        audioPlayTask?.startup()

        Task { @MainActor in PlaybackManager.shared.playerDidFinishPreparing() }
    }

    private func setVolumeBoostSettings() {
        let shouldBypassLegacy = !effects.volumeBoost || useVoiceBoostN.value
        if shouldBypassLegacy {
            // Bypass existing effects when VoiceBoostN handles it or volumeBoost off
            peakLimiter?.bypass = true
            highPassFilter?.bypass = true
            dynamicsProcessor?.bypass = true
            if effects.volumeBoost && useVoiceBoostN.value {
                FileLog.shared.addMessage("[EffectsPlayer] Volume boost enabled with VoiceBoostN - bypassing legacy AudioUnit chain")
            } else if !effects.volumeBoost {
                FileLog.shared.addMessage("[EffectsPlayer] Volume boost disabled - bypassing all effects")
            }
        } else {
            setFloatParameter(highPassFilter?.audioUnit, key: kHipassParam_CutoffFrequency, value: 180)
            setFloatParameter(highPassFilter?.audioUnit, key: kHipassParam_Resonance, value: 0)
            highPassFilter?.bypass = false

            setFloatParameter(dynamicsProcessor?.audioUnit, key: kDynamicsProcessorParam_Threshold, value: -41)
            setFloatParameter(dynamicsProcessor?.audioUnit, key: kDynamicsProcessorParam_HeadRoom, value: 40)
            setFloatParameter(dynamicsProcessor?.audioUnit, key: kDynamicsProcessorParam_ExpansionRatio, value: 1)
            setFloatParameter(dynamicsProcessor?.audioUnit, key: kDynamicsProcessorParam_ExpansionThreshold, value: -100)
            setFloatParameter(dynamicsProcessor?.audioUnit, key: kDynamicsProcessorParam_AttackTime, value: 0.05)
            setFloatParameter(dynamicsProcessor?.audioUnit, key: kDynamicsProcessorParam_ReleaseTime, value: 0.2)

            setFloatParameter(dynamicsProcessor?.audioUnit, key: kDynamicsProcessorParam_OverallGain, value: 0)

            setFloatParameter(dynamicsProcessor?.audioUnit, key: kDynamicsProcessorParam_CompressionAmount, value: 0)
            setFloatParameter(dynamicsProcessor?.audioUnit, key: kDynamicsProcessorParam_InputAmplitude, value: -120)
            setFloatParameter(dynamicsProcessor?.audioUnit, key: kDynamicsProcessorParam_OutputAmplitude, value: -120)
            dynamicsProcessor?.bypass = false

            setFloatParameter(peakLimiter?.audioUnit, key: kLimiterParam_AttackTime, value: 0.002)
            setFloatParameter(peakLimiter?.audioUnit, key: kLimiterParam_DecayTime, value: 0.005)
            setFloatParameter(peakLimiter?.audioUnit, key: kLimiterParam_PreGain, value: 11)
            peakLimiter?.bypass = false
        }
    }

    // MARK: - Audio Units

    private func setFloatParameter(_ audioUnit: AudioUnit?, key: AudioUnitParameterID, value: Float) {
        if let audioUnit {
            AudioUnitSetParameter(audioUnit, key, kAudioUnitScope_Global, 0, value, 0)
        }
    }

    private func createAudioMixerNode() -> AVAudioMixerNode {
        return AVAudioMixerNode()
    }

    private func createTimePitchUnit() -> AVAudioUnitTimePitch {
        switch tuning.timeStretch.effectsPlayerAlgorithm {
        case .spectral:
            // Apple's default (phase-vocoder) time pitch unit
            return AVAudioUnitTimePitch()
        case .iPodTimeOther:
            // the iPod-era speech-tuned unit the app has always used; the
            // algorithm is baked into the engine graph, so switching requires a
            // player rebuild (PlaybackManager.handleAudioTuningChanged)
            var componentDescription = AudioComponentDescription()
            componentDescription.componentType = kAudioUnitType_FormatConverter
            componentDescription.componentSubType = kAudioUnitSubType_AUiPodTimeOther
            componentDescription.componentManufacturer = kAudioUnitManufacturer_Apple

            return AVAudioUnitTimePitch(audioComponentDescription: componentDescription)
        }
    }

    private func createHighPassUnit() -> AVAudioUnitEffect {
        var componentDescription = AudioComponentDescription()
        componentDescription.componentType = kAudioUnitType_Effect
        componentDescription.componentSubType = kAudioUnitSubType_HighPassFilter
        componentDescription.componentManufacturer = kAudioUnitManufacturer_Apple

        return AVAudioUnitEffect(audioComponentDescription: componentDescription)
    }

    private func createDynamicsProcessorUnit() -> AVAudioUnitEffect {
        var componentDescription = AudioComponentDescription()
        componentDescription.componentType = kAudioUnitType_Effect
        componentDescription.componentSubType = kAudioUnitSubType_DynamicsProcessor
        componentDescription.componentManufacturer = kAudioUnitManufacturer_Apple

        return AVAudioUnitEffect(audioComponentDescription: componentDescription)
    }

    private func createPeakLimiterUnit() -> AVAudioUnitEffect {
        var componentDescription = AudioComponentDescription()
        componentDescription.componentType = kAudioUnitType_Effect
        componentDescription.componentSubType = kAudioUnitSubType_PeakLimiter
        componentDescription.componentManufacturer = kAudioUnitManufacturer_Apple

        return AVAudioUnitEffect(audioComponentDescription: componentDescription)
    }

    // MARK: Hashable

    static func == (lhs: EffectsPlayer, rhs: EffectsPlayer) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    // MARK: - Volume

    func setVolume(_ volume: Float) {
        audioMixerNode?.outputVolume = volume
    }
}
