import XCTest

@testable import podcasts

/// Pure validation of on-device chapter generation and the per-episode cache.
@MainActor
final class TranscriptChapterGeneratorTests: XCTestCase {
    private let cueStarts: [TimeInterval] = stride(from: 0.0, through: 3600, by: 30).map { $0 }

    private func item(_ title: String, _ seconds: Int) -> GeneratedChapterListItem {
        GeneratedChapterListItem(title: title, startSeconds: seconds)
    }

    func testValidationSnapsSortsAndSpacesChapters() {
        let raw = [
            item("Closing thoughts", 3550),
            item("Intro", 12),
            item("Main topic", 900),
            item("Too close to main topic", 930),
            item("  ", 1800)
        ]

        let chapters = TranscriptChapterGenerator.validated(raw, cueStartTimes: cueStarts, duration: 3600)

        XCTAssertEqual(chapters.map(\.title), ["Intro", "Main topic", "Closing thoughts"])
        XCTAssertEqual(chapters.first?.startTime, 0, "An opening chapter near zero is pulled to the episode start")
        XCTAssertEqual(chapters.map(\.startTime), chapters.map(\.startTime).sorted())
        XCTAssertTrue(zip(chapters, chapters.dropFirst()).allSatisfy { $1.startTime - $0.startTime >= 60 },
                      "Chapters closer than the minimum gap are dropped")
    }

    func testValidationDropsUnsnappableTimestamps() {
        // Cues only cover the first 10 minutes; a chapter at 50 minutes has no
        // nearby cue and must be dropped rather than invented.
        let shortCues: [TimeInterval] = stride(from: 0.0, through: 600, by: 30).map { $0 }
        let chapters = TranscriptChapterGenerator.validated([item("Ghost", 3000), item("Real", 300)],
                                                            cueStartTimes: shortCues,
                                                            duration: 3600)

        XCTAssertEqual(chapters.map(\.title), ["Real"])
    }

    func testValidationClampsToDuration() {
        let chapters = TranscriptChapterGenerator.validated([item("Beyond the end", 9000)],
                                                            cueStartTimes: cueStarts,
                                                            duration: 3600)

        XCTAssertEqual(chapters.map(\.startTime), [3600])
    }

    func testTimestampStringFormats() {
        XCTAssertEqual(TranscriptChapterGenerator.timestampString(for: 65), "1:05")
        XCTAssertEqual(TranscriptChapterGenerator.timestampString(for: 3725), "1:02:05")
    }

    func testStoreRoundTripsChapters() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chapter-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OnDeviceChapterStore(directoryURL: directory)

        XCTAssertNil(store.load(episodeUuid: "ep-1"))

        let chapters = [
            GeneratedChapter(title: "Intro", timestamp: "0:00", startTime: 0),
            GeneratedChapter(title: "Topic", timestamp: "15:00", startTime: 900)
        ]
        store.save(chapters, episodeUuid: "ep-1")

        let loaded = try XCTUnwrap(store.load(episodeUuid: "ep-1"))
        XCTAssertEqual(loaded.map(\.title), ["Intro", "Topic"])
        XCTAssertEqual(loaded.map(\.startTime), [0, 900])
        XCTAssertEqual(loaded.map(\.timestamp), ["0:00", "15:00"], "Timestamps regenerate from start times")
        XCTAssertNil(store.load(episodeUuid: "ep-other"))
    }
}
