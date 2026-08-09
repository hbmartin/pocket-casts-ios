import AVFoundation
import Foundation
@testable import podcasts
import XCTest

final class AudioTranscodeHelperTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioTranscodeHelperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        try await super.tearDown()
    }

    func testCancelledPassthroughPreservesCancellation() async throws {
        let source = root.appendingPathComponent("source.m4a")
        try Data("small passthrough".utf8).write(to: source)
        let gate = AudioTranscodeCancellationGate()
        let task = Task {
            await gate.wait()
            return try await AudioTranscodeHelper().transcodeForUpload(sourceURL: source)
        }

        await gate.waitUntilEntered()
        task.cancel()
        await gate.open()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "unexpected error: \(error)")
        }
    }

    func testCancelledEncodePreservesCancellationAndLeavesNoOutput() async throws {
        let source = try makeChunk(seconds: 0.5)
        let output = root.appendingPathComponent("output.m4a")
        let gate = AudioTranscodeCancellationGate()
        let task = Task {
            await gate.wait()
            try await AudioTranscodeHelper.encodeToMonoAAC(
                asset: AVURLAsset(url: source),
                outputURL: output,
                bitRate: 48_000
            )
        }

        await gate.waitUntilEntered()
        task.cancel()
        await gate.open()

        do {
            try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "unexpected error: \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    private func makeChunk(seconds: Double) throws -> URL {
        let url = root.appendingPathComponent("source.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        try file.write(from: buffer)
        return url
    }
}

private actor AudioTranscodeCancellationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var isWaiting = false

    func wait() async {
        await withCheckedContinuation {
            continuation = $0
            isWaiting = true
            enteredContinuation?.resume()
            enteredContinuation = nil
        }
    }

    func waitUntilEntered() async {
        guard !isWaiting else { return }
        await withCheckedContinuation { enteredContinuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
        isWaiting = false
    }
}
