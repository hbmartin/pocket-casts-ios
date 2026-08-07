import GRDB
@testable import PocketCastsDataModel
import XCTest

/// Coverage for the Read Aloud store (migration 91, ADR-0019, ADR-0020).
final class ReadAloudDataManagerTests: DataManagerTestCase {
    private func document(
        uuid: String = UUID().uuidString.lowercased(),
        title: String = "A Document",
        addedDate: Double = 1000
    ) -> ReadAloudDocumentRecord {
        var record = ReadAloudDocumentRecord()
        record.uuid = uuid
        record.title = title
        record.sourcePath = "\(uuid).txt"
        record.characterCount = 1234
        record.addedDate = addedDate
        return record
    }

    private func narration(
        uuid: String = UUID().uuidString.lowercased(),
        documentUuid: String,
        state: NarrationState = .queued,
        createdDate: Double = 1000
    ) -> NarrationRecord {
        var record = NarrationRecord()
        record.uuid = uuid
        record.documentUuid = documentUuid
        record.voiceId = "com.apple.voice.compact.en-US.Samantha"
        record.voiceName = "Samantha"
        record.narrationState = state
        record.createdDate = createdDate
        return record
    }

    // MARK: - Round trip

    func testDocumentRoundTripsEveryField() throws {
        try runWithBothImplementations { dataManager, _ in
            var record = document(uuid: "d1")
            record.originalFilename = "Essay.md"
            record.source = .shared
            record.utType = "net.daringfireball.markdown"
            record.language = "en"

            XCTAssertTrue(dataManager.readAloud.add(record))

            let loaded = try XCTUnwrap(dataManager.readAloud.document(uuid: "d1"))
            XCTAssertEqual(loaded.title, "A Document")
            XCTAssertEqual(loaded.originalFilename, "Essay.md")
            XCTAssertEqual(loaded.source, .shared)
            XCTAssertEqual(loaded.utType, "net.daringfireball.markdown")
            XCTAssertEqual(loaded.sourcePath, "d1.txt")
            XCTAssertEqual(loaded.characterCount, 1234)
            XCTAssertEqual(loaded.language, "en")
        }
    }

