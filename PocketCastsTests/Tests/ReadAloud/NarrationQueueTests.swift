import Foundation
@testable import PocketCastsDataModel
@testable import PocketCastsReadAloud
@testable import podcasts
import XCTest

/// Coverage for the Read Aloud render pipeline: the resume contract above all
/// (ADR-0019, migration 91).
/// Subclasses `DBTestCase` rather than standing up its own `DataManager`: this
/// bundle deliberately shares one instance process-wide (see `DBTestCase`), and
/// opening a fresh `DatabasePool` per test leaks connections that surface much
/// later as unrelated failures in download-backed suites.
final class NarrationQueueTests: DBTestCase {
    private var storage: ReadAloudStorage!
    private var root: URL!
    private var createdDocumentUuids: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadAloudTests-\(UUID().uuidString)", isDirectory: true)
        storage = ReadAloudStorage(rootURL: root)
    }

    override func tearDown() async throws {
        // The DataManager is shared with every other DBTestCase, so rows have to
        // go back out the way they came in. Deleting the document cascades to
        // its narrations.
        for uuid in createdDocumentUuids {
            dataManager.readAloud.deleteDocument(uuid: uuid)
        }
        createdDocumentUuids = []
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// Enough text to chunk into several pieces at the fake engine's small limit.
    private static let sourceText = (1...12)
        .map { "This is sentence number \($0) of the test document." }
        .joined(separator: " ")

    /// Creates a document with one queued narration, the shape the importer
    /// produces.
    @discardableResult
    private func makeNarration(text: String = NarrationQueueTests.sourceText) throws -> NarrationRecord {
        let documentUuid = UUID().uuidString.lowercased()
        let sourcePath = try storage.writeSource(text: text, documentUuid: documentUuid)

        var document = ReadAloudDocumentRecord()
        document.uuid = documentUuid
        document.title = "Test Document"
        document.sourcePath = sourcePath
        document.characterCount = Int32(text.count)
        document.addedDate = Date().timeIntervalSince1970

        var record = NarrationRecord()
        record.uuid = UUID().uuidString.lowercased()
        record.documentUuid = documentUuid
        record.voiceId = "test.voice"
        record.voiceName = "Test Voice"
        record.narrationState = .queued
        record.createdDate = Date().timeIntervalSince1970

        XCTAssertTrue(dataManager.readAloud.add(document: document, narration: record))
        createdDocumentUuids.append(documentUuid)
        return record
    }

    /// A second narration of an existing document, sharing its source file.
    private func makeSecondNarration(of narration: NarrationRecord) throws -> NarrationRecord {
        var record = NarrationRecord()
        record.uuid = UUID().uuidString.lowercased()
        record.documentUuid = narration.documentUuid
        record.voiceId = "test.voice"
        record.voiceName = "Test Voice"
        record.narrationState = .queued
        record.createdDate = Date().timeIntervalSince1970
        XCTAssertTrue(dataManager.readAloud.add(record))
        return record
    }

    private func makeQueue(
        engine: FakeSynthesisEngine,
        assembler: any NarrationAssembling = FakeAssembler(),
        materializer: FakeMaterializer = FakeMaterializer()
    ) -> NarrationQueue {
        NarrationQueue(
            dataManager: dataManager,
            storage: storage,
            engineFactory: FakeEngineFactory(engine: engine),
            assembler: assembler,
            materializer: materializer,
            extractors: .standard
        )
    }

    // MARK: - Happy path

    func testRenderingProducesAnEpisodeAndMarksCompleted() async throws {
        let narration = try makeNarration()
        let engine = FakeSynthesisEngine()
        let materializer = FakeMaterializer()
        let queue = makeQueue(engine: engine, materializer: materializer)

        await queue.enqueue(uuid: narration.uuid)
        await queue.drainUntilIdle()

        let loaded = try XCTUnwrap(dataManager.readAloud.narration(uuid: narration.uuid))
        XCTAssertEqual(loaded.narrationState, .completed)
        XCTAssertEqual(loaded.episodeUuid, materializer.episodeUuid)
        XCTAssertGreaterThan(loaded.chunkCount, 0)
        XCTAssertEqual(loaded.completedChunkCount, loaded.chunkCount)
        let synthesized = await engine.synthesizedIndices
        XCTAssertEqual(synthesized.count, Int(loaded.chunkCount))
    }

    /// The workspace is scratch space for one render; leaving it behind would
    /// accumulate a copy of every narration's audio forever.
    func testWorkspaceIsRemovedOnSuccess() async throws {
        let narration = try makeNarration()
        let queue = makeQueue(engine: FakeSynthesisEngine())

        await queue.enqueue(uuid: narration.uuid)
        await queue.drainUntilIdle()

        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.workspaceURL(narrationUuid: narration.uuid).path))
    }

    func testTheSourceDocumentSurvivesAnyRender() async throws {
        let narration = try makeNarration()
        let queue = makeQueue(engine: FakeSynthesisEngine())

        await queue.enqueue(uuid: narration.uuid)
        await queue.drainUntilIdle()

        let document = try XCTUnwrap(dataManager.readAloud.document(uuid: narration.documentUuid))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.sourceURL(relativePath: document.sourcePath).path))
    }

    /// Re-narrating shares the document's one source file rather than copying
    /// it, which is the whole reason the document table exists.
    func testASecondNarrationRendersFromTheSameSourceFile() async throws {
        let first = try makeNarration()
        let second = try makeSecondNarration(of: first)
        let engine = FakeSynthesisEngine()
        let queue = makeQueue(engine: engine)

        await queue.enqueue(uuid: first.uuid)
        await queue.enqueue(uuid: second.uuid)
        await queue.drainUntilIdle()

        XCTAssertEqual(dataManager.readAloud.narration(uuid: first.uuid)?.narrationState, .completed)
        XCTAssertEqual(dataManager.readAloud.narration(uuid: second.uuid)?.narrationState, .completed)
        XCTAssertEqual(dataManager.readAloud.narrations(documentUuid: first.documentUuid).count, 2)

        let sources = try FileManager.default.contentsOfDirectory(atPath: storage.sourcesURL.path)
        XCTAssertEqual(sources.count, 1, "a second narration must not duplicate the source file")
    }

    // MARK: - Resume (the load-bearing behaviour)

    /// The point of chunk-level checkpointing: a resumed narration must not
    /// re-render — and, for paid engines, must not re-pay for — work already on
    /// disk.
    func testResumeSkipsChunksAlreadyOnDisk() async throws {
        let narration = try makeNarration()

        // First pass: render everything, then pretend the app died before
        // assembly by resetting the row to `rendering` with the chunk files kept.
        let firstEngine = FakeSynthesisEngine()
        let firstQueue = makeQueue(engine: firstEngine, assembler: FailingAssembler())
        await firstQueue.enqueue(uuid: narration.uuid)
        await firstQueue.drainUntilIdle()

        let afterCrash = try XCTUnwrap(dataManager.readAloud.narration(uuid: narration.uuid))
        XCTAssertEqual(afterCrash.narrationState, .failed)
        let renderedCount = await firstEngine.synthesizedIndices.count
        XCTAssertGreaterThan(renderedCount, 1)
        // The workspace deliberately survives a failure so a retry resumes.
        XCTAssertEqual(
            storage.renderedChunkIndices(narrationUuid: narration.uuid, chunkCount: Int(afterCrash.chunkCount)).count,
            renderedCount
        )

        // Second pass: a fresh engine must be asked for nothing at all.
        let secondEngine = FakeSynthesisEngine()
        let secondQueue = makeQueue(engine: secondEngine)
        await secondQueue.retry(uuid: narration.uuid)
        await secondQueue.drainUntilIdle()

        let resumedIndices = await secondEngine.synthesizedIndices
        XCTAssertEqual(resumedIndices, [], "resume re-synthesized chunks that were already rendered")
        XCTAssertEqual(dataManager.readAloud.narration(uuid: narration.uuid)?.narrationState, .completed)
    }

    /// The checkpoint column is bumped *after* the file lands, so a kill in
    /// between leaves it one behind. The filesystem, not the column, has to be
    /// the authority — otherwise a rendered chunk is silently dropped.
    func testResumeTrustsTheFilesystemOverAStaleCount() async throws {
        let narration = try makeNarration()

        let firstEngine = FakeSynthesisEngine()
        let firstQueue = makeQueue(engine: firstEngine, assembler: FailingAssembler())
        await firstQueue.enqueue(uuid: narration.uuid)
        await firstQueue.drainUntilIdle()
        let renderedCount = await firstEngine.synthesizedIndices.count

        // Simulate the torn state: files on disk, count behind.
        dataManager.readAloud.updateProgress(uuid: narration.uuid, completedChunkCount: 0)

        let secondEngine = FakeSynthesisEngine()
        let secondQueue = makeQueue(engine: secondEngine)
        await secondQueue.retry(uuid: narration.uuid)
        await secondQueue.drainUntilIdle()

        let resumedIndices = await secondEngine.synthesizedIndices
        XCTAssertEqual(resumedIndices, [])
        XCTAssertEqual(dataManager.readAloud.narration(uuid: narration.uuid)?.completedChunkCount, Int32(renderedCount))
    }

    func testRestorePendingPicksUpAnInterruptedRender() async throws {
        let narration = try makeNarration()
        dataManager.readAloud.markRendering(uuid: narration.uuid, chunkCount: 3)

        let engine = FakeSynthesisEngine()
        let queue = makeQueue(engine: engine)
        await queue.restorePending()
        await queue.drainUntilIdle()

        XCTAssertEqual(dataManager.readAloud.narration(uuid: narration.uuid)?.narrationState, .completed)
        let synthesized = await engine.synthesizedIndices
        XCTAssertGreaterThan(synthesized.count, 0)
    }

    func testCompletedNarrationsAreNotResumed() async throws {
        let narration = try makeNarration()
        dataManager.readAloud.markCompleted(uuid: narration.uuid, episodeUuid: "ep-1", duration: 10, sizeInBytes: 10)

        let engine = FakeSynthesisEngine()
        let queue = makeQueue(engine: engine)
        await queue.restorePending()
        await queue.drainUntilIdle()

        let synthesized = await engine.synthesizedIndices
        XCTAssertEqual(synthesized, [])
    }

    // MARK: - Failure and cancellation

    func testAFailedChunkLeavesNoPartialFileBehind() async throws {
        let narration = try makeNarration()
        let engine = FakeSynthesisEngine(failAtIndex: 1, writeFileBeforeFailing: true)
        let queue = makeQueue(engine: engine)

        await queue.enqueue(uuid: narration.uuid)
        await queue.drainUntilIdle()

        let loaded = try XCTUnwrap(dataManager.readAloud.narration(uuid: narration.uuid))
        XCTAssertEqual(loaded.narrationState, .failed)
        XCTAssertEqual(loaded.errorCode, ReadAloudError.engineFailure.code)
        // Chunk 1's partial file must be gone, or resume would count it as done.
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: storage.chunkURL(narrationUuid: narration.uuid, index: 1).path),
            "a partial chunk file survived and would be mistaken for finished work"
        )
        // Chunk 0 rendered cleanly and is kept for the retry.
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.chunkURL(narrationUuid: narration.uuid, index: 0).path))
    }

    func testCancellationClearsTheWorkspace() async throws {
        let narration = try makeNarration()
        let queue = makeQueue(engine: FakeSynthesisEngine())

        await queue.cancel(uuid: narration.uuid)

        XCTAssertEqual(dataManager.readAloud.narration(uuid: narration.uuid)?.narrationState, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.workspaceURL(narrationUuid: narration.uuid).path))
    }

    func testAMissingSourceFileFailsWithSourceUnreadable() async throws {
        let narration = try makeNarration()
        let document = try XCTUnwrap(dataManager.readAloud.document(uuid: narration.documentUuid))
        storage.deleteSource(relativePath: document.sourcePath)

        let queue = makeQueue(engine: FakeSynthesisEngine())
        await queue.enqueue(uuid: narration.uuid)
        await queue.drainUntilIdle()

        XCTAssertEqual(
            dataManager.readAloud.narration(uuid: narration.uuid)?.errorCode,
            ReadAloudError.sourceUnreadable.code
        )
    }

    // MARK: - Serialization

    func testNarrationsRenderOneAtATime() async throws {
        let first = try makeNarration()
        let second = try makeNarration()
        let engine = FakeSynthesisEngine()
        let queue = makeQueue(engine: engine)

        await queue.enqueue(uuid: first.uuid)
        await queue.enqueue(uuid: second.uuid)
        await queue.drainUntilIdle()

        XCTAssertEqual(dataManager.readAloud.narration(uuid: first.uuid)?.narrationState, .completed)
        XCTAssertEqual(dataManager.readAloud.narration(uuid: second.uuid)?.narrationState, .completed)
        let peakConcurrency = await engine.maxConcurrent
        XCTAssertEqual(peakConcurrency, 1, "narrations rendered concurrently")
    }
}

