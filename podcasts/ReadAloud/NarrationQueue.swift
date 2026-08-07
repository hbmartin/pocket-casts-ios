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
        guard runningUuid != uuid, !pending.contains(uuid) else { return }
        pending.append(uuid)
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

        let chunks = TextChunker().chunks(for: extracted, maxCharacters: engine.capabilities.maxCharactersPerChunk)
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

        for chunk in chunks {
            try Task.checkCancellation()
            if suspended { throw ReadAloudError.cancelled }
            guard !rendered.contains(chunk.index) else { continue }

            let chunkURL = storage.chunkURL(narrationUuid: narration.uuid, index: chunk.index)
            do {
                try await engine.synthesize(
                    chunk: chunk,
                    voice: voice,
                    settings: settings,
                    apiKey: apiKey,
                    to: chunkURL
                )
            } catch {
                // Never leave a partial file behind: the resume path treats any
                // non-empty chunk file as finished work.
                try? FileManager.default.removeItem(at: chunkURL)
                throw error
            }

            rendered.insert(chunk.index)
            dataManager.readAloud.updateProgress(uuid: narration.uuid, completedChunkCount: rendered.count)
            Self.postChanged()
        }

        try Task.checkCancellation()

        let output = try await assembler.assemble(
            chunkURLs: chunks.map { storage.chunkURL(narrationUuid: narration.uuid, index: $0.index) },
            pauseBefore: Set(chunks.filter(\.startsBlock).map(\.index)),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("narration-\(narration.uuid).m4a")
        )

        let episodeUuid = try await materializer.materialize(
            document: document,
            narration: narration,
            audioURL: output.url,
            duration: output.duration,
            sizeInBytes: output.sizeInBytes
        )

        dataManager.readAloud.markCompleted(
            uuid: narration.uuid,
            episodeUuid: episodeUuid,
            duration: output.duration,
            sizeInBytes: output.sizeInBytes
        )
        storage.deleteWorkspace(narrationUuid: narration.uuid)
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