    func testNarrationRoundTripsEveryField() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "d1"))
            var record = narration(uuid: "n1", documentUuid: "d1")
            record.engine = .remoteProvider
            record.providerId = "elevenlabs"
            record.rate = 1.25

            XCTAssertTrue(dataManager.readAloud.add(record))

            let loaded = try XCTUnwrap(dataManager.readAloud.narration(uuid: "n1"))
            XCTAssertEqual(loaded.documentUuid, "d1")
            XCTAssertEqual(loaded.engine, .remoteProvider)
            XCTAssertEqual(loaded.providerId, "elevenlabs")
            XCTAssertEqual(loaded.voiceId, "com.apple.voice.compact.en-US.Samantha")
            XCTAssertEqual(loaded.rate, 1.25)
            XCTAssertEqual(loaded.narrationState, .queued)
        }
    }

    func testUuidsAreUnique() throws {
        try runWithBothImplementations { dataManager, _ in
            XCTAssertTrue(dataManager.readAloud.add(document(uuid: "dupe")))
            XCTAssertFalse(dataManager.readAloud.add(document(uuid: "dupe")))

            dataManager.readAloud.add(document(uuid: "d1"))
            XCTAssertTrue(dataManager.readAloud.add(narration(uuid: "n-dupe", documentUuid: "d1")))
            XCTAssertFalse(dataManager.readAloud.add(narration(uuid: "n-dupe", documentUuid: "d1")))
        }
    }

    /// A failure between the two inserts must not leave a document nobody asked
    /// for sitting in the library.
    func testPairedInsertIsAtomic() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(narration(uuid: "taken", documentUuid: "d1"))

            let inserted = dataManager.readAloud.add(
                document: document(uuid: "d1"),
                narration: narration(uuid: "taken", documentUuid: "d1")
            )

            XCTAssertFalse(inserted)
            XCTAssertNil(dataManager.readAloud.document(uuid: "d1"))
        }
    }

    // MARK: - Re-narration

    /// The point of the document table: several narrations share one document
    /// and one source file.
    func testADocumentCanCarrySeveralNarrations() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "d1"))
            dataManager.readAloud.add(narration(uuid: "first", documentUuid: "d1", createdDate: 100))
            dataManager.readAloud.add(narration(uuid: "second", documentUuid: "d1", createdDate: 200))

            XCTAssertEqual(dataManager.readAloud.narrations(documentUuid: "d1").map(\.uuid), ["second", "first"])
            XCTAssertEqual(dataManager.readAloud.document(uuid: "d1")?.sourcePath, "d1.txt")
        }
    }

    func testLibraryPairsDocumentsWithTheirNarrations() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "older", addedDate: 100))
            dataManager.readAloud.add(document(uuid: "newer", addedDate: 200))
            dataManager.readAloud.add(narration(uuid: "n1", documentUuid: "older", createdDate: 10))
            dataManager.readAloud.add(narration(uuid: "n2", documentUuid: "older", createdDate: 20))

            let library = dataManager.readAloud.library()

            XCTAssertEqual(library.map(\.document.uuid), ["newer", "older"])
            XCTAssertEqual(library[0].narrations, [], "a document with no narrations still appears")
            XCTAssertEqual(library[1].narrations.map(\.uuid), ["n2", "n1"])
        }
    }

    func testRenamingADocumentLeavesItsNarrationsAlone() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "d1"))
            dataManager.readAloud.add(narration(uuid: "n1", documentUuid: "d1"))

            XCTAssertTrue(dataManager.readAloud.renameDocument(uuid: "d1", title: "Renamed"))

            XCTAssertEqual(dataManager.readAloud.document(uuid: "d1")?.title, "Renamed")
            XCTAssertEqual(dataManager.readAloud.narrations(documentUuid: "d1").count, 1)
        }
    }

    // MARK: - Progress and terminal states

    func testRenderingRecordsChunkCountAndClearsPriorError() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "d1"))
            dataManager.readAloud.add(narration(uuid: "n1", documentUuid: "d1"))
            dataManager.readAloud.markFailed(uuid: "n1", errorCode: "network_unavailable", errorDetails: "detail")

            XCTAssertTrue(dataManager.readAloud.markRendering(uuid: "n1", chunkCount: 7))

            let loaded = try XCTUnwrap(dataManager.readAloud.narration(uuid: "n1"))
            XCTAssertEqual(loaded.narrationState, .rendering)
            XCTAssertEqual(loaded.chunkCount, 7)
            XCTAssertNil(loaded.errorCode)
            XCTAssertNil(loaded.errorDetails)
        }
    }

    func testCompletionLinksTheEpisode() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "d1"))
            dataManager.readAloud.add(narration(uuid: "n1", documentUuid: "d1", state: .rendering))

            XCTAssertTrue(dataManager.readAloud.markCompleted(
                uuid: "n1", episodeUuid: "ep-1", duration: 123.5, sizeInBytes: 4096
            ))

            let loaded = try XCTUnwrap(dataManager.readAloud.narration(uuid: "n1"))
            XCTAssertEqual(loaded.narrationState, .completed)
            XCTAssertEqual(loaded.episodeUuid, "ep-1")
            XCTAssertEqual(loaded.outputDuration, 123.5)
            XCTAssertEqual(loaded.outputSizeInBytes, 4096)
            XCTAssertNotNil(loaded.completedDate)
        }
    }

    /// A cancellation that raced the final assembly must win: completion
    /// updates nothing once the row has left `rendering`.
    func testCompletionLosesToACancellationThatRacedIt() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "d1"))
            dataManager.readAloud.add(narration(uuid: "n1", documentUuid: "d1", state: .rendering))
            dataManager.readAloud.markCancelled(uuid: "n1")

            XCTAssertFalse(dataManager.readAloud.markCompleted(uuid: "n1", episodeUuid: "ep-1", duration: 1, sizeInBytes: 1))

            XCTAssertEqual(dataManager.readAloud.narration(uuid: "n1")?.narrationState, .cancelled)
            XCTAssertNil(dataManager.readAloud.narration(uuid: "n1")?.episodeUuid)
        }
    }

    /// Retrying keeps the checkpoint: chunks already rendered are still valid
    /// because the settings that produced them are frozen on the row.
    func testRequeueingKeepsTheCheckpoint() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "d1"))
            dataManager.readAloud.add(narration(uuid: "n1", documentUuid: "d1"))
            dataManager.readAloud.markRendering(uuid: "n1", chunkCount: 5)
            dataManager.readAloud.updateProgress(uuid: "n1", completedChunkCount: 3)
            dataManager.readAloud.markFailed(uuid: "n1", errorCode: "network_unavailable", errorDetails: nil)

            XCTAssertTrue(dataManager.readAloud.markQueued(uuid: "n1"))

            let loaded = try XCTUnwrap(dataManager.readAloud.narration(uuid: "n1"))
            XCTAssertEqual(loaded.narrationState, .queued)
            XCTAssertEqual(loaded.completedChunkCount, 3)
            XCTAssertNil(loaded.errorCode)
        }
    }

    // MARK: - Resume

    func testPendingResumeCoversQueuedAndRenderingOldestFirst() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "d1"))
            dataManager.readAloud.add(narration(uuid: "queued", documentUuid: "d1", state: .queued, createdDate: 200))
            dataManager.readAloud.add(narration(uuid: "rendering", documentUuid: "d1", state: .rendering, createdDate: 100))
            dataManager.readAloud.add(narration(uuid: "done", documentUuid: "d1", state: .completed, createdDate: 50))
            dataManager.readAloud.add(narration(uuid: "failed", documentUuid: "d1", state: .failed, createdDate: 60))
            dataManager.readAloud.add(narration(uuid: "cancelled", documentUuid: "d1", state: .cancelled, createdDate: 70))

            XCTAssertEqual(dataManager.readAloud.narrationsPendingResume().map(\.uuid), ["rendering", "queued"])
        }
    }

    // MARK: - Deletion (ADR-0019)

    /// Deleting the episode takes its narration but never the document — that is
    /// the promise a swipe on the Files screen has to keep.
    func testDeletingAnEpisodeRemovesItsNarrationAndKeepsTheDocument() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "d1"))
            dataManager.readAloud.add(narration(uuid: "n1", documentUuid: "d1", state: .rendering))
            dataManager.readAloud.markCompleted(uuid: "n1", episodeUuid: "ep-1", duration: 60, sizeInBytes: 1024)

            let removed = try XCTUnwrap(dataManager.readAloud.deleteNarration(episodeUuid: "ep-1"))

            XCTAssertEqual(removed.uuid, "n1")
            XCTAssertNil(dataManager.readAloud.narration(uuid: "n1"))
            let survivor = try XCTUnwrap(dataManager.readAloud.document(uuid: "d1"))
            XCTAssertEqual(survivor.sourcePath, "d1.txt")
        }
    }

    /// Ordinary uploaded files are deleted constantly; this has to report that
    /// it did nothing so callers can skip the follow-up work.
    func testDeletingAnUnrelatedEpisodeReportsNoNarration() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "d1"))
            dataManager.readAloud.add(narration(uuid: "n1", documentUuid: "d1", state: .rendering))
            dataManager.readAloud.markCompleted(uuid: "n1", episodeUuid: "ep-1", duration: 60, sizeInBytes: 1024)

            XCTAssertNil(dataManager.readAloud.deleteNarration(episodeUuid: "some-other-upload"))
            XCTAssertNotNil(dataManager.readAloud.narration(uuid: "n1"))
        }
    }

    func testDeleteNarrationByUuidReportsWhetherARowWasRemoved() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "d1"))
            dataManager.readAloud.add(narration(uuid: "n1", documentUuid: "d1"))

            XCTAssertTrue(dataManager.readAloud.deleteNarration(uuid: "n1"))
            XCTAssertFalse(dataManager.readAloud.deleteNarration(uuid: "n1"), "nothing left to delete")
        }
    }

    func testDeletingADocumentCascadesToItsNarrations() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "d1"))
            dataManager.readAloud.add(document(uuid: "d2"))
            dataManager.readAloud.add(narration(uuid: "n1", documentUuid: "d1"))
            dataManager.readAloud.add(narration(uuid: "n2", documentUuid: "d1"))
            dataManager.readAloud.add(narration(uuid: "other", documentUuid: "d2"))

            let removed = dataManager.readAloud.deleteDocument(uuid: "d1")

            XCTAssertEqual(Set(removed.map(\.uuid)), ["n1", "n2"], "callers need these to clean up workspaces and episodes")
            XCTAssertNil(dataManager.readAloud.document(uuid: "d1"))
            XCTAssertNil(dataManager.readAloud.narration(uuid: "n1"))
            XCTAssertNotNil(dataManager.readAloud.narration(uuid: "other"))
        }
    }

    func testLookupByEpisodeUuid() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "d1"))
            dataManager.readAloud.add(narration(uuid: "n1", documentUuid: "d1", state: .rendering))
            dataManager.readAloud.markCompleted(uuid: "n1", episodeUuid: "ep-1", duration: 60, sizeInBytes: 1024)

            XCTAssertEqual(dataManager.readAloud.narration(episodeUuid: "ep-1")?.uuid, "n1")
            XCTAssertNil(dataManager.readAloud.narration(episodeUuid: "ep-2"))
        }
    }

    func testAllDocumentsAreNewestFirst() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.readAloud.add(document(uuid: "old", addedDate: 100))
            dataManager.readAloud.add(document(uuid: "new", addedDate: 300))
            dataManager.readAloud.add(document(uuid: "middle", addedDate: 200))

            XCTAssertEqual(dataManager.readAloud.allDocuments().map(\.uuid), ["new", "middle", "old"])
            XCTAssertEqual(dataManager.readAloud.allDocuments(limit: 2).map(\.uuid), ["new", "middle"])
        }
    }

    // MARK: - Defensive decoding

    /// An unknown persisted raw value must fall back rather than trap: a row
    /// written by a newer build has to stay readable after a downgrade.
    func testUnknownRawValuesFallBack() throws {
        try runWithBothImplementations { dataManager, _ in
            var documentRecord = document(uuid: "d1")
            documentRecord.sourceKind = 99
            dataManager.readAloud.add(documentRecord)

            var narrationRecord = narration(uuid: "n1", documentUuid: "d1")
            narrationRecord.state = 99
            narrationRecord.engineKind = 99
            dataManager.readAloud.add(narrationRecord)

            XCTAssertEqual(dataManager.readAloud.document(uuid: "d1")?.source, .picked)
            let loaded = try XCTUnwrap(dataManager.readAloud.narration(uuid: "n1"))
            XCTAssertEqual(loaded.narrationState, .queued)
            XCTAssertEqual(loaded.engine, .appleBuiltIn)
        }
    }
}
