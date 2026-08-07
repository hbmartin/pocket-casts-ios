import Foundation
import PocketCastsDataModel
import PocketCastsReadAloud
import PocketCastsUtils
import UniformTypeIdentifiers

/// Renders queued narrations, one at a time.
///
/// Serial by design: synthesis is CPU-bound offline work, and running two
/// documents at once would halve the speed of the one the user is waiting for
/// while doubling the battery cost.
///
/// **Resume contract.** After each chunk renders, its file lands in the
/// workspace and only then is `completedChunkCount` bumped. On relaunch,
/// `restorePending` re-reads the source, re-chunks it (the chunker is pure, so
/// index N means the same text it did before) and skips the indices whose files
/// already exist. The row's synthesis settings are frozen at enqueue, so a
/// resumed run can never be rendering something different from the chunks
/// already on disk — which is why there is no manifest and no settings
/// fingerprint.
actor NarrationQueue {
    static let shared = NarrationQueue()

    private let dataManager: DataManager
    private let storage: ReadAloudStorage
    private let engineFactory: any NarrationEngineProviding
    private let assembler: any NarrationAssembling
    private let materializer: any NarrationMaterializing
    private let extractors: TextExtractorRegistry

    private var pending: [String] = []
    private var runningUuid: String?
    private var runningTask: Task<Void, Never>?
    /// Set when the app is heading to the background and the grace period is
    /// about to expire: finish the chunk in flight, then stop.
    private var suspended = false

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

    func enqueue(uuid: String) {
        suspended = false
        if runningUuid != uuid, !pending.contains(uuid) {
            pending.append(uuid)
        }
        // Always drain, even for a duplicate: re-enqueueing an already-pending
        // narration (what restorePending does on foreground) may be the only
        // thing that clears a suspension, and clearing it must restart work.
        drain()
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
    func retry(uuid: String) {
        guard dataManager.readAloud.markQueued(uuid: uuid) else { return }
        Self.postChanged()
        enqueue(uuid: uuid)
    }

    func cancel(uuid: String) {
        pending.removeAll { $0 == uuid }
        dataManager.readAloud.markCancelled(uuid: uuid)
        if runningUuid == uuid {
            runningTask?.cancel()
        }
        storage.deleteWorkspace(narrationUuid: uuid)
        Self.postChanged()
    }

    /// The background grace period is ending. The chunk in flight finishes (its
    /// file and checkpoint land), then the queue stops until the next launch or
    /// foreground.
    func suspendAfterCurrentChunk() {
        suspended = true
    }

    var isIdle: Bool {
        runningUuid == nil && pending.isEmpty
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
        guard runningTask == nil, !suspended, !pending.isEmpty else { return }
        let uuid = pending.removeFirst()
        runningUuid = uuid

        runningTask = Task { [weak self] in
            await self?.run(uuid: uuid)
            await self?.finishRun()
        }
    }

    private func finishRun() {
        runningUuid = nil
        runningTask = nil
        drain()
    }

    // MARK: - Rendering one narration

    private func run(uuid: String) async {
        guard let narration = dataManager.readAloud.narration(uuid: uuid),
              NarrationState.resumable.contains(narration.narrationState),
              let document = dataManager.readAloud.document(uuid: narration.documentUuid) else { return }

        do {
            try await render(narration, document: document)
        } catch is CancellationError {
            dataManager.readAloud.markCancelled(uuid: uuid)
            storage.deleteWorkspace(narrationUuid: uuid)
        } catch {
            let readAloudError = error as? ReadAloudError ?? .engineFailure
            if case .cancelled = readAloudError {
                dataManager.readAloud.markCancelled(uuid: uuid)
                storage.deleteWorkspace(narrationUuid: uuid)
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
        }
        Self.postChanged()
    }

    private func render(_ narration: NarrationRecord, document: ReadAloudDocumentRecord) async throws {
        let extracted = try loadText(of: document)
        let engine = try engineFactory.makeEngine(for: narration.engine, providerId: narration.providerId)
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

        try storage.prepareWorkspace(narrationUuid: narration.uuid)

        let voice = SynthesisVoice(id: narration.voiceId, name: narration.voiceName, language: document.language ?? "")
        let settings = SynthesisSettings(rate: Float(narration.rate))

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
            rendered: &rendered
        )

        try Task.checkCancellation()

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
        rendered: inout Set<Int>
    ) async throws {
        guard !chunks.isEmpty else { return }
        let limit = max(engine.capabilities.maxConcurrentChunks, 1)
        let storage = storage

        // `inout` can't cross the group's closure boundary; copy in, copy back.
        var completed = rendered
        defer { rendered = completed }

        try await withThrowingTaskGroup(of: Int.self) { group in
            var next = chunks.makeIterator()

            /// Adds one chunk unless the run is stopping. Returns false when
            /// there was nothing left to add.
            func addNext() throws -> Bool {
                try Task.checkCancellation()
                if suspended { throw ReadAloudError.cancelled }
                guard let chunk = next.next() else { return false }

                let chunkURL = storage.chunkURL(narrationUuid: narrationUuid, index: chunk.index)
                group.addTask {
                    do {
                        try await engine.synthesize(
                            chunk: chunk,
                            voice: voice,
                            settings: settings,
                            apiKey: apiKey,
                            to: chunkURL
                        )
                    } catch {
                        // Never leave a partial file behind: the resume path
                        // treats any non-empty chunk file as finished work.
                        try? FileManager.default.removeItem(at: chunkURL)
                        throw error
                    }
                    return chunk.index
                }
                return true
            }

            for _ in 0..<limit where try !addNext() { break }

            while let index = try await group.next() {
                completed.insert(index)
                dataManager.readAloud.updateProgress(uuid: narrationUuid, completedChunkCount: completed.count)
                Self.postChanged()
                _ = try addNext()
            }
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
