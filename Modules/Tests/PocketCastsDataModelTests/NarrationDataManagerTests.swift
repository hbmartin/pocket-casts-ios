import GRDB
@testable import PocketCastsDataModel
import XCTest

/// Coverage for the Read Aloud narration store (migration 91, ADR-0019).
final class NarrationDataManagerTests: DataManagerTestCase {
    private func narration(
        uuid: String = UUID().uuidString.lowercased(),
        title: String = "A Document",
        state: NarrationState = .queued,
        createdDate: Double = 1000
    ) -> NarrationRecord {
        var record = NarrationRecord()
        record.uuid = uuid
        record.title = title
        record.sourcePath = "\(uuid).txt"
        record.characterCount = 1234
        record.voiceId = "com.apple.voice.compact.en-US.Samantha"
        record.voiceName = "Samantha"
        record.narrationState = state
        record.createdDate = createdDate
        return record
    }

    // MARK: - Round trip

    func testAddAndFetchRoundTripsEveryField() throws {
        try runWithBothImplementations { dataManager, _ in
            var record = narration(uuid: "n1")
            record.originalFilename = "Essay.md"
            record.source = .shared
            record.utType = "net.daringfireball.markdown"
            record.language = "en"
            record.engine = .remoteProvider
            record.providerId = "elevenlabs"
            record.rate = 1.25

            XCTAssertTrue(dataManager.narrations.add(record))

            let loaded = try XCTUnwrap(dataManager.narrations.narration(uuid: "n1"))
            XCTAssertEqual(loaded.title, "A Document")
            XCTAssertEqual(loaded.originalFilename, "Essay.md")
            XCTAssertEqual(loaded.source, .shared)
            XCTAssertEqual(loaded.utType, "net.daringfireball.markdown")
            XCTAssertEqual(loaded.sourcePath, "n1.txt")
            XCTAssertEqual(loaded.characterCount, 1234)
            XCTAssertEqual(loaded.language, "en")
            XCTAssertEqual(loaded.engine, .remoteProvider)
            XCTAssertEqual(loaded.providerId, "elevenlabs")
            XCTAssertEqual(loaded.voiceId, "com.apple.voice.compact.en-US.Samantha")
            XCTAssertEqual(loaded.rate, 1.25)
            XCTAssertEqual(loaded.narrationState, .queued)
        }
    }

    func testUuidIsUnique() throws {
        try runWithBothImplementations { dataManager, _ in
            XCTAssertTrue(dataManager.narrations.add(narration(uuid: "dupe")))
            XCTAssertFalse(dataManager.narrations.add(narration(uuid: "dupe")))
        }
    }

    func testMissingNarrationIsNil() throws {
        try runWithBothImplementations { dataManager, _ in
            XCTAssertNil(dataManager.narrations.narration(uuid: "nope"))
        }
    }

    // MARK: - Progress and terminal states

    func testRenderingRecordsChunkCountAndClearsPriorError() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.narrations.add(narration(uuid: "n1"))
            dataManager.narrations.markFailed(uuid: "n1", errorCode: "network_unavailable", errorDetails: "detail")

            XCTAssertTrue(dataManager.narrations.markRendering(uuid: "n1", chunkCount: 7))