// MARK: - Fakes

private actor FakeSynthesisEngine: SpeechSynthesisEngine {
    nonisolated let id = "test.engine"
    nonisolated var capabilities: EngineCapabilities {
        // Small limit so the fixture chunks several times over.
        EngineCapabilities(
            maxCharactersPerChunk: 300,
            maxConcurrentChunks: 1,
            requiresAPIKey: false,
            requiresConfirmation: false,
            supportsFreePreview: true
        )
    }

    private(set) var synthesizedIndices: [Int] = []
    private(set) var maxConcurrent = 0
    private var active = 0

    private let failAtIndex: Int?
    private let writeFileBeforeFailing: Bool

    init(failAtIndex: Int? = nil, writeFileBeforeFailing: Bool = false) {
        self.failAtIndex = failAtIndex
        self.writeFileBeforeFailing = writeFileBeforeFailing
    }

    nonisolated func availableVoices(apiKey: String?) async throws -> [SynthesisVoice] {
        [SynthesisVoice(id: "test.voice", name: "Test Voice", language: "en-US")]
    }

    func synthesize(
        chunk: NarrationChunk,
        voice: SynthesisVoice,
        settings: SynthesisSettings,
        apiKey: String?,
        to outputURL: URL
    ) async throws {
        active += 1
        maxConcurrent = max(maxConcurrent, active)
        defer { active -= 1 }

        if chunk.index == failAtIndex {
            if writeFileBeforeFailing {
                // The realistic shape of a mid-write failure: bytes on disk that
                // must not be mistaken for a finished chunk.
                try? Data("partial".utf8).write(to: outputURL)
            }
            throw ReadAloudError.engineFailure
        }

        synthesizedIndices.append(chunk.index)
        try Data("chunk-\(chunk.index)".utf8).write(to: outputURL)
    }
}

