import AVFoundation
import Foundation
@testable import PocketCastsReadAloud
@testable import podcasts
import XCTest

/// Coverage for joining rendered chunks into the episode's audio file, over the
/// real `AVMutableComposition` + AAC encode path.
final class NarrationAssemblerTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NarrationAssemblerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    /// Writes a silent PCM chunk of a known length, standing in for a
    /// synthesized utterance.
    private func makeChunk(seconds: Double, name: String) throws -> URL {
        let url = root.appendingPathComponent("\(name).caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        let frameCount = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        try file.write(from: buffer)
        return url
    }

    private func duration(of url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    func testChunksAreJoinedInOrder() async throws {
        let chunks = [
            try makeChunk(seconds: 0.5, name: "a"),
            try makeChunk(seconds: 0.5, name: "b"),
            try makeChunk(seconds: 0.5, name: "c"),
        ]
        let outputURL = root.appendingPathComponent("out.m4a")

        let output = try await NarrationAssembler().assemble(
            chunkURLs: chunks,
            pauseBefore: [],
            outputURL: outputURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertGreaterThan(output.sizeInBytes, 0)
        // AAC pads to frame boundaries, so this is deliberately loose.
        XCTAssertEqual(output.duration, 1.5, accuracy: 0.1)
    }

    /// Paragraph pauses are inserted as empty time ranges, so they must show up
    /// in the finished duration.
    func testBlockOpeningsAddAPause() async throws {
        let chunks = [
            try makeChunk(seconds: 0.5, name: "a"),
            try makeChunk(seconds: 0.5, name: "b"),
        ]
        let outputURL = root.appendingPathComponent("paused.m4a")

        let output = try await NarrationAssembler().assemble(
            chunkURLs: chunks,
            pauseBefore: [1],
            outputURL: outputURL
        )

        let expected = 1.0 + NarrationAssembler.paragraphPause.seconds
        XCTAssertEqual(output.duration, expected, accuracy: 0.1)
    }

    /// A pause before the first chunk would just be dead air at the head of the
    /// episode.
    func testNoPauseIsAddedBeforeTheFirstChunk() async throws {
        let chunks = [try makeChunk(seconds: 0.5, name: "a")]
        let outputURL = root.appendingPathComponent("first.m4a")

        let output = try await NarrationAssembler().assemble(
            chunkURLs: chunks,
            pauseBefore: [0],
            outputURL: outputURL
        )

        XCTAssertEqual(output.duration, 0.5, accuracy: 0.1)
    }

    func testOutputIsMonoAAC() async throws {
        let chunks = [try makeChunk(seconds: 0.5, name: "a")]
        let outputURL = root.appendingPathComponent("format.m4a")

        _ = try await NarrationAssembler().assemble(chunkURLs: chunks, pauseBefore: [], outputURL: outputURL)

        let tracks = try await AVURLAsset(url: outputURL).loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let descriptions = try await track.load(.formatDescriptions)
        let basicDescription = try XCTUnwrap(descriptions.first?.audioStreamBasicDescription)
        XCTAssertEqual(basicDescription.mChannelsPerFrame, 1)
        XCTAssertEqual(basicDescription.mFormatID, kAudioFormatMPEG4AAC)
    }

    func testAnEmptyChunkListIsRefused() async throws {
        do {
            _ = try await NarrationAssembler().assemble(
                chunkURLs: [],
                pauseBefore: [],
                outputURL: root.appendingPathComponent("empty.m4a")
            )
            XCTFail("expected assembly to fail")
        } catch {
            XCTAssertEqual(error as? ReadAloudError, .assemblyFailed)
        }
    }

    /// Assembling around a missing or empty chunk would ship a silently
    /// truncated episode, which is worse than failing and offering a retry.
    func testAnUnreadableChunkFailsRatherThanTruncating() async throws {
        let good = try makeChunk(seconds: 0.5, name: "a")
        let bad = root.appendingPathComponent("bad.caf")
        try Data("not audio".utf8).write(to: bad)

        do {
            _ = try await NarrationAssembler().assemble(
                chunkURLs: [good, bad],
                pauseBefore: [],
                outputURL: root.appendingPathComponent("truncated.m4a")
            )
            XCTFail("expected assembly to fail")
        } catch {
            XCTAssertEqual(error as? ReadAloudError, .assemblyFailed)
        }
    }

    func testAStaleOutputFileIsReplaced() async throws {
        let outputURL = root.appendingPathComponent("stale.m4a")
        try Data(repeating: 0, count: 4096).write(to: outputURL)
        let chunks = [try makeChunk(seconds: 0.5, name: "a")]

        let output = try await NarrationAssembler().assemble(
            chunkURLs: chunks,
            pauseBefore: [],
            outputURL: outputURL
        )

        XCTAssertEqual(output.duration, 0.5, accuracy: 0.1)
        let readBack = try await duration(of: outputURL)
        XCTAssertEqual(readBack, 0.5, accuracy: 0.1)
    }
}