            let loaded = try XCTUnwrap(dataManager.narrations.narration(uuid: "n1"))
            XCTAssertEqual(loaded.narrationState, .rendering)
            XCTAssertEqual(loaded.chunkCount, 7)
            XCTAssertNil(loaded.errorCode)
            XCTAssertNil(loaded.errorDetails)
        }
    }

    func testProgressAdvancesTheCheckpoint() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.narrations.add(narration(uuid: "n1"))
            dataManager.narrations.markRendering(uuid: "n1", chunkCount: 5)

            dataManager.narrations.updateProgress(uuid: "n1", completedChunkCount: 3)

            XCTAssertEqual(dataManager.narrations.narration(uuid: "n1")?.completedChunkCount, 3)
        }
    }

    func testCompletionLinksTheEpisode() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.narrations.add(narration(uuid: "n1"))

            XCTAssertTrue(dataManager.narrations.markCompleted(
                uuid: "n1", episodeUuid: "ep-1", duration: 123.5, sizeInBytes: 4096
            ))

            let loaded = try XCTUnwrap(dataManager.narrations.narration(uuid: "n1"))
            XCTAssertEqual(loaded.narrationState, .completed)
            XCTAssertEqual(loaded.episodeUuid, "ep-1")
            XCTAssertEqual(loaded.outputDuration, 123.5)
            XCTAssertEqual(loaded.outputSizeInBytes, 4096)
            XCTAssertNotNil(loaded.completedDate)
        }
    }

    /// The failure detail is developer-authored; provider text must never reach
    /// this column because it can echo the user's document.
    func testFailureRecordsCodeAndDetail() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.narrations.add(narration(uuid: "n1"))

            dataManager.narrations.markFailed(uuid: "n1", errorCode: "rate_limited", errorDetails: "rateLimited")

            let loaded = try XCTUnwrap(dataManager.narrations.narration(uuid: "n1"))
            XCTAssertEqual(loaded.narrationState, .failed)
            XCTAssertEqual(loaded.errorCode, "rate_limited")
            XCTAssertEqual(loaded.errorDetails, "rateLimited")
        }
    }

    /// Retrying keeps the checkpoint: chunks already rendered are still valid
    /// because the settings that produced them are frozen on the row.
    func testRequeueingKeepsTheCheckpoint() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.narrations.add(narration(uuid: "n1"))
            dataManager.narrations.markRendering(uuid: "n1", chunkCount: 5)
            dataManager.narrations.updateProgress(uuid: "n1", completedChunkCount: 3)
            dataManager.narrations.markFailed(uuid: "n1", errorCode: "network_unavailable", errorDetails: nil)

            XCTAssertTrue(dataManager.narrations.markQueued(uuid: "n1"))

            let loaded = try XCTUnwrap(dataManager.narrations.narration(uuid: "n1"))
            XCTAssertEqual(loaded.narrationState, .queued)
            XCTAssertEqual(loaded.completedChunkCount, 3)
            XCTAssertNil(loaded.errorCode)
        }
    }

    // MARK: - Resume

    func testPendingResumeCoversQueuedAndRenderingOldestFirst() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.narrations.add(narration(uuid: "queued", state: .queued, createdDate: 200))
            dataManager.narrations.add(narration(uuid: "rendering", state: .rendering, createdDate: 100))
            dataManager.narrations.add(narration(uuid: "done", state: .completed, createdDate: 50))
            dataManager.narrations.add(narration(uuid: "failed", state: .failed, createdDate: 60))
            dataManager.narrations.add(narration(uuid: "cancelled", state: .cancelled, createdDate: 70))
            dataManager.narrations.add(narration(uuid: "detached", state: .detached, createdDate: 80))

            let pending = dataManager.narrations.narrationsPendingResume()

            XCTAssertEqual(pending.map(\.uuid), ["rendering", "queued"])
        }
    }

    /// A process kill leaves the row mid-run, so `rendering` must be resumable —
    /// there is no chance to write a "stopped" state on the way down.
    func testRenderingRowsSurviveAsResumable() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.narrations.add(narration(uuid: "n1", state: .rendering))

            XCTAssertEqual(dataManager.narrations.narrationsPendingResume().map(\.uuid), ["n1"])
        }
    }

    // MARK: - Detach (ADR-0019)

    func testDetachClearsTheEpisodeButKeepsTheDocument() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.narrations.add(narration(uuid: "n1"))
            dataManager.narrations.markCompleted(uuid: "n1", episodeUuid: "ep-1", duration: 60, sizeInBytes: 1024)

            XCTAssertTrue(dataManager.narrations.detachEpisode(episodeUuid: "ep-1"))

            let loaded = try XCTUnwrap(dataManager.narrations.narration(uuid: "n1"))
            XCTAssertEqual(loaded.narrationState, .detached)
            XCTAssertNil(loaded.episodeUuid)
            XCTAssertNil(loaded.outputDuration)
            XCTAssertNil(loaded.outputSizeInBytes)
            // The document itself is untouched — that is the whole point.
            XCTAssertEqual(loaded.sourcePath, "n1.txt")
            XCTAssertEqual(loaded.title, "A Document")
        }
    }

    /// Ordinary uploaded files are deleted constantly; detach must report that
    /// it did nothing so callers can skip the follow-up work.
    func testDetachingAnUnrelatedEpisodeReportsNoChange() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.narrations.add(narration(uuid: "n1"))
            dataManager.narrations.markCompleted(uuid: "n1", episodeUuid: "ep-1", duration: 60, sizeInBytes: 1024)

            XCTAssertFalse(dataManager.narrations.detachEpisode(episodeUuid: "some-other-upload"))
            XCTAssertEqual(dataManager.narrations.narration(uuid: "n1")?.narrationState, .completed)
        }
    }

    func testLookupByEpisodeUuid() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.narrations.add(narration(uuid: "n1"))
            dataManager.narrations.markCompleted(uuid: "n1", episodeUuid: "ep-1", duration: 60, sizeInBytes: 1024)

            XCTAssertEqual(dataManager.narrations.narration(episodeUuid: "ep-1")?.uuid, "n1")
            XCTAssertNil(dataManager.narrations.narration(episodeUuid: "ep-2"))
        }
    }

    // MARK: - Listing and deletion

    func testAllNarrationsAreNewestFirst() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.narrations.add(narration(uuid: "old", createdDate: 100))
            dataManager.narrations.add(narration(uuid: "new", createdDate: 300))
            dataManager.narrations.add(narration(uuid: "middle", createdDate: 200))

            XCTAssertEqual(dataManager.narrations.allNarrations().map(\.uuid), ["new", "middle", "old"])
            XCTAssertEqual(dataManager.narrations.allNarrations(limit: 2).map(\.uuid), ["new", "middle"])
        }
    }

    func testDeleteRemovesOnlyTheNamedRow() throws {
        try runWithBothImplementations { dataManager, _ in
            dataManager.narrations.add(narration(uuid: "n1"))
            dataManager.narrations.add(narration(uuid: "n2"))

            XCTAssertTrue(dataManager.narrations.delete(uuid: "n1"))

            XCTAssertNil(dataManager.narrations.narration(uuid: "n1"))
            XCTAssertNotNil(dataManager.narrations.narration(uuid: "n2"))
        }
    }

    // MARK: - Defensive decoding

    /// An unknown persisted raw value must fall back rather than trap: a row
    /// written by a newer build has to stay readable after a downgrade.
    func testUnknownRawValuesFallBack() throws {
        try runWithBothImplementations { dataManager, _ in
            var record = narration(uuid: "n1")
            record.state = 99
            record.engineKind = 99
            record.sourceKind = 99
            dataManager.narrations.add(record)

            let loaded = try XCTUnwrap(dataManager.narrations.narration(uuid: "n1"))
            XCTAssertEqual(loaded.narrationState, .queued)
            XCTAssertEqual(loaded.engine, .appleBuiltIn)
            XCTAssertEqual(loaded.source, .picked)
        }
    }
}
