import AVFoundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

/// Audio pipeline reader; state is confined to its dispatch queue and the
/// semaphore-coordinated buffer hand-off.
/// @unchecked Sendable: mutable state is guarded by `lock` or confined to the read queue (see above).
nonisolated final class AudioReadTask: @unchecked Sendable {
    private let cancelled = AtomicBool()

    private let readQueue: DispatchQueue
    /// Guards the reader's mutable state. Every mutator takes it via `withLock` so an
    /// early return can never leak the lock (which is what let `shutdown()` race the
    /// read loop and free the VBN state mid-`VBN_Process`).
    private let lock = NSLock()

    private var trimSilence: TrimSilenceAmount = .off

    private var audioFile: AVAudioFile
    private var outputFormat: AVAudioFormat
    private var bufferManager: PlayBufferManager

    private let bufferLength = UInt32(Constants.Audio.defaultFrameSize)
    private let bufferByteSize = Float32(MemoryLayout<Float32>.size)

    private let detector = TrimSilenceDetector()
    private var trimParameters = TrimSilenceParameters.preset(for: .off)
    private let flatnessBox = SpectralFlatnessBox()
    private var vadAnalyzer: TrimVoiceActivityAnalyzer?
    /// Adaptive effects switching (Item 14): user toggle snapshot, the hysteresis
    /// classifier and the current music-segment flag. The classifier and flag are
    /// only touched from the read loop; the toggle refreshes with each tuning apply.
    private var adaptiveEffectsEnabled = Settings.adaptiveEffects()
    private var musicClassifier = MusicSegmentClassifier()
    private var musicSegmentActive = false
    /// True while an analyzer is being built off-thread, to avoid duplicate builds.
    private var vadAnalyzerBuilding = false
    private var gapStartFramePosition: AVAudioFramePosition = 0

    private var channelCount = 0 as UInt32
    private var buffersSavedDuringGap = SynchronizedAudioStack()
    private var fadeInNextFrame = true
    private var cachedFrameCount = 0 as Int64

    private var currentFramePosition: AVAudioFramePosition = 0
    private let endOfFileSemaphore = DispatchSemaphore(value: 0)

    private var voiceBoostNState: OpaquePointer?
    private var useVoiceBoostN: AtomicBool?
    private var useNormalize: AtomicBool?
    /// Which configuration the live VBN state was created with, so a
    /// boost ↔ normalize switch recreates it instead of reusing the wrong chain.
    private enum VBNMode { case boost, normalize }
    private var activeVBNMode: VBNMode?
    private var voiceBoostNSampleRate: Double = 0
    private var hasProcessedFirstBuffer = false
    /// Cached mono→stereo conversion objects, created once and reused per buffer
    /// (rebuilding an AVAudioConverter every read buffer is wasteful).
    private var stereoFormat: AVAudioFormat?
    private var monoToStereoConverter: AVAudioConverter?
    private var tuning: AudioTuning
    /// Integrated LUFS precomputed for this episode; 0 = unknown (adapt live).
    private let knownLUFS: Double

    init(trimSilence: TrimSilenceAmount, audioFile: AVAudioFile, outputFormat: AVAudioFormat, bufferManager: PlayBufferManager, playPositionHint: TimeInterval, frameCount: Int64, useVoiceBoostN: AtomicBool? = nil, useNormalize: AtomicBool? = nil, sampleRate: Double = 0, tuning: AudioTuning = PlaybackManager.engineState.tuning, knownLUFS: Double = 0) {
        self.trimSilence = trimSilence
        self.audioFile = audioFile
        self.outputFormat = outputFormat
        self.bufferManager = bufferManager
        cachedFrameCount = frameCount
        self.useVoiceBoostN = useVoiceBoostN
        self.useNormalize = useNormalize
        voiceBoostNSampleRate = sampleRate
        self.tuning = tuning
        self.knownLUFS = knownLUFS

        readQueue = DispatchQueue(label: "au.com.pocketcasts.ReadQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .never, target: nil)

        reconfigureDetector()

        if playPositionHint > 0 {
            currentFramePosition = framePositionForTime(playPositionHint).framePosition
            if currentFramePosition < audioFile.length {
                FileLog.shared.addMessage("Setting framePosition to \(currentFramePosition) for file: \(audioFile.url.lastPathComponent)")
                audioFile.framePosition = currentFramePosition
            } else {
                FileLog.shared.addMessage("Attempted to seek past EOF: \(currentFramePosition) >= \(audioFile.length), file: \(audioFile.url.lastPathComponent)")
                audioFile.framePosition = max(0, audioFile.length - 1)
            }
        }
    }

    func startup() {
        readQueue.async { [weak self] in
            guard let self else { return }

            // there are some Core Audio errors that aren't marked as throws in the Swift code, so they'll crash the app
            // that's why we have an Objective-C try/catch block here to catch them (see https://github.com/shiftyjelly/pocketcasts-ios/issues/1493 for more details)
            do {
                try SJCommonUtils.catchException { [weak self] in
                    guard let self else { return }

                    do {
                        while !self.cancelled.value {
                            // nil is returned when there are playback errors or us getting to the end of a file, sleep so we don't end up in a tight loop but these all set the cancelled flag
                            guard let audioBuffers = try self.readFromFile() else {
                                Thread.sleep(forTimeInterval: 0.1)
                                continue
                            }

                            for buffer in audioBuffers {
                                self.scheduleForPlayback(buffer: buffer)
                            }
                        }
                    } catch {
                        self.bufferManager.readErrorOccurred.value = true
                        FileLog.shared.addMessage("Audio Read failed (Swift): \(error.localizedDescription)")
                    }
                }
            } catch {
                self.bufferManager.readErrorOccurred.value = true
                FileLog.shared.addMessage("Audio Read failed (obj-c): \(error.localizedDescription)")
            }
        }
    }

    func shutdown() {
        // Signal first so a semaphore-parked read thread wakes and exits its loop
        // (`cancelled` is now set). THEN take `lock` to tear down: this blocks only
        // until any in-flight `readFromFile` iteration finishes, so we never free the
        // VBN state or analyzer while the read thread is using them. No deadlock: the
        // read thread never holds `lock` while blocked on a semaphore.
        cancelled.value = true
        bufferManager.bufferSemaphore.signal()
        endOfFileSemaphore.signal()

        lock.withLock {
            vadAnalyzer?.finish()
            vadAnalyzer = nil

            if let vbnState = voiceBoostNState {
                VBN_Destroy(vbnState)
                voiceBoostNState = nil
                PlaybackManager.engineState.clearVoiceBoostMeters()
                FileLog.shared.addMessage("[AudioReadTask] VoiceBoostN state destroyed on shutdown")
            }
        }
    }

    func setTrimSilence(_ trimSilence: TrimSilenceAmount) {
        lock.withLock {
            self.trimSilence = trimSilence
            reconfigureDetector()
        }
    }

    /// Live-applies a new tuning snapshot: restages the VoiceBoostN config and
    /// updates the trim gate parameters.
    func setTuning(_ tuning: AudioTuning) {
        lock.withLock {
            self.tuning = tuning
            reconfigureDetector()
            if let vbnState = voiceBoostNState {
                var config = activeVBNMode == .normalize ? tuning.vbnNormalizeConfig() : tuning.vbnConfig()
                VBN_SetConfig(vbnState, &config)
            }
        }
    }

    /// Must be called with `lock` held (or from init).
    private func reconfigureDetector() {
        trimParameters = tuning.trimParameters(for: trimSilence)
        detector.configure(parameters: trimParameters, sampleRate: audioFile.fileFormat.sampleRate, framesPerBuffer: Int(bufferLength))

        adaptiveEffectsEnabled = Settings.adaptiveEffects()
        let wantsVAD = trimSilence != .off && (trimParameters.discriminator == .vad || adaptiveEffectsEnabled)
        if wantsVAD {
            if vadAnalyzer == nil { startBuildingVADAnalyzer() }
        } else if let analyzer = vadAnalyzer {
            analyzer.finish()
            vadAnalyzer = nil
        }
    }

    /// Feeds the hysteresis classifier with the freshest speech/music confidences
    /// and logs every profile switch (Item 14 telemetry: timestamp, confidences,
    /// segment duration) so false-positive rates can be reviewed from the logs.
    private func updateMusicSegment(analyzer: TrimVoiceActivityAnalyzer, framePosition: Int64) {
        let classification = analyzer.classification(atFramePosition: framePosition)
        let seconds = TimeInterval(framePosition) / audioFile.fileFormat.sampleRate
        guard musicClassifier.analyze(speechConfidence: classification?.speech,
                                      musicConfidence: classification?.music,
                                      at: seconds) else { return }

        musicSegmentActive = musicClassifier.isMusicActive
        let confidences = classification.map { String(format: "speech %.2f music %.2f", $0.speech, $0.music) } ?? "no coverage"
        if musicSegmentActive {
            FileLog.shared.addMessage(String(format: "[AdaptiveEffects] music segment started at %.1fs (%@) — trim and voice boost suspended", seconds, confidences))
        } else {
            let duration = musicClassifier.endedSegmentDuration ?? 0
            FileLog.shared.addMessage(String(format: "[AdaptiveEffects] music segment ended at %.1fs after %.1fs (%@) — effects restored", seconds, duration, confidences))
        }
    }

    /// Builds the system VAD analyzer off the caller's thread. Its init synchronously
    /// loads a CoreML sound-classifier model, which must not run on the main actor
    /// (`setTuning`/`setTrimSilence` are called there) or while holding `lock` (that
    /// stalls the read thread). Installs the finished analyzer under `lock`; until then
    /// the detector runs with the heuristic features it already computes.
    /// Called with `lock` held (or from init).
    private func startBuildingVADAnalyzer() {
        guard !vadAnalyzerBuilding else { return }
        vadAnalyzerBuilding = true
        let sampleRate = audioFile.processingFormat.sampleRate
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let built: TrimVoiceActivityAnalyzer?
            do {
                built = try TrimVoiceActivityAnalyzer(sampleRate: sampleRate)
            } catch {
                built = nil
                FileLog.shared.addMessage("[AudioReadTask] system VAD unavailable, falling back to heuristic gating: \(error.localizedDescription)")
            }
            self.lock.withLock {
                self.vadAnalyzerBuilding = false
                let stillWantsVAD = self.trimSilence != .off && (self.trimParameters.discriminator == .vad || self.adaptiveEffectsEnabled)
                guard let built else { return }
                if stillWantsVAD, self.vadAnalyzer == nil {
                    self.vadAnalyzer = built
                    FileLog.shared.addMessage("[AudioReadTask] system VAD analyzer active for trim silence")
                } else {
                    built.finish()
                }
            }
        }
    }

    func seekTo(_ time: TimeInterval, completion: ((Bool) -> Void)?) {
        let boxedCompletion = PocketCastsUtils.UncheckedSendable(completion)
        DispatchQueue.global(qos: .default).async { () in
            let seekResult = self.performSeek(time)
            self.bufferManager.bufferSemaphore.signal()
            boxedCompletion.value?(seekResult)
        }
    }

    private func performSeek(_ time: TimeInterval) -> Bool {
        lock.withLock {
            let positionRequired = framePositionForTime(time)
            var seekedToEnd = false

            if positionRequired.passedEndOfFile {
                bufferManager.removeAll()
                bufferManager.readToEOFSuccessfully.value = true

                seekedToEnd = true
            } else {
                currentFramePosition = positionRequired.framePosition
                audioFile.framePosition = currentFramePosition
                bufferManager.aboutToSeek()
                detector.reset()
                buffersSavedDuringGap.removeAll()
                fadeInNextFrame = true

                // stream analyzers can't rewind; recreate after the seek
                if let analyzer = vadAnalyzer {
                    analyzer.finish()
                    vadAnalyzer = nil
                    reconfigureDetector()
                }
                musicClassifier.reset()
                musicSegmentActive = false

                if let vbnState = voiceBoostNState {
                    VBN_Reset(vbnState)
                    FileLog.shared.addMessage("[AudioReadTask] VoiceBoostN state reset after seek")
                }

                // if we've finished reading this file, wake the reading thread back up
                if bufferManager.readToEOFSuccessfully.value {
                    endOfFileSemaphore.signal()
                }
            }

            return seekedToEnd
        }
    }

    private func handleReachedEndOfFile() {
        bufferManager.readToEOFSuccessfully.value = true

        // we've read to the end but the player won't yet have played to the end, wait til it signals us that it has
        endOfFileSemaphore.wait()
    }

    /// Result of one locked read pass. `reachedEndOfFile` handling waits on a
    /// semaphore and so is performed by the caller AFTER `lock` is released.
    private enum ReadOutcome {
        case reachedEndOfFile
        case readError
        case buffers([BufferedAudio])
    }

    private func readFromFile() throws -> [BufferedAudio]? {
        let outcome: ReadOutcome = try lock.withLock {
            // are we at the end of the file?
            currentFramePosition = audioFile.framePosition
            if currentFramePosition >= cachedFrameCount {
                return .reachedEndOfFile
            }

            guard let audioPCMBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: bufferLength) else {
                FileLog.shared.addMessage("[AudioReadTask] failed to allocate read buffer")
                bufferManager.readErrorOccurred.value = true
                cancelled.value = true
                return .readError
            }

            do {
                try audioFile.read(into: audioPCMBuffer)
            } catch {
                FileLog.shared.addMessage("[AudioReadTask] read failed: \(error.localizedDescription)")
                throw error
            }

            // check that we actually read something
            if audioPCMBuffer.frameLength == 0 {
                return .reachedEndOfFile
            }

            // Handle dynamic VoiceBoostN state creation/destruction (single-threaded
            // under `lock`; `shutdown()` takes the same lock before freeing this state).
            // Boost wins over normalize (the documented interlock); a mode switch
            // recreates the state so the right chain (full boost vs gain+limiter
            // only) is configured.
            let requestedMode: VBNMode? = if useVoiceBoostN?.value == true {
                .boost
            } else if useNormalize?.value == true {
                .normalize
            } else {
                nil
            }

            if requestedMode != activeVBNMode, voiceBoostNState != nil {
                VBN_Destroy(voiceBoostNState)
                voiceBoostNState = nil
                PlaybackManager.engineState.clearVoiceBoostMeters()
                FileLog.shared.addMessage("[AudioReadTask] VBN mode changed mid-playback (\(String(describing: activeVBNMode)) -> \(String(describing: requestedMode)))")
            }

            if let requestedMode, voiceBoostNState == nil {
                var config = requestedMode == .boost ? tuning.vbnConfig() : tuning.vbnNormalizeConfig()
                voiceBoostNState = VBN_CreateWithConfig(voiceBoostNSampleRate, &config)
                if let vbnState = voiceBoostNState, knownLUFS != 0 {
                    // seed the gain from the precomputed loudness so playback starts
                    // at the right level instead of adapting over the first seconds
                    VBN_SetInitialGainDB(vbnState, config.targetLUFS - Float(knownLUFS))
                }
                let modeName = requestedMode == .boost ? "VoiceBoostN" : "Normalize"
                if hasProcessedFirstBuffer {
                    FileLog.shared.addMessage("[AudioReadTask] \(modeName) enabled mid-playback - created state at \(voiceBoostNSampleRate) Hz")
                } else {
                    FileLog.shared.addMessage("[AudioReadTask] \(modeName) enabled - created state at \(voiceBoostNSampleRate) Hz\(knownLUFS != 0 ? " (seeded from \(knownLUFS) LUFS)" : "")")
                }
            }
            activeVBNMode = requestedMode
            hasProcessedFirstBuffer = true

            // Process through VoiceBoostN if enabled — suspended inside music
            // segments (adaptive effects): boosting music squashes its dynamics.
            if let vbnState = voiceBoostNState, !musicSegmentActive, let channelData = audioPCMBuffer.floatChannelData {
                let frameCount = Int32(audioPCMBuffer.frameLength)
                let bufferChannelCount = Int32(audioPCMBuffer.format.channelCount)

                var channelPointers: [UnsafeMutablePointer<Float>?] = []
                for i in 0..<Int(bufferChannelCount) {
                    channelPointers.append(channelData[i])
                }

                channelPointers.withUnsafeMutableBufferPointer { ptr in
                    VBN_Process(vbnState, ptr.baseAddress, frameCount, bufferChannelCount)
                }

                PlaybackManager.engineState.publishVoiceBoostMeters(.init(
                    gainDB: VBN_GetCurrentGainDB(vbnState),
                    measuredLUFS: VBN_GetMeasuredLUFS(vbnState),
                    limiterReductionDB: VBN_GetLimiterReductionDB(vbnState)
                ))
            }

            currentFramePosition = audioFile.framePosition
            fadeInNextFrame = false
            if channelCount == 0 { channelCount = audioPCMBuffer.audioBufferList.pointee.mNumberBuffers }

            if channelCount == 0 {
                bufferManager.readErrorOccurred.value = true
                cancelled.value = true
                return .readError
            }

            // iOS 16 has an issue in which if the conditions below are met, the playback will fail:
            // Audio file has a single channel and spatial audio is enabled
            // In order to prevent this issue, we convert a mono buffer to stereo buffer
            // For more info, see: https://github.com/Automattic/pocket-casts-ios/issues/62
            let audioBuffer: BufferedAudio
            if audioPCMBuffer.audioBufferList.pointee.mNumberBuffers == 1,
               let stereoBuffer = makeStereoBuffer(from: audioPCMBuffer) {
                audioBuffer = BufferedAudio(audioBuffer: stereoBuffer, framePosition: currentFramePosition, shouldFadeOut: false, shouldFadeIn: fadeInNextFrame)
            } else {
                audioBuffer = BufferedAudio(audioBuffer: audioPCMBuffer, framePosition: currentFramePosition, shouldFadeOut: false, shouldFadeIn: fadeInNextFrame)
            }

            var buffers = [BufferedAudio]()
            if trimSilence != .off {
                let bufferListPointer = UnsafeMutableAudioBufferListPointer(audioPCMBuffer.mutableAudioBufferList)

                let currPosition = currentFramePosition / Int64(audioFile.fileFormat.sampleRate)
                let totalDuration = cachedFrameCount / Int64(audioFile.fileFormat.sampleRate)
                let timeLeft = totalDuration - currPosition

                let rms = (channelCount == 1) ? AudioUtils.calculateRms(bufferListPointer[0]) : AudioUtils.calculateStereoRms(bufferListPointer[0], rightBuffer: bufferListPointer[1])
                var features = TrimFeatureFrame(rmsDB: 20 * log10(max(rms, 1e-7)))

                if trimParameters.discriminator != .rms {
                    features.zeroCrossingRate = AudioUtils.calculateZeroCrossingRate(bufferListPointer[0])
                    features.spectralFlatness = flatnessBox.spectralFlatness(of: bufferListPointer[0])
                }
                if let analyzer = vadAnalyzer, trimParameters.discriminator == .vad || adaptiveEffectsEnabled {
                    analyzer.append(audioPCMBuffer, atFramePosition: currentFramePosition)
                    if trimParameters.discriminator == .vad {
                        features.vadSpeechConfidence = analyzer.speechConfidence(atFramePosition: currentFramePosition)
                    }
                    if adaptiveEffectsEnabled {
                        updateMusicSegment(analyzer: analyzer, framePosition: currentFramePosition)
                    }
                }

                let stashedCount = buffersSavedDuringGap.count()
                if stashedCount == 0 {
                    gapStartFramePosition = currentFramePosition
                }

                var decision = detector.analyze(features, stashedCount: stashedCount, timeLeft: TimeInterval(timeLeft))

                // retrospective VAD veto: never drop a gap the classifier heard speech in
                if case .endGapTrim = decision,
                   let analyzer = vadAnalyzer,
                   analyzer.speechDetected(inFrameRange: gapStartFramePosition ..< currentFramePosition, aboveConfidence: Float(trimParameters.vadSpeechConfidenceThreshold)) == true {
                    decision = .endGapEmitAll
                    FileLog.shared.addMessage("[AudioReadTask] VAD vetoed a silence trim (speech detected in gap)")
                }

                // Adaptive effects: never open or close a trim gap inside a music
                // segment — musical quiet is content, not silence.
                if musicSegmentActive {
                    switch decision {
                    case .stash, .endGapTrim:
                        decision = stashedCount > 0 ? .endGapEmitAll : .passthrough
                    case .passthrough, .endGapEmitAll:
                        break
                    }
                }

                switch decision {
                case .passthrough:
                    buffers.append(audioBuffer)
                case .stash:
                    buffersSavedDuringGap.push(audioBuffer)
                case .endGapEmitAll:
                    // the gap was too short to trim, push it all back
                    while buffersSavedDuringGap.canPop() {
                        buffers.append(buffersSavedDuringGap.pop()!)
                    }
                    buffers.append(audioBuffer)
                case .endGapTrim(let keepBuffers):
                    appendTrimmedGap(keepBuffers: keepBuffers, resume: audioBuffer, into: &buffers)
                }
            } else {
                buffers.append(audioBuffer)
            }

            return .buffers(buffers)
        }

        switch outcome {
        case .reachedEndOfFile:
            // Waits on the end-of-file semaphore; must run with `lock` released.
            handleReachedEndOfFile()
            return nil
        case .readError:
            return nil
        case .buffers(let buffers):
            return buffers
        }
    }

    /// Converts a mono buffer to stereo (working around an iOS 16 spatial-audio bug for
    /// single-channel files), reusing a cached converter/format instead of allocating an
    /// `AVAudioConverter` per buffer. Returns nil (caller falls back to the mono buffer)
    /// if setup or conversion fails, rather than emitting a silent buffer. Called with `lock` held.
    private func makeStereoBuffer(from monoBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if stereoFormat == nil {
            stereoFormat = AVAudioFormat(standardFormatWithSampleRate: audioFile.processingFormat.sampleRate, channels: 2)
        }
        guard let stereoFormat,
              let stereoBuffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: monoBuffer.frameCapacity) else {
            return nil
        }
        if monoToStereoConverter == nil {
            monoToStereoConverter = AVAudioConverter(from: audioFile.processingFormat, to: stereoFormat)
        }
        do {
            try monoToStereoConverter?.convert(to: stereoBuffer, from: monoBuffer)
        } catch {
            FileLog.shared.addMessage("[AudioReadTask] mono→stereo conversion failed, using mono buffer: \(error.localizedDescription)")
            return nil
        }
        return stereoBuffer
    }

    /// Reassembles a trimmed gap: keeps the head of the gap (start of the
    /// pause), drops the middle, keeps a short tail leading back into speech,
    /// and splices — either with the legacy fade-out/fade-in or, when
    /// configured, an equal-power crossfade across the cut.
    private func appendTrimmedGap(keepBuffers: Int, resume: BufferedAudio, into buffers: inout [BufferedAudio]) {
        let sampleRate = audioFile.fileFormat.sampleRate
        let crossfadeFrames = detector.crossfadeFrames

        if crossfadeFrames > 0 {
            // crossfade splice: keep `keepBuffers` head buffers (or a short
            // overlap carrier when none are kept), drop the middle, keep the
            // legacy-sized tail, and overlap across the cut
            var head = [BufferedAudio]()
            for _ in 0 ..< max(keepBuffers, 1) {
                guard let buffer = buffersSavedDuringGap.pop() else { break }
                head.append(buffer)
            }
            if keepBuffers == 0, let carrier = head.first {
                AudioUtils.truncate(carrier.audioBuffer, toFrames: crossfadeFrames)
            }

            while buffersSavedDuringGap.canPop(), buffersSavedDuringGap.count() > max(0, keepBuffers - 1) {
                if let dropped = buffersSavedDuringGap.pop() {
                    StatsManager.shared.addTimeSavedDynamicSpeed(Double(dropped.audioBuffer.frameLength) / sampleRate)
                }
            }

            var tail = [BufferedAudio]()
            while buffersSavedDuringGap.canPop() {
                tail.append(buffersSavedDuringGap.pop()!)
            }

            if let outgoing = head.last {
                let incoming = tail.first ?? resume
                let overlap = min(crossfadeFrames, Int(outgoing.audioBuffer.frameLength), Int(incoming.audioBuffer.frameLength))
                if overlap > 1 {
                    AudioUtils.crossfadeSplice(outgoing: outgoing.audioBuffer, incoming: incoming.audioBuffer, overlapFrames: overlap)
                    AudioUtils.trimLeadingFrames(incoming.audioBuffer, frames: overlap)
                    StatsManager.shared.addTimeSavedDynamicSpeed(Double(overlap) / sampleRate)
                }
            }

            buffers.append(contentsOf: head)
            buffers.append(contentsOf: tail)
            buffers.append(resume)
            return
        }

        // legacy splice: keep keepBuffers+1 head buffers (fading the last out),
        // drop the middle, keep the last keepBuffers-1 as the tail, fade the
        // resume buffer back in
        for index in 0 ... keepBuffers {
            guard let buffer = buffersSavedDuringGap.pop() else { break }
            if index < keepBuffers {
                buffers.append(buffer)
            } else {
                // fade out the last frame to avoid a jarring re-attach
                AudioUtils.fadeAudio(buffer, fadeOut: true, channelCount: channelCount)
                buffers.append(buffer)
            }
        }

        // pop all the ones we don't need after that
        while buffersSavedDuringGap.canPop(), buffersSavedDuringGap.count() > (keepBuffers - 1) {
            if let dropped = buffersSavedDuringGap.pop() {
                StatsManager.shared.addTimeSavedDynamicSpeed(Double(dropped.audioBuffer.frameLength) / sampleRate)
            }
        }

        while buffersSavedDuringGap.canPop() {
            buffers.append(buffersSavedDuringGap.pop()!)
        }

        // fade back in the new frame
        AudioUtils.fadeAudio(resume, fadeOut: false, channelCount: channelCount)
        buffers.append(resume)
    }

    private func scheduleForPlayback(buffer: BufferedAudio) {
        // the play task will signal us when it needs more buffer, but it will keep signalling as long as the buffer is low, so keep calling wait until we get below the high point
        while !cancelled.value, bufferManager.bufferLength() >= bufferManager.highBufferPoint {
            bufferManager.bufferSemaphore.wait()
        }

        if !cancelled.value {
            bufferManager.push(buffer)
        }
    }

    private func framePositionForTime(_ time: TimeInterval) -> (framePosition: Int64, passedEndOfFile: Bool) {
        let totalFrames = Double(cachedFrameCount)
        let totalSeconds = totalFrames / audioFile.fileFormat.sampleRate
        let percentSeek = time / totalSeconds

        return (Int64(totalFrames * percentSeek), percentSeek >= 1)
    }
}
