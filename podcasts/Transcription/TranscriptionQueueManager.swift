import BackgroundTasks
import Foundation
import PocketCastsDataModel
import PocketCastsTranscription
import PocketCastsUtils
import UIKit

/// Serial job queue for locally generated diarized transcriptions.
///
/// One job runs at a time (transcription is CPU/battery heavy). The
/// `EpisodeTranscription` DB row is the durable job record: `restorePendingJobs()`
/// re-enqueues `queued` rows on launch and resets rows a crash left `processing`.
/// Progress fans out to the UI via `TranscriptionProgress` notifications (throttled
/// to ~1/sec inside a stage), terminal states via `EpisodeTranscriptionCompleted`.
actor TranscriptionQueueManager {
    /// Lifecycle of a single transcription job, surfaced through `state(for:)` and
    /// carried (as `stageName`/fraction) in `TranscriptionProgress` notifications.
    nonisolated enum JobState: Equatable, Sendable {
        case queued
        case preparingModel(Double)
        case transcribing(Double)
        case diarizing(Double)
        case saving
        case completed
        case failed(TranscriptionError)
        case cancelled

        /// Stable stage label carried in `TranscriptionProgress.stage`.
        var stageName: String {
            switch self {
            case .queued: "queued"
            case .preparingModel: "preparing_model"
            case .transcribing: "transcribing"
            case .diarizing: "diarizing"
            case .saving: "saving"
            case .completed: "completed"
            case .failed: "failed"
            case .cancelled: "cancelled"
            }
        }

        /// Pipeline position, used to reject out-of-order state writes from
        /// asynchronously delivered progress callbacks.
        var stageOrder: Int {
            switch self {
            case .queued: 0
            case .preparingModel: 1
            case .transcribing: 2
            case .diarizing: 3
            case .saving: 4
            case .completed, .failed, .cancelled: 5
            }
        }

        /// 0…1 within the current stage.
        var fractionCompleted: Double {
            switch self {
            case .preparingModel(let fraction), .transcribing(let fraction), .diarizing(let fraction):
                fraction
            case .completed:
                1
            case .queued, .saving, .failed, .cancelled:
                0
            }
        }
    }

    /// Polling cadence for asynchronous remote-provider jobs: 3s, backing off
    /// ×1.5 per poll to a 30s cap, bounded overall at 30 minutes. Tests inject a
    /// near-zero schedule.
    nonisolated struct PollSchedule: Sendable {
        var initialInterval: TimeInterval = 3
        var backoffFactor: Double = 1.5
        var maxInterval: TimeInterval = 30
        var overallTimeout: TimeInterval = 30 * 60

        static let `default` = PollSchedule()
    }

    static let shared = TranscriptionQueueManager()

    /// Must match the BGTaskSchedulerPermittedIdentifiers entry in podcasts-Info.plist.
    static let backgroundTaskId = "au.com.shiftyjelly.podcasts.Transcription"

    private static let progressPostInterval: TimeInterval = 1.0

    /// Why an in-flight job's Task was cancelled: a user cancel becomes `.cancelled`,
    /// a deferral (BG task expiration) puts the job back to `.queued`.
    private enum CancelIntent { case user, requeue }

    private let dataManager: DataManager
    private let engineFactory: any TranscriptionEngineProviding
    private let artifactStore: TranscriptionArtifactStore
    private let engineMode: @Sendable () -> TranscriptionEngineMode
    private let audioFileURL: @Sendable (String) -> URL?
    private let thermalState: @Sendable () -> ProcessInfo.ThermalState
    private let powerState: @Sendable () async -> TranscriptionPowerState
    private let batteryPolicy: @Sendable () -> TranscriptionBatteryPolicy
    private let podcastDisablesRemote: @Sendable (String?) -> Bool
    private let remoteConsent: @Sendable (String) -> Bool
    private let maxSpeakers: @Sendable () -> Int
    private let remoteProviderId: @Sendable () -> String
    private let remoteAPIKey: @Sendable (String) -> String?
    private let episodeDownloadURL: @Sendable (String) -> URL?
    private let transcodeForUpload: @Sendable (URL) async throws -> AudioTranscodeHelper.Output
    private let pollSchedule: PollSchedule

    private var states: [String: JobState] = [:]
    private var pendingEpisodeUuids: [String] = []
    private var drainTask: Task<Void, Never>?
    private var currentJob: (episodeUuid: String, task: Task<Void, Never>)?
    private var cancelIntents: [String: CancelIntent] = [:]
    private var lastPostedStage: String?
    private var lastProgressPostDate = Date.distantPast

    init(dataManager: DataManager = .sharedManager,
         engineFactory: any TranscriptionEngineProviding = TranscriptionEngineFactory(),
         artifactStore: TranscriptionArtifactStore = TranscriptionArtifactStore(),
         engineMode: @escaping @Sendable () -> TranscriptionEngineMode = { TranscriptionEngineFactory.currentMode() },
         audioFileURL: @escaping @Sendable (String) -> URL? = { episodeUuid in
             guard let episode = DataManager.sharedManager.findBaseEpisode(uuid: episodeUuid),
                   episode.downloaded(pathFinder: DownloadManager.shared) else { return nil }
             return URL(fileURLWithPath: episode.pathToDownloadedFile(pathFinder: DownloadManager.shared))
         },
         thermalState: @escaping @Sendable () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
         powerState: @escaping @Sendable () async -> TranscriptionPowerState = { await TranscriptionPowerState.current() },
         batteryPolicy: @escaping @Sendable () -> TranscriptionBatteryPolicy = { Settings.transcriptionBatteryPolicy() },
         podcastDisablesRemote: @escaping @Sendable (String?) -> Bool = { podcastUuid in
             guard let podcastUuid, let podcast = DataManager.sharedManager.findPodcast(uuid: podcastUuid) else { return false }
             return podcast.settings.disableRemoteTranscription
         },
         remoteConsent: @escaping @Sendable (String) -> Bool = { TranscriptionConsentGate.hasConsent(providerId: $0) },
         maxSpeakers: @escaping @Sendable () -> Int = { Settings.transcriptionMaxSpeakers() },
         remoteProviderId: @escaping @Sendable () -> String = { Settings.transcriptionRemoteProvider() },
         remoteAPIKey: @escaping @Sendable (String) -> String? = { TranscriptionKeyStore.apiKey(providerId: $0) },
         episodeDownloadURL: @escaping @Sendable (String) -> URL? = { episodeUuid in
             guard let episode = DataManager.sharedManager.findBaseEpisode(uuid: episodeUuid),
                   let urlString = episode.downloadUrl,
                   let url = URL(string: urlString),
                   let scheme = url.scheme?.lowercased(),
                   scheme == "http" || scheme == "https" else { return nil }
             return url
         },
         transcodeForUpload: @escaping @Sendable (URL) async throws -> AudioTranscodeHelper.Output = {
             try await AudioTranscodeHelper().transcodeForUpload(sourceURL: $0)
         },
         pollSchedule: PollSchedule = .default) {
        self.dataManager = dataManager
        self.engineFactory = engineFactory
        self.artifactStore = artifactStore
        self.engineMode = engineMode
        self.audioFileURL = audioFileURL
        self.thermalState = thermalState
        self.powerState = powerState
        self.batteryPolicy = batteryPolicy
        self.podcastDisablesRemote = podcastDisablesRemote
        self.remoteConsent = remoteConsent
        self.maxSpeakers = maxSpeakers
        self.remoteProviderId = remoteProviderId
        self.remoteAPIKey = remoteAPIKey
        self.episodeDownloadURL = episodeDownloadURL
        self.transcodeForUpload = transcodeForUpload
        self.pollSchedule = pollSchedule
    }

    // MARK: - Public API

    /// Creates (or resets) the episode's transcription record as `queued` and kicks
    /// the drain. A no-op when the episode is already queued or in flight.
    func enqueue(episodeUuid: String, podcastUuid: String?) {
        guard !isEpisodeQueued(episodeUuid), !isEpisodeProcessing(episodeUuid) else { return }

        var record = dataManager.transcriptions.find(episodeUuid: episodeUuid) ?? EpisodeTranscriptionRecord()
        if record.episodeUuid.isEmpty {
            record.episodeUuid = episodeUuid
            record.createdAt = Date().timeIntervalSince1970
        }
        if let podcastUuid {
            record.podcastUuid = podcastUuid
        }
        record.transcriptionStatus = .queued
        record.errorMessage = nil
        // A fresh enqueue never resumes an old remote job; only requeue/restore
        // paths (which bypass enqueue) keep the job id for poll resumption.
        record.remoteJobId = nil
        record.updatedAt = Date().timeIntervalSince1970
        dataManager.transcriptions.upsert(record)

        cancelIntents[episodeUuid] = nil
        setState(episodeUuid: episodeUuid, state: .queued, forcePost: true)
        pendingEpisodeUuids.append(episodeUuid)
        drainIfNeeded()
    }

    /// Cancels a queued or in-flight job. The record moves to `cancelled` and an
    /// `EpisodeTranscriptionCompleted(succeeded: false)` is posted.
    func cancel(episodeUuid: String) {
        if let currentJob, currentJob.episodeUuid == episodeUuid {
            cancelIntents[episodeUuid] = .user
            currentJob.task.cancel()
            return
        }
        guard let index = pendingEpisodeUuids.firstIndex(of: episodeUuid) else { return }
        pendingEpisodeUuids.remove(at: index)
        finishCancelled(episodeUuid: episodeUuid)
    }

    func state(for episodeUuid: String) -> JobState? {
        states[episodeUuid]
    }

    func isEpisodeQueued(_ episodeUuid: String) -> Bool {
        pendingEpisodeUuids.contains(episodeUuid)
    }

    func isEpisodeProcessing(_ episodeUuid: String) -> Bool {
        currentJob?.episodeUuid == episodeUuid
    }

    /// Re-enqueues every pending DB record: `queued` rows join the queue as-is,
    /// and rows a crash left `processing` are reset to `queued` first.
    func restorePendingJobs() {
        for record in dataManager.transcriptions.pendingRecords() {
            let episodeUuid = record.episodeUuid
            guard !episodeUuid.isEmpty, !isEpisodeQueued(episodeUuid), !isEpisodeProcessing(episodeUuid) else { continue }
            if record.transcriptionStatus == .processing {
                // A previous run died mid-job; the work is safe to redo from scratch.
                dataManager.transcriptions.setStatus(episodeUuid: episodeUuid, status: .queued)
            }
            states[episodeUuid] = .queued
            pendingEpisodeUuids.append(episodeUuid)
        }
        drainIfNeeded()
    }

    /// Removes the generated transcript entirely: DB record, FTS segment rows and
    /// the VTT artifact on disk (the DAO deliberately leaves files to the app layer).
    func deleteTranscription(episodeUuid: String) {
        if let index = pendingEpisodeUuids.firstIndex(of: episodeUuid) {
            pendingEpisodeUuids.remove(at: index)
        }
        if let currentJob, currentJob.episodeUuid == episodeUuid {
            cancelIntents[episodeUuid] = .user
            currentJob.task.cancel()
        }
        dataManager.transcriptions.delete(episodeUuid: episodeUuid)
        dataManager.transcriptSearch.delete(episodeUuid: episodeUuid, source: .generated)
        artifactStore.delete(episodeUuid: episodeUuid)
        states[episodeUuid] = nil
    }

    /// Settings "Clear All": removes every generated transcription — records,
    /// FTS rows and VTT artifacts — cancelling any queued or in-flight jobs.
    func deleteAllTranscriptions() {
        for record in dataManager.transcriptions.allRecords() where !record.episodeUuid.isEmpty {
            deleteTranscription(episodeUuid: record.episodeUuid)
        }
    }

    /// Suspends until the drain loop goes idle (queue empty, or deferred by
    /// thermal/expiration). Used by the BGProcessingTask handler and tests.
    func drainUntilIdle() async {
        while let task = drainTask {
            await task.value
        }
    }

    /// BGProcessingTask expiration: put the in-flight job back to `queued` (not
    /// `cancelled`) so the next charging pass resumes it.
    func deferForBackgroundExpiration() {
        guard let currentJob else { return }
        cancelIntents[currentJob.episodeUuid] = .requeue
        currentJob.task.cancel()
    }

    // MARK: - Drain

    private func drainIfNeeded() {
        guard drainTask == nil, !pendingEpisodeUuids.isEmpty else { return }
        drainTask = Task { await self.drainLoop() }
    }

    private func drainLoop() async {
        defer { drainTask = nil }

        while !pendingEpisodeUuids.isEmpty {
            guard !isThermallyThrottled else {
                // Leave the remaining jobs queued; the requiresExternalPower
                // BGProcessingTask pass picks them up when the device is cooler.
                FileLog.shared.addMessage("[Transcription] drain deferred: thermal state too high")
                break
            }

            let episodeUuid = pendingEpisodeUuids.removeFirst()
            let job = Task { await self.execute(episodeUuid: episodeUuid) }
            currentJob = (episodeUuid, job)
            await job.value
            currentJob = nil
            cancelIntents[episodeUuid] = nil

            if states[episodeUuid] == .queued {
                // The job deferred itself back to the queue (thermal throttle or
                // background expiration): keep it pending but stop draining.
                if !pendingEpisodeUuids.contains(episodeUuid) {
                    pendingEpisodeUuids.append(episodeUuid)
                }
                break
            }
        }
    }

    private func execute(episodeUuid: String) async {
        let backgroundTask = await TranscriptionBackgroundTask.begin()
        do {
            try await run(episodeUuid: episodeUuid)
        } catch is CancellationError {
            finishCancelledOrRequeued(episodeUuid: episodeUuid)
        } catch let error as TranscriptionError {
            switch error {
            case .cancelled:
                finishCancelledOrRequeued(episodeUuid: episodeUuid)
            case .thermalThrottled, .powerDeferred:
                requeue(episodeUuid: episodeUuid)
            default:
                finishFailed(episodeUuid: episodeUuid, error: error)
            }
        } catch {
            finishFailed(episodeUuid: episodeUuid, error: .engineFailure)
        }
        await backgroundTask.end()
    }

    // MARK: - Pipeline

    private func run(episodeUuid: String) async throws {
        guard var record = dataManager.transcriptions.find(episodeUuid: episodeUuid) else {
            // Record deleted while queued (e.g. via deleteTranscription) — nothing to do.
            states[episodeUuid] = nil
            return
        }

        // Engine resolution: the remote provider is used only when it is the
        // global mode, the user has consented to it, and the podcast hasn't
        // opted out — otherwise the job falls back to the on-device pipeline.
        // Re-resolved on every run so setting changes apply to queued jobs.
        let globalMode = engineMode()
        if globalMode == .remoteProvider,
           !podcastDisablesRemote(record.podcastUuid),
           remoteConsent(remoteProviderId()) {
            try await runRemote(episodeUuid: episodeUuid, record: record)
            return
        }

        let mode = globalMode == .remoteProvider ? .appleBuiltIn : globalMode
        // Local transcription is compute-heavy: the battery policy defers it
        // (remote jobs cost network, not battery, and return above).
        try await checkPower()

        let engine = try engineFactory.makeEngine(for: mode)
        guard let audioURL = audioFileURL(episodeUuid) else {
            throw TranscriptionError.notDownloaded
        }

        record.transcriptionStatus = .processing
        record.engineMode = mode.rawValue
        // Provenance: which engine build produced this transcript (e.g.
        // "whisperkit.openai_whisper-small" or "apple.speechanalyzer").
        record.modelId = engine.id
        record.errorMessage = nil
        record.updatedAt = Date().timeIntervalSince1970
        dataManager.transcriptions.upsert(record)
        setState(episodeUuid: episodeUuid, state: .preparingModel(0), forcePost: true)
        Analytics.track(.transcriptionStarted, properties: ["episode_uuid": episodeUuid, "engine": engine.id])

        let languageOverride = Settings.transcriptionLanguageOverride()

        try await engine.prepare(locale: languageOverride.map(Locale.init(identifier:)),
                                 progress: progressHandler(episodeUuid: episodeUuid) { .preparingModel($0) })
        try Task.checkCancellation()
        try checkThermal()
        try await checkPower()

        setState(episodeUuid: episodeUuid, state: .transcribing(0), forcePost: true)
        let segments = try await engine.transcribe(audioFile: audioURL,
                                                   language: languageOverride,
                                                   progress: progressHandler(episodeUuid: episodeUuid) { .transcribing($0) })
        try Task.checkCancellation()
        try checkThermal()
        try await checkPower()

        setState(episodeUuid: episodeUuid, state: .diarizing(0), forcePost: true)
        let turns = try await diarize(episodeUuid: episodeUuid, audioURL: audioURL)
        let cues = SpeakerAligner.align(segments: segments, turns: turns)
        guard !cues.isEmpty else { throw TranscriptionError.engineFailure }
        setState(episodeUuid: episodeUuid, state: .diarizing(1))

        let speakerCount = Set(cues.compactMap(\.speaker)).count
        let transcript = DiarizedTranscript(cues: cues,
                                            language: languageOverride,
                                            speakerCount: speakerCount,
                                            engineDescription: engine.id)
        try complete(episodeUuid: episodeUuid, record: record, transcript: transcript)
    }

    /// The shared SpeakerKit diarizer stage, run for BOTH local pipeline modes
    /// (Apple ASR + SpeakerKit is the diarized built-in mode, WhisperKit +
    /// SpeakerKit the local-model one).
    ///
    /// Diarization is best-effort: any failure — diarizer model download blocked
    /// by the cellular gate, engine error, no diarizer configured — logs and
    /// falls back to empty turns so the job still completes as a monologue.
    /// Only cancellation propagates and fails the job.
    private func diarize(episodeUuid: String, audioURL: URL) async throws -> [SpeakerTurn] {
        guard let diarizer = engineFactory.makeDiarizer() else { return [] }

        do {
            // Model download/load is a small share of the stage; the analysis
            // pass over the full episode dominates.
            try await diarizer.prepare(progress: progressHandler(episodeUuid: episodeUuid) { .diarizing(0.2 * $0) })
            try Task.checkCancellation()
            let cap = maxSpeakers()
            return try await diarizer.diarize(audioFile: audioURL,
                                              maxSpeakers: cap > 0 ? cap : nil,
                                              progress: progressHandler(episodeUuid: episodeUuid) { .diarizing(0.2 + 0.8 * $0) })
        } catch is CancellationError {
            throw TranscriptionError.cancelled
        } catch TranscriptionError.cancelled {
            throw TranscriptionError.cancelled
        } catch {
            FileLog.shared.addMessage("[Transcription] diarization failed for \(episodeUuid), continuing as monologue: \(error)")
            return []
        }
    }

    // MARK: - Remote pipeline

    /// Mode 2: the transcript is produced by a hosted API using the user's own
    /// key. Stages map as: `preparingModel` = source resolution + transcode +
    /// upload, `transcribing` = provider-side processing (poll loop for async
    /// providers), then the shared `saving` path.
    private func runRemote(episodeUuid: String, record: EpisodeTranscriptionRecord) async throws {
        var record = record

        // A job id left on the record (crash/expiration mid-poll) means audio was
        // already submitted — resume polling instead of paying for a second job.
        let resumeJobId = record.engineMode == TranscriptionEngineMode.remoteProvider.rawValue
            ? record.remoteJobId : nil
        let providerId = (resumeJobId != nil ? record.provider : nil) ?? remoteProviderId()

        guard let provider = engineFactory.makeRemoteProvider(id: providerId) else {
            throw TranscriptionError.remoteJobFailed("Unknown transcription provider: \(providerId)")
        }
        guard let apiKey = remoteAPIKey(providerId) else {
            throw TranscriptionError.invalidAPIKey
        }

        record.transcriptionStatus = .processing
        record.engineMode = TranscriptionEngineMode.remoteProvider.rawValue
        record.provider = providerId
        record.errorMessage = nil
        record.updatedAt = Date().timeIntervalSince1970
        dataManager.transcriptions.upsert(record)

        let language = Settings.transcriptionLanguageOverride()

        if let resumeJobId {
            FileLog.shared.addMessage("[Transcription] resuming remote job \(resumeJobId) (\(providerId)) for \(episodeUuid)")
            setState(episodeUuid: episodeUuid, state: .transcribing(0), forcePost: true)
            let handle = RemoteJobHandle(providerId: providerId, jobId: resumeJobId)
            let transcript = try await pollUntilComplete(provider: provider, handle: handle, apiKey: apiKey, episodeUuid: episodeUuid)
            try complete(episodeUuid: episodeUuid, record: record, transcript: transcript)
            return
        }

        setState(episodeUuid: episodeUuid, state: .preparingModel(0), forcePost: true)
        Analytics.track(.transcriptionStarted, properties: ["episode_uuid": episodeUuid, "engine": providerId])

        let (source, temporaryUploadFile) = try await resolveRemoteSource(episodeUuid: episodeUuid, provider: provider)
        defer {
            if let temporaryUploadFile {
                try? FileManager.default.removeItem(at: temporaryUploadFile)
            }
        }
        try Task.checkCancellation()

        setState(episodeUuid: episodeUuid, state: .transcribing(0), forcePost: true)
        let outcome = try await provider.submit(source: source, language: language, apiKey: apiKey)

        switch outcome {
        case .completed(let transcript):
            try complete(episodeUuid: episodeUuid, record: record, transcript: transcript)
        case .job(let handle):
            // Persist before the first poll so a crash/expiration can resume
            // the job instead of re-submitting it.
            dataManager.transcriptions.setRemoteJobId(episodeUuid: episodeUuid, jobId: handle.jobId)
            record.remoteJobId = handle.jobId
            let transcript = try await pollUntilComplete(provider: provider, handle: handle, apiKey: apiKey, episodeUuid: episodeUuid)
            try complete(episodeUuid: episodeUuid, record: record, transcript: transcript)
        }
    }

    /// Prefers the episode's public URL for providers that can fetch it (also
    /// covers non-downloaded episodes); otherwise transcodes the downloaded file
    /// for upload. Returns the temp transcode URL (if any) for cleanup.
    private func resolveRemoteSource(episodeUuid: String,
                                     provider: any RemoteTranscriptionProvider) async throws -> (RemoteAudioSource, temporaryUploadFile: URL?) {
        if provider.supportsPublicURL, let downloadURL = episodeDownloadURL(episodeUuid) {
            return (.publicURL(downloadURL), nil)
        }
        guard let audioURL = audioFileURL(episodeUuid) else {
            throw TranscriptionError.notDownloaded
        }
        let output = try await transcodeForUpload(audioURL)
        return (.fileUpload(output.url, mimeType: output.mimeType), output.isTemporary ? output.url : nil)
    }

    /// Polls an asynchronous remote job on `pollSchedule` (default 3s ×1.5 → 30s
    /// cap) until it completes, fails, or the 30-minute overall deadline passes.
    /// Cancellation is honored between every wait and request.
    private func pollUntilComplete(provider: any RemoteTranscriptionProvider,
                                   handle: RemoteJobHandle,
                                   apiKey: String,
                                   episodeUuid: String) async throws -> DiarizedTranscript {
        let deadline = Date().addingTimeInterval(pollSchedule.overallTimeout)
        var interval = pollSchedule.initialInterval
        var lastFraction: Double = 0

        while true {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(max(interval, 0) * 1_000_000_000))
            try Task.checkCancellation()

            switch try await provider.poll(handle: handle, apiKey: apiKey) {
            case .completed(let transcript):
                return transcript
            case .failed(let error):
                throw error
            case .processing(let fraction):
                lastFraction = fraction ?? lastFraction
                setState(episodeUuid: episodeUuid, state: .transcribing(lastFraction))
            }

            guard Date() < deadline else {
                throw TranscriptionError.remoteJobFailed("timeout")
            }
            interval = min(interval * pollSchedule.backoffFactor, pollSchedule.maxInterval)
        }
    }

    // MARK: - Completion

    /// Shared tail of both pipelines: write the VTT artifact, replace the FTS
    /// segments, finalize the record and announce completion.
    private func complete(episodeUuid: String, record: EpisodeTranscriptionRecord, transcript: DiarizedTranscript) throws {
        guard !transcript.cues.isEmpty else { throw TranscriptionError.engineFailure }

        var record = record
        setState(episodeUuid: episodeUuid, state: .saving, forcePost: true)
        let artifactURL = try artifactStore.write(transcript: transcript, episodeUuid: episodeUuid)

        let searchSegments = transcript.cues.enumerated().map { index, cue in
            TranscriptSearchSegment(index: index, text: cue.text, startTime: cue.start, endTime: cue.end, speaker: cue.speaker)
        }
        dataManager.transcriptSearch.replaceSegments(episodeUuid: episodeUuid,
                                                     podcastUuid: record.podcastUuid,
                                                     source: .generated,
                                                     segments: searchSegments)

        record.transcriptionStatus = .completed
        record.errorMessage = nil
        record.durationSecs = transcript.cues.last?.end ?? 0
        record.speakerCount = Int32(transcript.speakerCount)
        record.language = transcript.language
        record.remoteJobId = nil
        record.filePath = artifactURL.path
        record.updatedAt = Date().timeIntervalSince1970
        dataManager.transcriptions.upsert(record)

        setState(episodeUuid: episodeUuid, state: .completed, forcePost: true)
        NotificationCenter.postOnMainThread(EpisodeTranscriptionCompleted(episodeUuid: episodeUuid, succeeded: true))
        NotificationCenter.postOnMainThread(TranscriptIndexUpdated(uuid: episodeUuid))
        Analytics.track(.transcriptionCompleted, properties: [
            "episode_uuid": episodeUuid,
            "engine": transcript.engineDescription,
            "cue_count": transcript.cues.count,
            "duration_seconds": Int(record.durationSecs)
        ])
        FileLog.shared.addMessage("[Transcription] completed \(episodeUuid) (\(transcript.cues.count) cues)")
    }

    // MARK: - Terminal states

    private func finishFailed(episodeUuid: String, error: TranscriptionError) {
        // Provider-generated failure text can echo request ids or user data, so
        // only the sanitized description crosses into the record, analytics and
        // the shareable file log; the full error stays in the in-memory state.
        let sanitized = error.sanitizedDescription
        dataManager.transcriptions.setStatus(episodeUuid: episodeUuid, status: .failed, errorMessage: sanitized)
        setState(episodeUuid: episodeUuid, state: .failed(error), forcePost: true)
        NotificationCenter.postOnMainThread(EpisodeTranscriptionCompleted(episodeUuid: episodeUuid, succeeded: false))
        Analytics.track(.transcriptionFailed, properties: ["episode_uuid": episodeUuid, "error": sanitized])
        FileLog.shared.addMessage("[Transcription] failed \(episodeUuid): \(sanitized)")
    }

    private func finishCancelledOrRequeued(episodeUuid: String) {
        if cancelIntents[episodeUuid] == .requeue {
            requeue(episodeUuid: episodeUuid)
        } else {
            finishCancelled(episodeUuid: episodeUuid)
        }
    }

    private func finishCancelled(episodeUuid: String) {
        dataManager.transcriptions.setStatus(episodeUuid: episodeUuid, status: .cancelled)
        setState(episodeUuid: episodeUuid, state: .cancelled, forcePost: true)
        NotificationCenter.postOnMainThread(EpisodeTranscriptionCompleted(episodeUuid: episodeUuid, succeeded: false))
        Analytics.track(.transcriptionCancelled, properties: ["episode_uuid": episodeUuid])
        FileLog.shared.addMessage("[Transcription] cancelled \(episodeUuid)")
    }

    private func requeue(episodeUuid: String) {
        dataManager.transcriptions.setStatus(episodeUuid: episodeUuid, status: .queued)
        setState(episodeUuid: episodeUuid, state: .queued, forcePost: true)
        FileLog.shared.addMessage("[Transcription] job deferred back to the queue: \(episodeUuid)")
    }

    // MARK: - Thermal

    private var isThermallyThrottled: Bool {
        switch thermalState() {
        case .serious, .critical: true
        default: false
        }
    }

    private func checkThermal() throws {
        if isThermallyThrottled {
            throw TranscriptionError.thermalThrottled
        }
    }

    /// Local-pipeline checkpoints only; remote jobs never consult the battery.
    private func checkPower() async throws {
        if TranscriptionPowerState.isDeferred(policy: batteryPolicy(), state: await powerState()) {
            FileLog.shared.addMessage("[Transcription] deferred by battery policy; job stays queued")
            throw TranscriptionError.powerDeferred
        }
    }

    /// Battery level/charging state/Low Power Mode changed: a power-deferred
    /// queue may be runnable again. Called from the app-level observers.
    func powerConditionsChanged() {
        drainIfNeeded()
    }

    // MARK: - Progress

    /// Engine progress callbacks arrive on arbitrary threads; hop onto the actor
    /// where `noteProgress` applies the ~1/sec notification throttle.
    nonisolated private func progressHandler(episodeUuid: String,
                                             state: @escaping @Sendable (Double) -> JobState) -> @Sendable (Double) -> Void {
        { [weak self] fraction in
            guard let self else { return }
            Task { await self.noteProgress(episodeUuid: episodeUuid, state: state(fraction)) }
        }
    }

    private func noteProgress(episodeUuid: String, state: JobState) {
        // Drop late callbacks once the job left the running slot (cancelled/finished).
        guard currentJob?.episodeUuid == episodeUuid else { return }
        // Engine progress closures hop onto the actor asynchronously, so a final
        // in-stage callback can arrive after the pipeline already advanced the
        // stage (or finished). Never let a progress update regress the state.
        if let existing = states[episodeUuid], existing.stageOrder > state.stageOrder { return }
        setState(episodeUuid: episodeUuid, state: state)
    }

    /// Updates the in-memory job state and posts a `TranscriptionProgress`
    /// notification, throttled to ~1/sec inside a stage. Stage transitions and
    /// terminal states always post (`forcePost` or a stage-name change).
    private func setState(episodeUuid: String, state: JobState, forcePost: Bool = false) {
        states[episodeUuid] = state

        let now = Date()
        let stageChanged = state.stageName != lastPostedStage
        guard forcePost || stageChanged || now.timeIntervalSince(lastProgressPostDate) >= Self.progressPostInterval else { return }
        lastPostedStage = state.stageName
        lastProgressPostDate = now
        NotificationCenter.postOnMainThread(TranscriptionProgress(episodeUuid: episodeUuid,
                                                                  stage: state.stageName,
                                                                  progress: state.fractionCompleted))
    }
}

