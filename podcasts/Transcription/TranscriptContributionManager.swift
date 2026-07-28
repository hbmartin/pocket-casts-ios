import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsTranscription
import PocketCastsUtils

/// Serial drain loop for the transcript-contribution upload queue
/// (docs/TranscriptContributions.md §2): the `PendingTranscriptUpload` rows a
/// completed transcription (Contribution) or a first-viewed Provided
/// transcript (Sighting) enqueue.
///
/// One row is processed at a time. Contributions locate the episode's
/// downloaded audio, fingerprint it through `ReferenceFingerprintEncoder`
/// (cached on disk next to the VTT artifact so retries never re-decode the
/// audio), gzip the VTT artifact and upload; sightings just replay the URL
/// metadata captured at enqueue time. An accepted contribution leaves behind a
/// compact Metadata row that generates the on-device summary/chapters and
/// attaches them with the receipt's one-time token. Contribution and sighting
/// rows have **no terminal give-up** — a row persists until the server accepts
/// it, rejects it as permanently invalid, or its transcription is deleted
/// locally (tombstone check before every send); metadata rows additionally
/// give up after `maxMetadataAttempts` failed attempts because their one-time
/// attachment token is candidate-scoped. Failed attempts back off
/// exponentially (capped at 6 h) and a server `pauseQueue` parks the whole
/// queue behind a persisted date. Contribution fingerprinting and metadata
/// generation obey the same battery policy as transcription jobs; lightweight
/// sightings remain network-only and are not power-gated.
actor TranscriptContributionManager {
    static let shared = TranscriptContributionManager()

    /// UserDefaults key holding the `pauseQueue` park date (epoch seconds).
    static let pausedUntilDefaultsKey = "TranscriptContributions.pausedUntil"

    /// Retries never wait longer than this, whatever the attempt count or
    /// server-provided Retry-After.
    static let maxRetryInterval: TimeInterval = 6 * 60 * 60

    /// Cadence for retrying a blocked metadata job (model unavailable,
    /// transient attach failure): weekly, in addition to lifecycle kicks once
    /// the row is due (docs/TranscriptContributions.md).
    static let metadataRetryInterval: TimeInterval = 7 * 24 * 60 * 60

    /// A metadata job that keeps failing (e.g. generation output stays outside
    /// the 150–250-word / 3–8-chapter contract) is dropped after this many
    /// attempts instead of re-running the map/reduce weekly forever.
    static let maxMetadataAttempts: Int32 = 26

    // MARK: - Payload JSON

    /// Contribution fields captured at enqueue time (`payloadJson`, kind 0).
    nonisolated struct ContributionInfo: Codable, Equatable, Sendable {
        var engine: String
        var modelId: String
        var language: String?
        var diarized: Bool
        var durationSeconds: Double
        /// Contribution creation time, epoch seconds.
        var createdAt: Double
    }

    /// Sighting fields captured at enqueue time (`payloadJson`, kind 1).
    nonisolated struct SightingInfo: Codable, Equatable, Sendable {
        var url: String
        var format: String
        var language: String?
    }

    /// Compact durable state retained after the transcript upload succeeds.
    /// The attachment token is candidate-scoped and consumed by the backend on
    /// the first successful metadata POST.
    nonisolated struct MetadataInfo: Codable, Equatable, Sendable {
        var candidateID: String
        var attachmentToken: String
    }

    // MARK: - Dependencies (all injectable for tests)

    private let dataManager: DataManager
    private let artifactStore: TranscriptionArtifactStore
    private let audioFileURL: @Sendable (String) -> URL?
    private let fingerprint: @Sendable (URL) async throws -> Data
    private let gzip: @Sendable (Data) throws -> Data
    private let sendContribution: @Sendable (TranscriptContributionPayload) async -> ContributionSendResult
    private let sendSighting: @Sendable (TranscriptSightingPayload) async -> ContributionSendResult
    private let generateMetadata: @Sendable (String, String, MetadataInfo) async -> CorpusMetadataAttachment?
    private let sendMetadata: @Sendable (CorpusMetadataAttachment) async -> ContributionSendResult
    private let powerState: @Sendable () async -> TranscriptionPowerState
    private let batteryPolicy: @Sendable () -> TranscriptionBatteryPolicy
    private let handleAttestationRejection: @Sendable () async -> Void
    private let appVersion: @Sendable () -> String
    private let loadPausedUntil: @Sendable () -> Date?
    private let storePausedUntil: @Sendable (Date?) -> Void
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    private var drainTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var wakeDate: Date?
    private var wakeID: UUID?
    private var drainRequestedAfterCurrentRun = false

    init(dataManager: DataManager = .sharedManager,
         artifactStore: TranscriptionArtifactStore = TranscriptionArtifactStore(),
         audioFileURL: @escaping @Sendable (String) -> URL? = { episodeUuid in
             // Same mechanism as TranscriptionQueueManager's audio resolution:
             // the fingerprint must be cut from the exact bytes the transcript was.
             guard let episode = DataManager.sharedManager.findBaseEpisode(uuid: episodeUuid),
                   episode.downloaded(pathFinder: DownloadManager.shared) else { return nil }
             return URL(fileURLWithPath: episode.pathToDownloadedFile(pathFinder: DownloadManager.shared))
         },
         fingerprint: @escaping @Sendable (URL) async throws -> Data = { try await ReferenceFingerprintEncoder.fingerprint(audioFileURL: $0) },
         gzip: @escaping @Sendable (Data) throws -> Data = { try ReferenceFingerprintEncoder.gzipped($0) },
         sendContribution: @escaping @Sendable (TranscriptContributionPayload) async -> ContributionSendResult = { await TranscriptContributeTask().send($0) },
         sendSighting: @escaping @Sendable (TranscriptSightingPayload) async -> ContributionSendResult = { await TranscriptSightingTask().send($0) },
         generateMetadata: @escaping @Sendable (String, String, MetadataInfo) async -> CorpusMetadataAttachment? = { episodeUuid, podcastUuid, info in
             await TranscriptCorpusMetadataGenerator.shared.generate(
                 episodeUUID: episodeUuid,
                 podcastUUID: podcastUuid,
                 candidateID: info.candidateID,
                 attachmentToken: info.attachmentToken
             )
         },
         sendMetadata: @escaping @Sendable (CorpusMetadataAttachment) async -> ContributionSendResult = { await CorpusMetadataAttachmentClient.attachResult($0) },
         powerState: @escaping @Sendable () async -> TranscriptionPowerState = { await TranscriptionPowerState.current() },
         batteryPolicy: @escaping @Sendable () -> TranscriptionBatteryPolicy = { Settings.transcriptionBatteryPolicy() },
         handleAttestationRejection: @escaping @Sendable () async -> Void = { await AppAttestService.shared.handleAttestationRejection() },
         appVersion: @escaping @Sendable () -> String = { Settings.appVersion() },
         loadPausedUntil: @escaping @Sendable () -> Date? = {
             let stamp = UserDefaults.standard.double(forKey: TranscriptContributionManager.pausedUntilDefaultsKey)
             return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
         },
         storePausedUntil: @escaping @Sendable (Date?) -> Void = { date in
             if let date {
                 UserDefaults.standard.set(date.timeIntervalSince1970, forKey: TranscriptContributionManager.pausedUntilDefaultsKey)
             } else {
                 UserDefaults.standard.removeObject(forKey: TranscriptContributionManager.pausedUntilDefaultsKey)
             }
         },
         now: @escaping @Sendable () -> Date = { Date() },
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { interval in
             try await Task.sleep(for: .seconds(interval))
         }) {
        self.dataManager = dataManager
        self.artifactStore = artifactStore
        self.audioFileURL = audioFileURL
        self.fingerprint = fingerprint
        self.gzip = gzip
        self.sendContribution = sendContribution
        self.sendSighting = sendSighting
        self.generateMetadata = generateMetadata
        self.sendMetadata = sendMetadata
        self.powerState = powerState
        self.batteryPolicy = batteryPolicy
        self.handleAttestationRejection = handleAttestationRejection
        self.appVersion = appVersion
        self.loadPausedUntil = loadPausedUntil
        self.storePausedUntil = storePausedUntil
        self.now = now
        self.sleep = sleep
    }

    // MARK: - Public API

    /// Starts the drain if it isn't already running. Cheap to call from every
    /// hook (launch, enqueue, power change): a paused/deferred/empty queue
    /// no-ops immediately.
    func kick() {
        guard drainTask == nil else { return }
        drainTask = Task { await self.drainLoop() }
    }

    /// Fire-and-forget kick of the shared manager from nonisolated contexts.
    nonisolated static func kickShared() {
        Task { await TranscriptContributionManager.shared.kick() }
    }

    /// Suspends until the drain loop goes idle. Used by tests.
    func drainUntilIdle() async {
        while let task = drainTask {
            await task.value
        }
    }

    /// Exponential backoff for the given (post-increment) attempt count:
    /// 60 s, 120 s, 240 s… capped at `maxRetryInterval`.
    nonisolated static func backoffInterval(attempts: Int32) -> TimeInterval {
        let exponent = Double(min(max(Int(attempts) - 1, 0), 16))
        return min(60 * pow(2, exponent), maxRetryInterval)
    }

    // MARK: - Enqueue (Contribution)

    /// Enqueues a contribution for a transcription that just completed, when
    /// the episode is Eligible. Called by `TranscriptionQueueManager.complete()`
    /// via its injected hook; the caller kicks the drain when this returns true.
    ///
    /// The payload metadata (engine, model, language, diarization, duration)
    /// is captured now, from the completed record and the episode row; the
    /// heavyweight artifacts (VTT bytes, fingerprint) are produced at send time.
    @discardableResult
    nonisolated static func enqueueContribution(episodeUuid: String,
                                                record: EpisodeTranscriptionRecord,
                                                dataManager: DataManager) -> Bool {
        let episode = dataManager.findBaseEpisode(uuid: episodeUuid)
        guard let podcastUuid = record.podcastUuid ?? (episode as? Episode)?.podcastUuid else { return false }
        let podcast = dataManager.findPodcast(uuid: podcastUuid, includeUnsubscribed: true)
        let hasCredentials = LocalFeedCredentials.credentials(podcastUuid: podcastUuid) != nil
        guard TranscriptContributionEligibility.isEligible(episode: episode, podcast: podcast, hasStoredFeedCredentials: hasCredentials) else { return false }

        let episodeDuration = episode?.duration ?? 0
        let durationSeconds = episodeDuration > 0 ? episodeDuration : record.durationSecs
        let info = ContributionInfo(engine: engineIdentifier(for: record),
                                    modelId: record.modelId ?? record.provider ?? "",
                                    language: record.language,
                                    diarized: record.speakerCount > 1,
                                    durationSeconds: durationSeconds,
                                    createdAt: Date().timeIntervalSince1970)
        guard let payloadJson = encodePayload(info) else { return false }

        var row = PendingTranscriptUploadRecord()
        row.episodeUuid = episodeUuid
        row.podcastUuid = podcastUuid
        row.uploadKind = .contribution
        row.payloadJson = payloadJson
        return dataManager.pendingTranscriptUploads.insert(row)
    }

    // MARK: - Enqueue (Sighting)

    /// Reports the first successful load of an episode's Provided-transcript
    /// metadata: enqueues a sighting row (deduplicated locally per episode)
    /// when the episode is Eligible and the URL is token-free, then kicks the
    /// drain. Safe to call on every transcript load.
    nonisolated static func noteSighting(episodeUuid: String,
                                         podcastUuid: String,
                                         transcriptUrl: String,
                                         format: String,
                                         language: String?,
                                         dataManager: DataManager = .sharedManager,
                                         kickAfterInsert: Bool = true) {
        let episode = dataManager.findBaseEpisode(uuid: episodeUuid)
        let podcast = dataManager.findPodcast(uuid: podcastUuid, includeUnsubscribed: true)
        let hasCredentials = LocalFeedCredentials.credentials(podcastUuid: podcastUuid) != nil
        guard TranscriptContributionEligibility.isEligible(episode: episode, podcast: podcast, hasStoredFeedCredentials: hasCredentials),
              TranscriptContributionEligibility.isTokenFreeURL(transcriptUrl) else { return }

        let info = SightingInfo(url: transcriptUrl, format: format, language: language)
        guard let payloadJson = encodePayload(info) else { return }

        var row = PendingTranscriptUploadRecord()
        row.episodeUuid = episodeUuid
        row.podcastUuid = podcastUuid
        row.uploadKind = .sighting
        row.payloadJson = payloadJson
        if dataManager.pendingTranscriptUploads.insertIfAbsent(row), kickAfterInsert {
            kickShared()
        }
    }

    // MARK: - Drain

    private func drainLoop() async {
        defer {
            drainTask = nil
            if drainRequestedAfterCurrentRun {
                drainRequestedAfterCurrentRun = false
                kick()
            }
        }

        var lastProcessed: (id: Int64, kind: Int32, attempts: Int32)?
        while true {
            let currentDate = now()
            if let pausedUntil = loadPausedUntil(), currentDate < pausedUntil {
                // Operator kill switch (docs/TranscriptContributions.md §5):
                // the queue stays parked until the persisted deadline.
                scheduleWake(at: pausedUntil)
                break
            }

            let contributionDeferred = TranscriptionPowerState.isDeferred(policy: batteryPolicy(), state: await powerState())
            let row: PendingTranscriptUploadRecord?
            if contributionDeferred {
                // Sightings are tiny network-only reports. Keep draining them even
                // when an older contribution (audio fingerprint decode) or metadata
                // job (on-device map/reduce generation) is waiting for
                // battery-friendly power conditions (including App Store builds
                // where battery monitoring is intentionally not initialized).
                row = dataManager.pendingTranscriptUploads.nextDue(at: currentDate, kind: .sighting)
                if row == nil, dataManager.pendingTranscriptUploads.nextDue(at: currentDate) != nil {
                    FileLog.shared.addMessage("[TranscriptContribution] contribution drain deferred by battery policy")
                }
            } else {
                row = dataManager.pendingTranscriptUploads.nextDue(at: currentDate)
            }
            guard let row, let rowId = row.id else {
                let scheduledKind: PendingTranscriptUploadKind? = contributionDeferred ? .sighting : nil
                if let retryDate = dataManager.pendingTranscriptUploads.nextScheduledAttempt(after: currentDate, kind: scheduledKind) {
                    scheduleWake(at: retryDate)
                }
                break
            }
            if let lastProcessed, rowId == lastProcessed.id, row.kind == lastProcessed.kind, row.attempts == lastProcessed.attempts {
                // The previous pass failed to advance this row (e.g. a retry-state
                // write failed): stop rather than hammer the server in a tight
                // loop. A kind change (an accepted contribution transitioning to
                // its metadata job resets attempts 0 → 0) counts as progress.
                FileLog.shared.addMessage("[TranscriptContribution] drain stalled on row \(lastProcessed.id); stopping until the next kick")
                break
            }
            lastProcessed = (rowId, row.kind, row.attempts)
            await process(row)
        }
    }

    private func process(_ row: PendingTranscriptUploadRecord) async {
        guard let rowId = row.id else {
            // Defensive: rows fetched from the DB always carry their PK.
            return
        }

        let result: ContributionSendResult?
        switch row.uploadKind {
        case .contribution:
            result = await processContribution(row)
        case .sighting:
            result = await processSighting(row)
        case .metadata:
            result = await processMetadata(row)
        }
        guard let result else { return } // Row already handled (tombstoned, dropped or rescheduled).

        switch result {
        case .accepted:
            dataManager.pendingTranscriptUploads.delete(id: rowId)
            if row.uploadKind == .contribution {
                artifactStore.deleteFingerprint(episodeUuid: row.episodeUuid)
            }
            FileLog.shared.addMessage("[TranscriptContribution] accepted \(row.uploadKind) for \(row.episodeUuid)")
        case .acceptedContribution(let receipt):
            if row.uploadKind == .contribution,
               let payload = Self.encodePayload(MetadataInfo(
                   candidateID: receipt.candidateID,
                   attachmentToken: receipt.attachmentToken
               )),
               dataManager.pendingTranscriptUploads.transitionToMetadata(id: rowId, payloadJson: payload) {
                artifactStore.deleteFingerprint(episodeUuid: row.episodeUuid)
                FileLog.shared.addMessage("[TranscriptContribution] transcript accepted; metadata job retained for \(row.episodeUuid)")
            } else {
                // The payload IS accepted server-side; retrying would re-upload
                // an already-accepted payload, potentially forever. A receipt on
                // a non-contribution row or a failed transition is
                // success-with-cleanup — only the metadata follow-up is lost.
                FileLog.shared.addMessage("[TranscriptContribution] accepted \(row.uploadKind) for \(row.episodeUuid); metadata follow-up not retained")
                dataManager.pendingTranscriptUploads.delete(id: rowId)
                if row.uploadKind == .contribution {
                    artifactStore.deleteFingerprint(episodeUuid: row.episodeUuid)
                }
            }
        case .retryAfter(let interval):
            scheduleRetry(row: row, rowId: rowId, minimumDelay: interval)
        case .pauseQueue(let interval):
            // The operator parked the whole queue; the row itself is untouched.
            let pausedUntil = now().addingTimeInterval(interval)
            storePausedUntil(pausedUntil)
            scheduleWake(at: pausedUntil)
            FileLog.shared.addMessage("[TranscriptContribution] queue paused for \(Int(interval))s by server")
        case .attestationRejected:
            await handleAttestationRejection()
            scheduleRetry(row: row, rowId: rowId, minimumDelay: 60)
        case .permanentFailure(let message):
            // Validation failures can never succeed with the same bytes — the
            // one terminal case. Delete the row (and the now-useless cache).
            FileLog.shared.addMessage("[TranscriptContribution] permanent failure for \(row.episodeUuid): \(message)")
            dataManager.pendingTranscriptUploads.delete(id: rowId)
            if row.uploadKind == .contribution {
                artifactStore.deleteFingerprint(episodeUuid: row.episodeUuid)
            }
        }
    }

    /// nil = the row was handled internally (tombstoned/dropped) and no send happened.
    private func processContribution(_ row: PendingTranscriptUploadRecord) async -> ContributionSendResult? {
        guard let rowId = row.id else { return nil }

        // Tombstone check before every send: deleting the transcription locally
        // cancels pending uploads (deleteTranscription also clears rows, but a
        // send racing the delete must not resurrect the contribution).
        guard let record = dataManager.transcriptions.find(episodeUuid: row.episodeUuid),
              record.transcriptionStatus == .completed else {
            FileLog.shared.addMessage("[TranscriptContribution] dropping contribution for \(row.episodeUuid): transcription deleted")
            removeContributionRow(id: rowId, episodeUuid: row.episodeUuid)
            return nil
        }
        guard let vtt = artifactStore.read(episodeUuid: row.episodeUuid) else {
            // The VTT artifact is gone (excluded from device backups); this row
            // can never produce its payload again.
            FileLog.shared.addMessage("[TranscriptContribution] dropping contribution for \(row.episodeUuid): VTT artifact missing")
            removeContributionRow(id: rowId, episodeUuid: row.episodeUuid)
            return nil
        }
        guard let info: ContributionInfo = Self.decodePayload(row.payloadJson) else {
            FileLog.shared.addMessage("[TranscriptContribution] dropping contribution for \(row.episodeUuid): undecodable payload")
            removeContributionRow(id: rowId, episodeUuid: row.episodeUuid)
            return nil
        }

        // Fingerprint, with disk cache: retries and relaunches must not
        // re-decode the whole audio file.
        let gzippedFingerprint: Data
        if let cached = artifactStore.readFingerprint(episodeUuid: row.episodeUuid) {
            gzippedFingerprint = cached
        } else {
            guard let audioURL = audioFileURL(row.episodeUuid) else {
                // The downloaded audio is gone. A re-download may be a different
                // ad stitch, so a fingerprint computed later could mismatch the
                // transcript — this contribution is unrecoverable.
                FileLog.shared.addMessage("[TranscriptContribution] dropping contribution for \(row.episodeUuid): audio no longer downloaded")
                removeContributionRow(id: rowId, episodeUuid: row.episodeUuid)
                return nil
            }
            do {
                let json = try await fingerprint(audioURL)
                gzippedFingerprint = try gzip(json)
                try artifactStore.writeFingerprint(gzippedFingerprint, episodeUuid: row.episodeUuid)
            } catch {
                // Fingerprinting failures are deterministic for the same file
                // (unreadable/empty audio) — treat as unrecoverable rather than
                // retrying a CPU-heavy decode forever.
                FileLog.shared.addMessage("[TranscriptContribution] dropping contribution for \(row.episodeUuid): fingerprint failed: \(error)")
                removeContributionRow(id: rowId, episodeUuid: row.episodeUuid)
                return nil
            }
        }

        let gzippedVtt: Data
        do {
            gzippedVtt = try gzip(Data(vtt.utf8))
        } catch {
            FileLog.shared.addMessage("[TranscriptContribution] dropping contribution for \(row.episodeUuid): VTT gzip failed: \(error)")
            removeContributionRow(id: rowId, episodeUuid: row.episodeUuid)
            return nil
        }

        let payload = TranscriptContributionPayload(episodeUuid: row.episodeUuid,
                                                    podcastUuid: row.podcastUuid,
                                                    gzippedVtt: gzippedVtt,
                                                    gzippedFingerprint: gzippedFingerprint,
                                                    engine: info.engine,
                                                    modelId: info.modelId,
                                                    language: info.language ?? "",
                                                    diarized: info.diarized,
                                                    appVersion: appVersion(),
                                                    episodeDurationSeconds: info.durationSeconds,
                                                    createdAt: Date(timeIntervalSince1970: info.createdAt))
        return await sendContribution(payload)
    }

    /// nil = the row was dropped (undecodable payload) and no send happened.
    private func processSighting(_ row: PendingTranscriptUploadRecord) async -> ContributionSendResult? {
        guard let rowId = row.id else { return nil }
        guard let info: SightingInfo = Self.decodePayload(row.payloadJson) else {
            FileLog.shared.addMessage("[TranscriptContribution] dropping sighting for \(row.episodeUuid): undecodable payload")
            dataManager.pendingTranscriptUploads.delete(id: rowId)
            return nil
        }
        let payload = TranscriptSightingPayload(episodeUuid: row.episodeUuid,
                                                podcastUuid: row.podcastUuid,
                                                transcriptUrl: info.url,
                                                format: info.format,
                                                language: info.language)
        return await sendSighting(payload)
    }

    /// nil = the row was handled internally (dropped or rescheduled) and the
    /// generic result handling must not touch it again.
    private func processMetadata(_ row: PendingTranscriptUploadRecord) async -> ContributionSendResult? {
        guard let rowId = row.id else { return nil }
        guard let info: MetadataInfo = Self.decodePayload(row.payloadJson) else {
            FileLog.shared.addMessage("[TranscriptContribution] dropping metadata job for \(row.episodeUuid): undecodable payload")
            dataManager.pendingTranscriptUploads.delete(id: rowId)
            return nil
        }
        guard artifactStore.read(episodeUuid: row.episodeUuid) != nil else {
            // The VTT artifact is the generation input; without it this job can
            // never produce its metadata (mirrors the contribution tombstone).
            FileLog.shared.addMessage("[TranscriptContribution] dropping metadata job for \(row.episodeUuid): VTT artifact missing")
            dataManager.pendingTranscriptUploads.delete(id: rowId)
            return nil
        }
        guard let metadata = await generateMetadata(row.episodeUuid, row.podcastUuid, info) else {
            // Model assets/lifecycle can be unavailable for long periods. Keep
            // the compact job and retry weekly — bounded by maxMetadataAttempts —
            // in addition to lifecycle kicks.
            scheduleMetadataRetry(row: row, rowId: rowId)
            return nil
        }
        let result = await sendMetadata(metadata)
        if case .retryAfter = result {
            // Weekly cadence instead of the send backoff: every retry re-runs
            // the expensive map/reduce, and the attempt budget still applies.
            scheduleMetadataRetry(row: row, rowId: rowId)
            return nil
        }
        // accepted deletes the row; permanentFailure (the one-time token is
        // consumed/expired) tombstones it; pause/attestation results use the
        // shared queue handling.
        return result
    }

    private func scheduleMetadataRetry(row: PendingTranscriptUploadRecord, rowId: Int64) {
        let attempts = row.attempts + 1
        guard attempts < Self.maxMetadataAttempts else {
            FileLog.shared.addMessage("[TranscriptContribution] dropping metadata job for \(row.episodeUuid): giving up after \(attempts) attempts")
            dataManager.pendingTranscriptUploads.delete(id: rowId)
            return
        }
        let retryDate = now().addingTimeInterval(Self.metadataRetryInterval)
        if dataManager.pendingTranscriptUploads.setRetryState(
            id: rowId,
            attempts: attempts,
            nextAttemptAt: retryDate
        ) {
            scheduleWake(at: retryDate)
        }
    }

    private func scheduleRetry(row: PendingTranscriptUploadRecord, rowId: Int64, minimumDelay: TimeInterval) {
        let attempts = row.attempts + 1
        let delay = min(max(minimumDelay, Self.backoffInterval(attempts: attempts)), Self.maxRetryInterval)
        let retryDate = now().addingTimeInterval(delay)
        if dataManager.pendingTranscriptUploads.setRetryState(id: rowId,
                                                              attempts: attempts,
                                                              nextAttemptAt: retryDate) {
            scheduleWake(at: retryDate)
        }
    }

    /// Arms one cancellable wake-up for the earliest known retry/pause deadline.
    /// The wait runs outside actor isolation; only the deadline handoff returns to
    /// this actor. New earlier deadlines replace the existing task.
    private func scheduleWake(at date: Date) {
        if let wakeDate, wakeDate <= date { return }

        wakeTask?.cancel()
        let id = UUID()
        let delay = max(0, date.timeIntervalSince(now()))
        wakeDate = date
        wakeID = id
        let sleep = self.sleep
        wakeTask = Task { @concurrent in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self.scheduledWakeFired(id: id)
        }
    }

    private func scheduledWakeFired(id: UUID) {
        guard wakeID == id else { return }
        wakeTask = nil
        wakeDate = nil
        wakeID = nil

        if drainTask == nil {
            kick()
        } else {
            drainRequestedAfterCurrentRun = true
        }
    }

    private func removeContributionRow(id: Int64, episodeUuid: String) {
        dataManager.pendingTranscriptUploads.delete(id: id)
        artifactStore.deleteFingerprint(episodeUuid: episodeUuid)
    }

    // MARK: - Helpers

    /// Maps the transcription record onto the wire `engine` identifier
    /// (docs/TranscriptContributions.md §3): `applespeech` | `whisperkit` |
    /// the remote provider id.
    nonisolated static func engineIdentifier(for record: EpisodeTranscriptionRecord) -> String {
        switch TranscriptionEngineMode(rawValue: record.engineMode) {
        case .appleBuiltIn, .none: "applespeech"
        case .localModel: "whisperkit"
        case .remoteProvider: record.provider ?? "remote"
        }
    }

    nonisolated private static func encodePayload(_ payload: some Encodable) -> String? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated private static func decodePayload<T: Decodable>(_ json: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
