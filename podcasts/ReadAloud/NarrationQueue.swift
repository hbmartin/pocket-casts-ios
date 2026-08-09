import Foundation
import PocketCastsDataModel
import PocketCastsReadAloud
import PocketCastsUtils
import Synchronization
import UniformTypeIdentifiers

/// Stable identity for one queue run. A retry receives a new generation, so
/// callers never accidentally wait for (or observe the result of) a later run
/// for the same narration.
nonisolated struct NarrationAttempt: Hashable, Sendable {
    let uuid: String
    let generation: UInt64
}

/// The durable checkpoint reached by one specific narration attempt.
nonisolated enum NarrationAttemptOutcome: Equatable, Sendable {
    case completed
    case failed
    case cancelled
    case suspended
    case superseded
    case missing
}

/// Renders queued narrations, one at a time.
///
/// Serial by design: synthesis is CPU-bound offline work, and running two
/// documents at once would halve the speed of the one the user is waiting for
/// while doubling the battery cost.
///
/// **Resume contract.** An engine writes each chunk to a temporary path. The
/// queue validates it, atomically promotes it to the checkpoint path, and only
/// then bumps `completedChunkCount`. A persisted manifest fingerprints the
/// extracted content, exact chunk plan, engine/model, voice, and rate; a resumed
/// run discards the workspace unless every input still matches.
actor NarrationQueue {
    static let shared = NarrationQueue()

    private let dataManager: DataManager
    private let storage: ReadAloudStorage
    private let engineFactory: any NarrationEngineProviding
    private let assembler: any NarrationAssembling
    private let materializer: any NarrationMaterializing
    private let extractors: TextExtractorRegistry

    private var pending: [NarrationAttempt] = []
    private var runningAttempt: NarrationAttempt?
    private var runningTask: Task<Void, Never>?
    private var generations: [String: UInt64] = [:]
    private var attemptOutcomes: [NarrationAttempt: NarrationAttemptOutcome] = [:]
    private var attemptWaiters: [NarrationAttempt: [CheckedContinuation<NarrationAttemptOutcome, Never>]] = [:]
    private var resumeRequested: Set<NarrationAttempt> = []

    /// Set when the background grace period is expiring: finish the chunk in
    /// flight, then stop.
    ///
    /// Behind a `Mutex` rather than actor state because the only thing that sets
    /// it is a `UIApplication` background-task expiration handler, which has no
    /// time to await an actor — the OS may suspend the process the moment that
    /// handler returns, and a hop scheduled from it can simply never land.
    private let suspended = Mutex(false)

    init(
        dataManager: DataManager = .sharedManager,
        storage: ReadAloudStorage = .default,
        engineFactory: any NarrationEngineProviding = NarrationEngineFactory(),
        assembler: any NarrationAssembling = NarrationAssembler(),
        materializer: any NarrationMaterializing = NarrationMaterializer(),
        extractors: TextExtractorRegistry = .standard
    ) {
        self.dataManager = dataManager
        self.storage = storage
        self.engineFactory = engineFactory
        self.assembler = assembler
        self.materializer = materializer
        self.extractors = extractors
    }

    // MARK: - Queue control

    @discardableResult
    func enqueue(uuid: String) -> NarrationAttempt {
        let wasSuspended = suspended.withLock { value in
            let wasSuspended = value
            value = false
            return wasSuspended
        }
        if let runningAttempt, runningAttempt.uuid == uuid {
            // If foreground restoration races the old run while its in-flight
            // children are draining, remember that work must restart after the
            // attempt reaches its suspended checkpoint. Returning the current
            // attempt alone would otherwise consume the only resume signal.
            if wasSuspended {
                resumeRequested.insert(runningAttempt)
            }
            return runningAttempt
        }
        if let existing = pending.first(where: { $0.uuid == uuid }) {
            drain()
            return existing
        }
        let attempt = makeAttempt(uuid: uuid)
        pending.append(attempt)
        // Always drain, even for a duplicate: re-enqueueing an already-pending
        // narration (what restorePending does on foreground) may be the only
        // thing that clears a suspension, and clearing it must restart work.
        drain()
        return attempt
    }

    /// Queues one narration and waits only for that exact attempt. Unlike
    /// `drainUntilIdle`, later unrelated queue work does not delay the caller.
    func enqueueAndWait(uuid: String) async -> NarrationAttemptOutcome {
        let attempt = enqueue(uuid: uuid)
        return await waitForAttempt(attempt)
    }

    func waitForAttempt(_ attempt: NarrationAttempt) async -> NarrationAttemptOutcome {
        if let outcome = attemptOutcomes[attempt] { return outcome }
        return await withCheckedContinuation { continuation in
            attemptWaiters[attempt, default: []].append(continuation)
        }
    }

    /// Re-queues everything left unfinished by a previous launch.
    ///
    /// `rendering` rows are included because a process kill leaves the row
    /// exactly as it was mid-run — there is no chance to write a "stopped" state
    /// on the way down.
    func restorePending() {
        for narration in dataManager.readAloud.narrationsPendingResume() {
            enqueue(uuid: narration.uuid)
        }
    }

    /// Retries a failed or cancelled narration. Rendered chunks are kept, so a
    /// retry after a network blip resumes rather than restarting.
    @discardableResult
    func retry(uuid: String) -> NarrationAttempt? {
        guard let previous = dataManager.readAloud.narration(uuid: uuid) else { return nil }
        guard dataManager.readAloud.markQueued(uuid: uuid) else { return nil }
        if previous.narrationState == .cancelled {
            // Cancellation deliberately abandons its checkpoints. Do this before
            // scheduling the replacement generation; the stale run is forbidden
            // from deleting the replacement workspace when it eventually exits.
            storage.deleteWorkspace(narrationUuid: uuid)
        }

        let attempt = makeAttempt(uuid: uuid)
        pending.removeAll { existing in
            guard existing.uuid == uuid else { return false }
            resolve(existing, as: .superseded)
            return true
        }
        pending.append(attempt)
        if runningAttempt?.uuid == uuid {
            runningTask?.cancel()
        }
        Self.postChanged()
        suspended.withLock { $0 = false }
        drain()
        return attempt
    }

    func cancel(uuid: String) {
        let cancelledPending = pending.filter { $0.uuid == uuid }
        pending.removeAll { $0.uuid == uuid }
        dataManager.readAloud.markCancelled(uuid: uuid)
        for attempt in cancelledPending {
            resolve(attempt, as: .cancelled)
        }
        if runningAttempt?.uuid == uuid {
            runningTask?.cancel()
        } else {
            storage.deleteWorkspace(narrationUuid: uuid)
        }
        Self.postChanged()
    }

    /// Cancels and waits until the active attempt has stopped touching its
    /// workspace. Deletion paths use this before removing the source/rows.
    @discardableResult
    func cancelAndWait(uuid: String) async -> NarrationAttemptOutcome? {
        let attempt = runningAttempt?.uuid == uuid
            ? runningAttempt
            : pending.first(where: { $0.uuid == uuid })
        cancel(uuid: uuid)
        guard let attempt else { return nil }
        return await waitForAttempt(attempt)
    }

    /// The background grace period is ending. The chunk in flight finishes (its
    /// file and checkpoint land), then the queue stops until the next launch or
    /// foreground.
    ///
    /// `nonisolated` so the expiration handler can set it and return, rather
    /// than scheduling work the OS may never run.
    nonisolated func suspendAfterCurrentChunk() {
        suspended.withLock { $0 = true }
    }

    var isIdle: Bool {
        runningAttempt == nil && pending.isEmpty
    }

    /// Test hook: waits for the queue to settle. Each task ends by calling
    /// `finishRun`, so by the time `value` returns `runningTask` is either nil
    /// or the next narration's task.
    func drainUntilIdle() async {
        while let task = runningTask {
            await task.value
        }
    }

    // MARK: - Draining

    private func drain() {
        guard runningTask == nil, !suspended.withLock({ $0 }), !pending.isEmpty else { return }
        let attempt = pending.removeFirst()
        runningAttempt = attempt

        runningTask = Task { [weak self] in
            let outcome = await self?.run(attempt: attempt) ?? .superseded
            await self?.finishRun(attempt: attempt, outcome: outcome)
        }
    }

    private func finishRun(attempt: NarrationAttempt, outcome: NarrationAttemptOutcome) {
        guard runningAttempt == attempt else {
            resolve(attempt, as: outcome)
            return
        }
        let shouldResume = outcome == .suspended && resumeRequested.remove(attempt) != nil
        if !shouldResume {
            resumeRequested.remove(attempt)
        }
        runningAttempt = nil
        runningTask = nil
        resolve(attempt, as: outcome)
        if shouldResume {
            pending.insert(makeAttempt(uuid: attempt.uuid), at: 0)
        }
        drain()
    }

    private func makeAttempt(uuid: String) -> NarrationAttempt {
        let generation = (generations[uuid] ?? 0) &+ 1
        generations[uuid] = generation
        return NarrationAttempt(uuid: uuid, generation: generation)
    }

    private func resolve(_ attempt: NarrationAttempt, as outcome: NarrationAttemptOutcome) {
        guard attemptOutcomes[attempt] == nil else { return }
        attemptOutcomes[attempt] = outcome
        for waiter in attemptWaiters.removeValue(forKey: attempt) ?? [] {
            waiter.resume(returning: outcome)
        }
    }

    private func ensureCurrent(_ attempt: NarrationAttempt) throws {
        guard generations[attempt.uuid] == attempt.generation else {
            throw NarrationAttemptSuperseded()
        }
    }

    // MARK: - Rendering one narration

    private func run(attempt: NarrationAttempt) async -> NarrationAttemptOutcome {
        let uuid = attempt.uuid
        guard let narration = dataManager.readAloud.narration(uuid: uuid),
              NarrationState.resumable.contains(narration.narrationState),
              let document = dataManager.readAloud.document(uuid: narration.documentUuid) else { return .missing }

        do {
            try ensureCurrent(attempt)
            try await render(narration, document: document, attempt: attempt)
            let state = dataManager.readAloud.narration(uuid: uuid)?.narrationState
            let outcome: NarrationAttemptOutcome = switch state {
            case .completed: .completed
            case .cancelled: .cancelled
            case .failed: .failed
            case .rendering: .suspended
            case .queued: .superseded
            case nil: .missing
            }
            Self.postChanged()
            return outcome
        } catch is NarrationAttemptSuperseded {
            return .superseded
        } catch is NarrationSuspended {
            // Deliberately nothing. The narration stays `rendering` — which is
            // in `NarrationState.resumable` — and its workspace stays on disk,
            // so the next launch or foreground picks it up and skips the chunks
            // already rendered. Treating this as cancellation (as it once was)
            // threw away every rendered chunk the moment the user switched apps.
            Self.postChanged()
            return generations[uuid] == attempt.generation ? .suspended : .superseded
        } catch is CancellationError {
            guard generations[uuid] == attempt.generation else { return .superseded }
            dataManager.readAloud.markCancelled(uuid: uuid)
            storage.deleteWorkspace(narrationUuid: uuid)
            Self.postChanged()
            return .cancelled
        } catch {
            guard generations[uuid] == attempt.generation else { return .superseded }
            let readAloudError = error as? ReadAloudError ?? .engineFailure
            if case .cancelled = readAloudError {
                dataManager.readAloud.markCancelled(uuid: uuid)
                storage.deleteWorkspace(narrationUuid: uuid)
                Self.postChanged()
                return .cancelled
            } else {
                FileLog.shared.addMessage("ReadAloud: narration \(uuid) failed: \(readAloudError.sanitizedDescription)")
                dataManager.readAloud.markFailed(
                    uuid: uuid,
                    errorCode: readAloudError.code,
                    errorDetails: readAloudError.sanitizedDescription
                )
                // The workspace survives a failure on purpose: a retry then
                // resumes from the last good chunk instead of re-rendering
                // (and, for provider engines, re-paying for) everything.
            }
            Self.postChanged()
            return .failed
        }
    }

    private func render(
        _ narration: NarrationRecord,
        document: ReadAloudDocumentRecord,
        attempt: NarrationAttempt
    ) async throws {
        let extracted = try loadText(of: document)
        let engine = try engineFactory.makeEngine(
            for: narration.engine,
            providerId: narration.providerId,
            modelId: narration.modelId
        )
        let apiKey = engineFactory.apiKey(providerId: narration.providerId)
        if engine.capabilities.requiresAPIKey, apiKey?.isEmpty != false {
            throw ReadAloudError.apiKeyMissing
        }

        let chunks = TextChunker().chunks(
            for: extracted,
            maxCharacters: engine.capabilities.maxCharactersPerChunk,
            boundary: engine.capabilities.chunkBoundary
        )
        guard !chunks.isEmpty else { throw ReadAloudError.emptyDocument }

        dataManager.readAloud.markRendering(uuid: narration.uuid, chunkCount: chunks.count)
        Self.postChanged()

        let voice = SynthesisVoice(id: narration.voiceId, name: narration.voiceName, language: document.language ?? "")
        let settings = SynthesisSettings(rate: Float(narration.rate))
        let manifest = ReadAloudWorkspaceManifest(
            document: extracted,
            chunks: chunks,
            engineId: engine.id,
            engineKind: narration.engineKind,
            providerId: narration.providerId,
            modelId: narration.modelId,
            voiceId: narration.voiceId,
            rate: narration.rate,
            maxCharactersPerChunk: engine.capabilities.maxCharactersPerChunk,
            chunkBoundary: engine.capabilities.chunkBoundary
        )
        try storage.prepareWorkspace(narrationUuid: narration.uuid, manifest: manifest)

        // The filesystem is the authority on what is already rendered, not the
        // stored count: the count is bumped after the file lands, so a kill in
        // between leaves it one behind.
        var rendered = storage.renderedChunkIndices(narrationUuid: narration.uuid, chunkCount: chunks.count)
        dataManager.readAloud.updateProgress(uuid: narration.uuid, completedChunkCount: rendered.count)

        let outstanding = chunks.filter { !rendered.contains($0.index) }
        try await renderChunks(
            outstanding,
            narrationUuid: narration.uuid,
            engine: engine,
            voice: voice,
            settings: settings,
            apiKey: apiKey,
            attempt: attempt,
            rendered: &rendered
        )

        try Task.checkCancellation()
        try ensureCurrent(attempt)

        let output = try await assembler.assemble(
            chunkURLs: chunks.map { storage.chunkURL(narrationUuid: narration.uuid, index: $0.index) },
            pauseBefore: Set(chunks.filter(\.startsBlock).map(\.index)),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("narration-\(narration.uuid).m4a")
        )
        // The assembled file is scratch: materialization moves it into the
        // download cache on success, but its copy fallback and every throwing
        // path leave it behind in tmp.
        defer { try? FileManager.default.removeItem(at: output.url) }

        let episodeUuid = try await materializer.materialize(
            document: document,
            narration: narration,
            audioURL: output.url,
            duration: output.duration,
            sizeInBytes: output.sizeInBytes
        )

        guard dataManager.readAloud.markCompleted(
            uuid: narration.uuid,
            episodeUuid: episodeUuid,
            duration: output.duration,
            sizeInBytes: output.sizeInBytes
        ) else {
            // The narration was cancelled or deleted while the episode was
            // being assembled. Its cancelled state wins; the episode that just
            // landed has no owner, so take it back out.
            if let orphan = dataManager.findUserEpisode(uuid: episodeUuid) {
                UserEpisodeManager.deleteFromDevice(userEpisode: orphan)
            }
            storage.deleteWorkspace(narrationUuid: narration.uuid)
            return
        }
        storage.deleteWorkspace(narrationUuid: narration.uuid)
    }

    /// Renders the outstanding chunks, up to `maxConcurrentChunks` at a time.
    ///
    /// The bookkeeping deliberately stays on the actor: only `synthesize` runs in
    /// a child task, and every mutation of `rendered` happens where `group.next()`
    /// resumes. Chunks may therefore finish out of order, which costs nothing —
    /// the assembler reads files back by index and progress is only a count.
    ///
    /// At `maxConcurrentChunks == 1` (every local engine) this is exactly the
    /// sequential loop it replaced: one task in flight, awaited before the next
    /// is added.
    private func renderChunks(
        _ chunks: [NarrationChunk],
        narrationUuid: String,
        engine: any SpeechSynthesisEngine,
        voice: SynthesisVoice,
        settings: SynthesisSettings,
        apiKey: String?,
        attempt: NarrationAttempt,
        rendered: inout Set<Int>
    ) async throws {
        guard !chunks.isEmpty else {
            if suspended.withLock({ $0 }) {
                throw NarrationSuspended()
            }
            return
        }
        let limit = max(engine.capabilities.maxConcurrentChunks, 1)
        let storage = storage

        // `inout` can't cross the group's closure boundary; copy in, copy back.
        var completed = rendered
        defer { rendered = completed }

        // A throwing group can exit before consuming successful siblings. Every
        // temporary path is generation-scoped and cleaned on exit, so only
        // results promoted by the actor below can survive as checkpoints.
        defer {
            for chunk in chunks {
                try? FileManager.default.removeItem(at: storage.partialChunkURL(
                    narrationUuid: narrationUuid,
                    index: chunk.index,
                    generation: attempt.generation
                ))
            }
        }

        let shouldSuspend = try await withThrowingTaskGroup(
            of: (index: Int, temporaryURL: URL).self,
            returning: Bool.self
        ) { group in
            var shouldSuspend = false
            var next = chunks.makeIterator()

            /// Adds one chunk unless the run is stopping. Returns false when
            /// there was nothing left to add.
            func addNext() throws -> Bool {
                try Task.checkCancellation()
                try ensureCurrent(attempt)
                if suspended.withLock({ $0 }) {
                    shouldSuspend = true
                    return false
                }
                guard let chunk = next.next() else { return false }

                let temporaryURL = storage.partialChunkURL(
                    narrationUuid: narrationUuid,
                    index: chunk.index,
                    generation: attempt.generation
                )
                try? FileManager.default.removeItem(at: temporaryURL)
                group.addTask {
                    do {
                        try await engine.synthesize(
                            chunk: chunk,
                            voice: voice,
                            settings: settings,
                            apiKey: apiKey,
                            to: temporaryURL
                        )
                    } catch {
                        try? FileManager.default.removeItem(at: temporaryURL)
                        throw error
                    }
                    return (chunk.index, temporaryURL)
                }
                return true
            }

            // Seed the window. `addNext` returns false once the chunks run
            // out, which for a short narration happens before the limit.
            for _ in 0..<limit {
                guard try addNext() else { break }
            }

            while let result = try await group.next() {
                try Task.checkCancellation()
                try ensureCurrent(attempt)
                try storage.commitRenderedChunk(
                    from: result.temporaryURL,
                    narrationUuid: narrationUuid,
                    index: result.index
                )
                let index = result.index
                completed.insert(index)
                dataManager.readAloud.updateProgress(uuid: narrationUuid, completedChunkCount: completed.count)
                Self.postChanged()
                if !shouldSuspend {
                    _ = try addNext()
                }
            }
            return shouldSuspend
        }

        if shouldSuspend || suspended.withLock({ $0 }) {
            throw NarrationSuspended()
        }
    }

    /// Re-reads and re-extracts the document's retained file. Done afresh on
    /// every run — including a resume — because extraction and chunking are
    /// deterministic, so this reproduces exactly the chunk indices already on
    /// disk.
    private func loadText(of document: ReadAloudDocumentRecord) throws -> ExtractedDocument {
        let sourceURL = storage.sourceURL(relativePath: document.sourcePath)
        guard let data = try? Data(contentsOf: sourceURL) else {
            throw ReadAloudError.sourceUnreadable
        }
        return try extractors.extract(
            data: data,
            filename: document.originalFilename ?? document.sourcePath,
            type: document.utType.flatMap(UTType.init(_:))
        )
    }

    // MARK: - Change notification

    private static func postChanged() {
        NotificationCenter.postOnMainThread(NarrationsChanged())
    }
}

/// Raised when the background grace period ends mid-render.
///
/// Deliberately not a `ReadAloudError`: nothing failed, the user is told
/// nothing, and no state changes. It exists only to unwind out of the render
/// loop without running assembly or materialization.
private struct NarrationSuspended: Error {}

/// Raised when a retry has replaced a run which is still unwinding. The stale
/// run must not mutate state or remove workspace files owned by its replacement.
private struct NarrationAttemptSuperseded: Error {}
