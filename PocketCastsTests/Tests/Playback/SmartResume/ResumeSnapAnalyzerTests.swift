import AVFoundation
import XCTest
@testable import podcasts

/// Drives the analyzer's synchronous core against synthesized WAV files:
/// 440Hz tone "speech" with 300ms silences at known times, so the expected
/// snap positions are exact (tolerance covers hop quantization only).
final class ResumeSnapAnalyzerTests: XCTestCase {
    private var workDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()

        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("resume-snap-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workDirectory)
        try await super.tearDown()
    }

    // MARK: - Synthesis

    /// 300ms of silence starting at k+0.7 for every second of the file — the
    /// speech-cadence stand-in. Silences land at 0.7-1.0, 1.7-2.0, 2.7-3.0, …
    private func speechCadence(duration: TimeInterval) -> [(start: TimeInterval, end: TimeInterval)] {
        (0 ..< Int(duration)).map { (start: TimeInterval($0) + 0.7, end: TimeInterval($0) + 1.0) }
    }

    /// Writes a 16-bit WAV of a 440Hz tone at -9dB RMS, silenced inside the
    /// given intervals.
    private func synthesizeFile(named name: String,
                                channels: AVAudioChannelCount = 1,
                                duration: TimeInterval = 12,
                                silences: [(start: TimeInterval, end: TimeInterval)]) throws -> URL {
        let sampleRate = 44100.0
        let url = workDirectory.appendingPathComponent(name)

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: Int(channels),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let channelData = try XCTUnwrap(buffer.floatChannelData)

        for frame in 0 ..< Int(frameCount) {
            let time = Double(frame) / sampleRate
            let silent = silences.contains { time >= $0.start && time < $0.end }
            let sample = silent ? Float(0) : Float(0.5 * sin(2 * .pi * 440 * time))
            for channel in 0 ..< Int(channels) {
                channelData[channel][frame] = sample
            }
        }

        // scoped so the file is flushed and closed before anything reads it
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        }

        return url
    }

    // MARK: - Snapping

    func testSnapsMonoTargetsToKnownSilences() throws {
        let url = try synthesizeFile(named: "mono.wav", silences: speechCadence(duration: 12))

        let snaps = ResumeSnapAnalyzer().snappedTimes(in: url, targets: [5.0, 8.2])

        // nearest gap to 5.0 is the 4.7-5.0 silence: snap = onset 5.0 - 0.15
        XCTAssertEqual(try XCTUnwrap(snaps[5.0]), 4.85, accuracy: 0.06)
        // nearest gap to 8.2 is the 7.7-8.0 silence: snap = onset 8.0 - 0.15
        XCTAssertEqual(try XCTUnwrap(snaps[8.2]), 7.85, accuracy: 0.06)
    }

    func testStereoFileSnapsLikeMono() throws {
        let url = try synthesizeFile(named: "stereo.wav", channels: 2, silences: speechCadence(duration: 12))

        let snaps = ResumeSnapAnalyzer().snappedTimes(in: url, targets: [5.0])

        XCTAssertEqual(try XCTUnwrap(snaps[5.0]), 4.85, accuracy: 0.06)
    }

    func testTargetNearFileStartClampsWindow() throws {
        // the 2.5s look-behind would start at -1.7s; the window clamps to 0 and
        // the 0.7-1.0 silence still snaps
        let url = try synthesizeFile(named: "near-start.wav", silences: speechCadence(duration: 12))

        let snaps = ResumeSnapAnalyzer().snappedTimes(in: url, targets: [0.8])

        XCTAssertEqual(try XCTUnwrap(snaps[0.8]), 0.85, accuracy: 0.06)
    }

    // MARK: - No candidates

    func testContinuousToneProducesNoCandidates() throws {
        let url = try synthesizeFile(named: "tone.wav", silences: [])

        let snaps = ResumeSnapAnalyzer().snappedTimes(in: url, targets: [5.0, 8.2])

        XCTAssertTrue(snaps.isEmpty, "a continuous tone has no dynamic range to snap within")
    }

    func testUnreadableFileProducesNoCandidates() {
        let url = workDirectory.appendingPathComponent("missing.wav")

        let snaps = ResumeSnapAnalyzer().snappedTimes(in: url, targets: [5.0])

        XCTAssertTrue(snaps.isEmpty)
    }

    // MARK: - Async path

    func testSnapCandidatesDeliversCompletionOnMainActor() async throws {
        let url = try synthesizeFile(named: "async.wav", silences: speechCadence(duration: 12))

        // async fulfillment: the completion hops onto the main actor, which a
        // blocking wait(for:) from a @MainActor test can starve.
        let completed = expectation(description: "snap analysis completion")
        ResumeSnapAnalyzer().snapCandidates(for: url, targets: [5.0]) { snaps in
            XCTAssertNotNil(snaps[5.0])
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 10)
    }
}