// MARK: - BGProcessingTask

extension TranscriptionQueueManager {
    /// Registers the charging-time queue drain. Must be called before the app
    /// finishes launching (from `AppDelegate.setupBackgroundRefresh()`).
    @MainActor
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskId, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleBackgroundTask(processingTask)
        }
    }

    /// Submits a `BGProcessingTaskRequest` when transcription work is pending.
    /// `requiresExternalPower` keeps heavy ASR work to charging sessions.
    nonisolated static func scheduleProcessingTaskIfNeeded(dataManager: DataManager = .sharedManager) {
        guard FeatureFlag.diarizedTranscription.enabled else { return }
        guard !dataManager.transcriptions.pendingRecords().isEmpty else { return }

        let request = BGProcessingTaskRequest(identifier: backgroundTaskId)
        request.requiresExternalPower = true
        // First-run locale assets may still need downloading.
        request.requiresNetworkConnectivity = true
        do {
            try BGTaskScheduler.shared.submit(request)
            FileLog.shared.addMessage("[Transcription] scheduled background processing task")
        } catch {
            FileLog.shared.addMessage("[Transcription] could not schedule background processing task: \(error.localizedDescription)")
        }
    }

    nonisolated private static func handleBackgroundTask(_ task: BGProcessingTask) {
        FileLog.shared.addMessage("[Transcription] background processing task started")
        let boxedTask = PocketCastsUtils.UncheckedSendable(task)
        task.expirationHandler = {
            FileLog.shared.addMessage("[Transcription] background processing task expired")
            Task { await TranscriptionQueueManager.shared.deferForBackgroundExpiration() }
        }
        Task {
            await shared.restorePendingJobs()
            await shared.drainUntilIdle()
            // Work can remain (thermal/expiration deferral) — ask for another pass.
            scheduleProcessingTaskIfNeeded()
            boxedTask.value.setTaskCompleted(success: true)
        }
    }
}

// MARK: - Background task guard

/// Keeps the app alive while a transcription job is in flight after the user
/// backgrounds the app. The task is ended in BOTH the expiration handler and the
/// job-completion path (`end()` is idempotent).
@MainActor
private final class TranscriptionBackgroundTask {
    private var taskId: UIBackgroundTaskIdentifier = .invalid

    static func begin() -> TranscriptionBackgroundTask {
        let holder = TranscriptionBackgroundTask()
        holder.taskId = UIApplication.shared.beginBackgroundTask(withName: "au.com.pocketcasts.transcription.job") {
            // Expiration: release immediately; interrupted jobs are recovered as
            // `processing` → `queued` by restorePendingJobs on the next launch or
            // by the BGProcessingTask pass.
            holder.end()
        }
        return holder
    }

    func end() {
        guard taskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskId)
        taskId = .invalid
    }
}
