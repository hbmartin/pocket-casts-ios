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
        // The DataManager is process-wide: rows leaked by an earlier crashed
        // test would be picked up by restorePending() and pollute the
        // whole-queue assertions below, so start from a clean slate.
        for document in dataManager.readAloud.allDocuments() {
            dataManager.readAloud.deleteDocument(uuid: document.uuid)
        }
        for narration in dataManager.readAloud.narrationsPendingResume() {
            dataManager.readAloud.deleteNarration(uuid: narration.uuid)
        }
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadAloudTests-\(UUID().uuidString)", isDirectory: true)
        storage = ReadAloudStorage(rootURL: root) { url in
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { return false }
            return text.hasPrefix("chunk-")
        }
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
        engine: any SpeechSynthesisEngine,
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
        dataManager.readAloud.markRendering(uuid: narration.uuid, chunkCount: 3)
        XCTAssertTrue(dataManager.readAloud.markCompleted(uuid: narration.uuid, episodeUuid: "ep-1", duration: 10, sizeInBytes: 10))

        let engine = FakeSynthesisEngine()
        let queue = makeQueue(engine: engine)
        await queue.restorePending()
        await queue.drainUntilIdle()

        let synthesized = await engine.synthesizedIndices
        XCTAssertEqual(synthesized, [])
    }

    // MARK: - Failure and cancellation

    func testWaitingForOneAttemptDoesNotWaitForUnrelatedQueueWork() async throws {
        let first = try makeNarration(text: "First narration.")
        let second = try makeNarration(text: "Second narration.")
        let engine = ControllableSynthesisEngine(concurrencyLimit: 1, gateStartingAtCall: 2)
        let queue = makeQueue(engine: engine)

        let firstAttempt = await queue.enqueue(uuid: first.uuid)
        let secondAttempt = await queue.enqueue(uuid: second.uuid)
        await engine.waitUntilStarted(2)

        let firstOutcome = await queue.waitForAttempt(firstAttempt)
        let isIdleWhileSecondIsBlocked = await queue.isIdle

        XCTAssertEqual(firstOutcome, .completed)
        XCTAssertFalse(isIdleWhileSecondIsBlocked, "waiting for the first attempt also waited for the blocked second attempt")
        await engine.open()
        let secondOutcome = await queue.waitForAttempt(secondAttempt)
        XCTAssertEqual(secondOutcome, .completed)
    }

    func testRetryWhileCancelledAttemptUnwindsCannotClobberReplacement() async throws {
        let narration = try makeNarration()
        let engine = ControllableSynthesisEngine(concurrencyLimit: 1, gateStartingAtCall: 1)
        let queue = makeQueue(engine: engine)

        let firstAttempt = await queue.enqueue(uuid: narration.uuid)
        await engine.waitUntilStarted(1)
        await queue.cancel(uuid: narration.uuid)
        XCTAssertEqual(dataManager.readAloud.narration(uuid: narration.uuid)?.narrationState, .cancelled)
        let retried = await queue.retry(uuid: narration.uuid)
        let retryAttempt = try XCTUnwrap(retried)
        await engine.open()

        let firstOutcome = await queue.waitForAttempt(firstAttempt)
        let retryOutcome = await queue.waitForAttempt(retryAttempt)
        XCTAssertEqual(firstOutcome, .superseded)
        XCTAssertEqual(retryOutcome, .completed)
        XCTAssertEqual(dataManager.readAloud.narration(uuid: narration.uuid)?.narrationState, .completed)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: storage.workspaceURL(narrationUuid: narration.uuid).path
        ))
    }

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
        // The workspace must exist first, or the assertion below would pass
        // vacuously without proving cancel(uuid:) removes anything.
        try storage.prepareWorkspace(narrationUuid: narration.uuid)
        try Data("chunk-0".utf8).write(to: storage.chunkURL(narrationUuid: narration.uuid, index: 0))
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

    /// Regression: a suspension that strands another narration in `pending`
    /// must be recoverable. Re-enqueueing the same uuid (what restorePending
    /// does on the next foreground) has to clear the flag AND drain — the old
    /// duplicate guard returned before draining, leaving the queue stuck.
    func testReEnqueueOfAPendingNarrationResumesAfterSuspension() async throws {
        let first = try makeNarration()
        let second = try makeNarration()
        let engine = GatedSynthesisEngine()
        let queue = makeQueue(engine: engine)

        await queue.enqueue(uuid: first.uuid)
        await queue.enqueue(uuid: second.uuid)
        // The first narration is parked inside its first chunk, so the
        // suspension deterministically lands before it can finish — and the
        // second never starts, because drain() refuses while suspended.
        await queue.suspendAfterCurrentChunk()
        await engine.open()
        await queue.drainUntilIdle()

        XCTAssertNotEqual(dataManager.readAloud.narration(uuid: second.uuid)?.narrationState, .completed)

        await queue.enqueue(uuid: second.uuid)
        await queue.drainUntilIdle()

        XCTAssertEqual(dataManager.readAloud.narration(uuid: second.uuid)?.narrationState, .completed)
    }

    // MARK: - Suspension

    /// The bug this replaced: suspension reused `ReadAloudError.cancelled`, so
    /// backgrounding the app mid-narration marked it cancelled — a state that is
    /// not resumable — and deleted the workspace every rendered chunk had been
    /// written to. Switching apps threw away all the work.
    func testSuspensionKeepsTheWorkspaceAndStaysResumable() async throws {
        let narration = try makeNarration()
        let engine = FakeSynthesisEngine(holdEachChunk: .milliseconds(20))
        let queue = makeQueue(engine: engine)

        await queue.enqueue(uuid: narration.uuid)
        // Let a chunk or two land, then expire the grace period.
        try await Task.sleep(for: .milliseconds(60))
        queue.suspendAfterCurrentChunk()
        await queue.drainUntilIdle()

        let loaded = try XCTUnwrap(dataManager.readAloud.narration(uuid: narration.uuid))
        XCTAssertTrue(
            NarrationState.resumable.contains(loaded.narrationState),
            "a suspended narration must still be resumable, was \(loaded.narrationState)"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: storage.workspaceURL(narrationUuid: narration.uuid).path),
            "suspension destroyed the checkpoint"
        )
        let renderedBefore = await engine.synthesizedIndices.count
        XCTAssertGreaterThan(renderedBefore, 0, "nothing rendered before suspension; the test proves nothing")
    }

    /// And the other half: what suspension leaves behind must actually resume,
    /// without re-rendering what already landed.
    func testASuspendedNarrationResumesWithoutRedoingWork() async throws {
        let narration = try makeNarration()
        let firstEngine = FakeSynthesisEngine(holdEachChunk: .milliseconds(20))
        let firstQueue = makeQueue(engine: firstEngine)

        await firstQueue.enqueue(uuid: narration.uuid)
        try await Task.sleep(for: .milliseconds(60))
        firstQueue.suspendAfterCurrentChunk()
        await firstQueue.drainUntilIdle()
        let renderedBeforeSuspension = await firstEngine.synthesizedIndices

        // A fresh launch: restorePending should pick it up off `rendering`.
        let secondEngine = FakeSynthesisEngine()
        let secondQueue = makeQueue(engine: secondEngine)
        await secondQueue.restorePending()
        await secondQueue.drainUntilIdle()

        XCTAssertEqual(dataManager.readAloud.narration(uuid: narration.uuid)?.narrationState, .completed)
        let redone = await secondEngine.synthesizedIndices
        XCTAssertTrue(
            Set(redone).isDisjoint(with: Set(renderedBeforeSuspension)),
            "resume re-rendered chunks that survived suspension"
        )
    }

    func testParallelSuspensionDrainsInflightChunksBeforeCheckpointing() async throws {
        let narration = try makeNarration()
        let engine = ControllableSynthesisEngine(concurrencyLimit: 3, gateStartingAtCall: 1)
        let queue = makeQueue(engine: engine)

        let attempt = await queue.enqueue(uuid: narration.uuid)
        await engine.waitUntilStarted(3)
        queue.suspendAfterCurrentChunk()
        await engine.open()

        let outcome = await queue.waitForAttempt(attempt)
        let completedCount = await engine.completedCount
        let activeCount = await engine.activeCount
        XCTAssertEqual(outcome, .suspended)
        XCTAssertEqual(completedCount, 3, "suspension started replacement chunks instead of only draining in-flight work")
        XCTAssertEqual(activeCount, 0, "attempt resolved before every in-flight child drained")
        let loaded = try XCTUnwrap(dataManager.readAloud.narration(uuid: narration.uuid))
        XCTAssertEqual(loaded.completedChunkCount, 3)
        XCTAssertEqual(
            storage.renderedChunkIndices(narrationUuid: narration.uuid, chunkCount: Int(loaded.chunkCount)).count,
            3
        )
    }

    func testChangedContentInvalidatesThePersistedWorkspaceManifest() async throws {
        let narration = try makeNarration()
        let firstEngine = FakeSynthesisEngine()
        let firstQueue = makeQueue(engine: firstEngine, assembler: FailingAssembler())
        await firstQueue.enqueue(uuid: narration.uuid)
        await firstQueue.drainUntilIdle()

        let original = try XCTUnwrap(dataManager.readAloud.narration(uuid: narration.uuid))
        XCTAssertGreaterThan(original.completedChunkCount, 0)
        let document = try XCTUnwrap(dataManager.readAloud.document(uuid: narration.documentUuid))
        let changedText = Self.sourceText.replacingOccurrences(of: "test document", with: "changed text!")
        try changedText.write(
            to: storage.sourceURL(relativePath: document.sourcePath),
            atomically: true,
            encoding: .utf8
        )

        let retryEngine = FakeSynthesisEngine()
        let retryQueue = makeQueue(engine: retryEngine)
        await retryQueue.retry(uuid: narration.uuid)
        await retryQueue.drainUntilIdle()

        let synthesizedCount = await retryEngine.synthesizedIndices.count
        XCTAssertEqual(dataManager.readAloud.narration(uuid: narration.uuid)?.narrationState, .completed)
        XCTAssertGreaterThan(
            synthesizedCount,
            0,
            "changed content reused checkpoints from the old manifest"
        )
    }

    func testInvalidChunkIsNeverPromotedOrTrustedAsACheckpoint() throws {
        let narrationUuid = "invalid-chunk"
        try storage.prepareWorkspace(narrationUuid: narrationUuid)
        let temporary = storage.partialChunkURL(narrationUuid: narrationUuid, index: 0, generation: 1)
        try Data("torn".utf8).write(to: temporary)

        XCTAssertThrowsError(
            try storage.commitRenderedChunk(from: temporary, narrationUuid: narrationUuid, index: 0)
        ) { error in
            XCTAssertEqual(error as? ReadAloudError, .synthesisProducedNoAudio)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.chunkURL(narrationUuid: narrationUuid, index: 0).path))

        let tornFinal = storage.chunkURL(narrationUuid: narrationUuid, index: 0)
        try Data("torn".utf8).write(to: tornFinal)
        XCTAssertEqual(storage.renderedChunkIndices(narrationUuid: narrationUuid, chunkCount: 1), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: tornFinal.path))
    }

    // MARK: - Orphan sweep

    /// Files can outlive their rows — an interrupted delete, a crash mid-render,
    /// a partial restore — and nothing else would ever reclaim them.
    func testSweepRemovesFilesWithNoRows() throws {
        let narration = try makeNarration()
        let document = try XCTUnwrap(dataManager.readAloud.document(uuid: narration.documentUuid))
        try storage.prepareWorkspace(narrationUuid: narration.uuid)

        // An orphan of each kind, alongside the live pair.
        let orphanSource = try storage.writeSource(text: "orphaned", documentUuid: "no-such-document")
        try storage.prepareWorkspace(narrationUuid: "no-such-narration")

        let removed = storage.sweepOrphans(
            liveDocumentUuids: [document.uuid],
            liveNarrationUuids: [narration.uuid]
        )

        XCTAssertEqual(removed, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.sourceURL(relativePath: orphanSource).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.workspaceURL(narrationUuid: "no-such-narration").path))
        // The live pair is untouched — the risk of a sweep is that it eats
        // something real.
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.sourceURL(relativePath: document.sourcePath).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.workspaceURL(narrationUuid: narration.uuid).path))
    }

    func testSweepIsANoOpWhenNothingIsOrphaned() throws {
        let narration = try makeNarration()
        let document = try XCTUnwrap(dataManager.readAloud.document(uuid: narration.documentUuid))

        let removed = storage.sweepOrphans(
            liveDocumentUuids: [document.uuid],
            liveNarrationUuids: [narration.uuid]
        )

        XCTAssertEqual(removed, 0)
    }

    // MARK: - Chunk concurrency

    /// Every local engine reports 1, and that path is the one verified working
    /// end to end, so it must stay exactly what it was: one chunk at a time.
    func testConcurrencyOfOneNeverOverlapsChunks() async throws {
        let narration = try makeNarration()
        let engine = FakeSynthesisEngine(concurrencyLimit: 1, holdEachChunk: .milliseconds(5))
        let queue = makeQueue(engine: engine)

        await queue.enqueue(uuid: narration.uuid)
        await queue.drainUntilIdle()

        let peak = await engine.maxConcurrent
        XCTAssertEqual(peak, 1, "chunks overlapped on an engine that asked for one at a time")
        let loaded = try XCTUnwrap(dataManager.readAloud.narration(uuid: narration.uuid))
        XCTAssertEqual(loaded.narrationState, .completed)
        XCTAssertEqual(loaded.completedChunkCount, loaded.chunkCount)
    }

    /// A network engine is latency-bound, so it may ask for several in flight.
    func testChunksRenderConcurrentlyUpToTheEngineLimit() async throws {
        let narration = try makeNarration()
        let engine = FakeSynthesisEngine(concurrencyLimit: 3, holdEachChunk: .milliseconds(20))
        let queue = makeQueue(engine: engine)

        await queue.enqueue(uuid: narration.uuid)
        await queue.drainUntilIdle()

        let peak = await engine.maxConcurrent
        XCTAssertGreaterThan(peak, 1, "the engine's concurrency allowance was ignored")
        XCTAssertLessThanOrEqual(peak, 3, "more chunks in flight than the engine allows")
    }

    /// Out-of-order completion is fine — the assembler reads files back by index
    /// — but every chunk must still be rendered exactly once.
    func testConcurrentRenderingCoversEveryChunkExactlyOnce() async throws {
        let narration = try makeNarration()
        let engine = FakeSynthesisEngine(concurrencyLimit: 4)
        let queue = makeQueue(engine: engine)

        await queue.enqueue(uuid: narration.uuid)
        await queue.drainUntilIdle()

        let loaded = try XCTUnwrap(dataManager.readAloud.narration(uuid: narration.uuid))
        let synthesized = await engine.synthesizedIndices
        XCTAssertEqual(Set(synthesized).count, synthesized.count, "a chunk was rendered twice")
        XCTAssertEqual(Set(synthesized), Set(0..<Int(loaded.chunkCount)))
        XCTAssertEqual(loaded.narrationState, .completed)
    }

    /// A failure inside the group must still fail the narration and still leave
    /// no partial file for the resume path to mistake for finished work.
    func testAFailingChunkUnderConcurrencyStillCleansUp() async throws {
        let narration = try makeNarration()
        let engine = FakeSynthesisEngine(failAtIndex: 2, writeFileBeforeFailing: true, concurrencyLimit: 3)
        let queue = makeQueue(engine: engine)

        await queue.enqueue(uuid: narration.uuid)
        await queue.drainUntilIdle()

        let loaded = try XCTUnwrap(dataManager.readAloud.narration(uuid: narration.uuid))
        XCTAssertEqual(loaded.narrationState, .failed)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: storage.chunkURL(narrationUuid: narration.uuid, index: 2).path),
            "a partial chunk file survived a concurrent failure"
        )
    }

    /// Resume must still skip finished work when several are in flight.
    func testConcurrentResumeSkipsRenderedChunks() async throws {
        let narration = try makeNarration()
        let firstQueue = makeQueue(engine: FakeSynthesisEngine(concurrencyLimit: 3), assembler: FailingAssembler())
        await firstQueue.enqueue(uuid: narration.uuid)
        await firstQueue.drainUntilIdle()

        let secondEngine = FakeSynthesisEngine(concurrencyLimit: 3)
        let secondQueue = makeQueue(engine: secondEngine)
        await secondQueue.retry(uuid: narration.uuid)
        await secondQueue.drainUntilIdle()

        let resumed = await secondEngine.synthesizedIndices
        XCTAssertEqual(resumed, [], "resume re-rendered chunks that were already on disk")
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
            maxConcurrentChunks: concurrencyLimit,
            requiresAPIKey: false,
            requiresConfirmation: false,
        )
    }

    private(set) var synthesizedIndices: [Int] = []
    private(set) var maxConcurrent = 0
    private var active = 0

    private let failAtIndex: Int?
    private let writeFileBeforeFailing: Bool
    private let concurrencyLimit: Int
    private let holdEachChunk: Duration?

    init(
        failAtIndex: Int? = nil,
        writeFileBeforeFailing: Bool = false,
        concurrencyLimit: Int = 1,
        holdEachChunk: Duration? = nil
    ) {
        self.failAtIndex = failAtIndex
        self.writeFileBeforeFailing = writeFileBeforeFailing
        self.concurrencyLimit = concurrencyLimit
        self.holdEachChunk = holdEachChunk
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

        if let holdEachChunk {
            try? await Task.sleep(for: holdEachChunk)
        }

        synthesizedIndices.append(chunk.index)
        try Data("chunk-\(chunk.index)".utf8).write(to: outputURL)
    }
}

