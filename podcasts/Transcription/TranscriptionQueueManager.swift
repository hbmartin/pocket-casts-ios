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
         thermalState: @escaping @Sendable () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState }) {
        self.dataManager = dataManager
        self.engineFactory = engineFactory
        self.artifactStore = artifactStore
        self.engineMode = engineMode
        self.audioFileURL = audioFileURL
        self.thermalState = thermalState
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
        artifactStore.delete(episodeUuid: episodeUuid)
        states[episodeUuid] = nil
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
            case .thermalThrottled:
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

        let mode = engineMode()
        let engine = try engineFactory.makeEngine(for: mode)
        guard let audioURL = audioFileURL(episodeUuid) else {
            throw TranscriptionError.notDownloaded
        }

        record.transcriptionStatus = .processing
        record.engineMode = mode.rawValue
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

        setState(episodeUuid: episodeUuid, state: .transcribing(0), forcePost: true)
        let segments = try await engine.transcribe(audioFile: audioURL,
                                                   language: languageOverride,
                                                   progress: progressHandler(episodeUuid: episodeUuid) { .transcribing($0) })
        try Task.checkCancellation()
        try checkThermal()

        // Phase 1 ships no diarizer: empty turns make the aligner emit untagged
        // (monologue) cues, which the serializer writes without <v> voice tags.
        setState(episodeUuid: episodeUuid, state: .diarizing(0), forcePost: true)
        let turns: [SpeakerTurn] = []
        let cues = SpeakerAligner.align(segments: segments, turns: turns)
        guard !cues.isEmpty else { throw TranscriptionError.engineFailure }
        setState(episodeUuid: episodeUuid, state: .diarizing(1))

        setState(episodeUuid: episodeUuid, state: .saving, forcePost: true)
        let speakerCount = Set(cues.compactMap(\.speaker)).count
        let transcript = DiarizedTranscript(cues: cues,
                                            language: languageOverride,
                                            speakerCount: speakerCount,
                                            engineDescription: engine.id)
        let artifactURL = try artifactStore.write(transcript: transcript, episodeUuid: episodeUuid)

        let searchSegments = cues.enumerated().map { index, cue in
            TranscriptionSegment(index: index, text: cue.text, startTime: cue.start, speaker: cue.speaker)
        }
        dataManager.transcriptions.replaceSegments(episodeUuid: episodeUuid,
                                                   podcastUuid: record.podcastUuid,
                                                   segments: searchSegments)

        record.transcriptionStatus = .completed
        record.errorMessage = nil
        record.durationSecs = cues.last?.end ?? 0
        record.speakerCount = Int32(speakerCount)
        record.language = languageOverride
        record.filePath = artifactURL.path
        record.updatedAt = Date().timeIntervalSince1970
        dataManager.transcriptions.upsert(record)

        setState(episodeUuid: episodeUuid, state: .completed, forcePost: true)
        NotificationCenter.postOnMainThread(EpisodeTranscriptionCompleted(episodeUuid: episodeUuid, succeeded: true))
        Analytics.track(.transcriptionCompleted, properties: [
            "episode_uuid": episodeUuid,
            "engine": engine.id,
            "cue_count": cues.count,
            "duration_seconds": Int(record.durationSecs)
        ])
        FileLog.shared.addMessage("[Transcription] completed \(episodeUuid) (\(cues.count) cues)")
    }

    // MARK: - Terminal states

    private func finishFailed(episodeUuid: String, error: TranscriptionError) {
        dataManager.transcriptions.setStatus(episodeUuid: episodeUuid, status: .failed, errorMessage: String(describing: error))
        setState(episodeUuid: episodeUuid, state: .failed(error), forcePost: true)
        NotificationCenter.postOnMainThread(EpisodeTranscriptionCompleted(episodeUuid: episodeUuid, succeeded: false))
        Analytics.track(.transcriptionFailed, properties: ["episode_uuid": episodeUuid, "error": String(describing: error)])
        FileLog.shared.addMessage("[Transcription] failed \(episodeUuid): \(error)")
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