private struct FakeEngineFactory: NarrationEngineProviding {
    let engine: FakeSynthesisEngine

    func makeEngine(for kind: NarrationEngineKind, providerId: String?) throws -> any SpeechSynthesisEngine {
        engine
    }

    func apiKey(providerId: String?) -> String? { nil }
}

private struct FakeAssembler: NarrationAssembling {
    func assemble(chunkURLs: [URL], pauseBefore: Set<Int>, outputURL: URL) async throws -> AssembledNarration {
        try Data("assembled".utf8).write(to: outputURL)
        return AssembledNarration(url: outputURL, duration: 42, sizeInBytes: 9)
    }
}

private struct FailingAssembler: NarrationAssembling {
    func assemble(chunkURLs: [URL], pauseBefore: Set<Int>, outputURL: URL) async throws -> AssembledNarration {
        throw ReadAloudError.assemblyFailed
    }
}

private struct FakeMaterializer: NarrationMaterializing {
    let episodeUuid: String

    init(episodeUuid: String = "episode-\(UUID().uuidString.lowercased())") {
        self.episodeUuid = episodeUuid
    }

    func materialize(
        document: ReadAloudDocumentRecord,
        narration: NarrationRecord,
        audioURL: URL,
        duration: TimeInterval,
        sizeInBytes: Int64
    ) async throws -> String {
        episodeUuid
    }
}