/// Holds every synthesize call at a gate until `open()` — the deterministic way
/// to keep a narration "in flight" while the test changes queue state.
private actor GatedSynthesisEngine: SpeechSynthesisEngine {
    nonisolated let id = "test.gated"
    nonisolated var capabilities: EngineCapabilities {
        EngineCapabilities(
            maxCharactersPerChunk: 300,
            maxConcurrentChunks: 1,
            requiresAPIKey: false,
            requiresConfirmation: false,
        )
    }

    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Releases every waiting synthesize call; later calls pass straight through.
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
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
        if !isOpen {
            await withCheckedContinuation { waiters.append($0) }
        }
        try Data("chunk-\(chunk.index)".utf8).write(to: outputURL)
    }
}

/// Gates synthesis from a chosen call onward, while deliberately ignoring task
/// cancellation at the gate. That models provider work already in flight and
/// lets tests prove the queue waits for stale children to unwind safely.
private actor ControllableSynthesisEngine: SpeechSynthesisEngine {
    nonisolated let id = "test.controllable"
    nonisolated var capabilities: EngineCapabilities {
        EngineCapabilities(
            maxCharactersPerChunk: 300,
            maxConcurrentChunks: concurrencyLimit,
            requiresAPIKey: false,
            requiresConfirmation: false,
        )
    }

    private let concurrencyLimit: Int
    private let gateStartingAtCall: Int
    private var isOpen = false
    private var started = 0
    private(set) var completedCount = 0
    private(set) var activeCount = 0
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private var startTarget: Int?
    private var startWaiter: CheckedContinuation<Void, Never>?

    init(concurrencyLimit: Int, gateStartingAtCall: Int) {
        self.concurrencyLimit = concurrencyLimit
        self.gateStartingAtCall = gateStartingAtCall
    }

    func waitUntilStarted(_ count: Int) async {
        guard started < count else { return }
        await withCheckedContinuation { continuation in
            startTarget = count
            startWaiter = continuation
        }
    }

    func open() {
        isOpen = true
        gateWaiters.forEach { $0.resume() }
        gateWaiters.removeAll()
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
        started += 1
        activeCount += 1
        if let startTarget, started >= startTarget {
            self.startTarget = nil
            startWaiter?.resume()
            startWaiter = nil
        }
        defer { activeCount -= 1 }

        if started >= gateStartingAtCall, !isOpen {
            await withCheckedContinuation { gateWaiters.append($0) }
        }
        completedCount += 1
        try Data("chunk-\(chunk.index)".utf8).write(to: outputURL)
    }
}

private struct FakeEngineFactory: NarrationEngineProviding {
    let engine: any SpeechSynthesisEngine

    func makeEngine(for kind: NarrationEngineKind, providerId: String?, modelId: String?) throws -> any SpeechSynthesisEngine {
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
