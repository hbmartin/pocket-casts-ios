import XCTest
@testable import podcasts
import AVFoundation
import Accelerate

final class AudioFeatureExtractorTests: XCTestCase {
    private let sampleRate = 44100.0

    // MARK: - Fixtures

    private func makeAudioBuffer(samples: [Float32]) -> AudioBuffer {
        var audioBuffer = AudioBuffer()
        audioBuffer.mNumberChannels = 1
        audioBuffer.mDataByteSize = UInt32(samples.count * MemoryLayout<Float32>.size)
        audioBuffer.mData = UnsafeMutableRawPointer.allocate(byteCount: Int(audioBuffer.mDataByteSize), alignment: MemoryLayout<Float32>.alignment)
        audioBuffer.mData?.copyMemory(from: samples, byteCount: Int(audioBuffer.mDataByteSize))
        return audioBuffer
    }

    private func cleanUp(_ buffer: inout AudioBuffer) {
        buffer.mData?.deallocate()
        buffer.mData = nil
    }

    private func sine(frequency: Double, count: Int, amplitude: Double = 0.5) -> [Float32] {
        (0 ..< count).map { Float32(amplitude * sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    private func whiteNoise(count: Int, amplitude: Float32 = 0.5) -> [Float32] {
        var generator = SystemRandomNumberGenerator()
        return (0 ..< count).map { _ in Float32.random(in: -amplitude ... amplitude, using: &generator) }
    }

    private func makePCMBuffer(samples: [Float32], channels: AVAudioChannelCount = 1) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for channel in 0 ..< Int(channels) {
            buffer.floatChannelData![channel].update(from: samples, count: samples.count)
        }
        return buffer
    }

    // MARK: - Zero-crossing rate

    func testZeroCrossingRateOfSine() {
        // a sine crosses zero twice per cycle: ZCR ≈ 2f/sr
        var buffer = makeAudioBuffer(samples: sine(frequency: 1000, count: 1152))
        defer { cleanUp(&buffer) }

        XCTAssertEqual(Double(AudioUtils.calculateZeroCrossingRate(buffer)), 2 * 1000 / sampleRate, accuracy: 0.005)
    }

    func testZeroCrossingRateOfNoiseIsHigh() {
        var buffer = makeAudioBuffer(samples: whiteNoise(count: 1152))
        defer { cleanUp(&buffer) }

        XCTAssertGreaterThan(AudioUtils.calculateZeroCrossingRate(buffer), 0.3)
    }

    func testZeroCrossingRateOfSilenceIsZero() {
        var buffer = makeAudioBuffer(samples: [Float32](repeating: 0, count: 1152))
        defer { cleanUp(&buffer) }

        XCTAssertEqual(AudioUtils.calculateZeroCrossingRate(buffer), 0)
    }

    // MARK: - Spectral flatness

    func testSpectralFlatnessSeparatesToneFromNoise() {
        let box = SpectralFlatnessBox()

        var toneBuffer = makeAudioBuffer(samples: sine(frequency: 1000, count: 1152))
        defer { cleanUp(&toneBuffer) }
        XCTAssertLessThan(box.spectralFlatness(of: toneBuffer), 0.1, "a pure tone is maximally peaky")

        var noiseBuffer = makeAudioBuffer(samples: whiteNoise(count: 1152))
        defer { cleanUp(&noiseBuffer) }
        XCTAssertGreaterThan(box.spectralFlatness(of: noiseBuffer), 0.4, "white noise is spectrally flat")
    }

    func testSpectralFlatnessOfSilenceIsSafe() {
        let box = SpectralFlatnessBox()
        var buffer = makeAudioBuffer(samples: [Float32](repeating: 0, count: 1152))
        defer { cleanUp(&buffer) }

        let flatness = box.spectralFlatness(of: buffer)
        XCTAssertTrue(flatness >= 0 && flatness <= 1)
    }

    // MARK: - Crossfade splice

    func testCrossfadeSpliceHasNoDip() {
        // two DC-1.0 buffers: an equal-power crossfade keeps the overlap near
        // unity (cos+sin ≥ 1 across the quarter circle), unlike the old
        // fade-out-then-fade-in which dipped to zero
        let outgoing = makePCMBuffer(samples: [Float32](repeating: 1, count: 1152))
        let incoming = makePCMBuffer(samples: [Float32](repeating: 1, count: 1152))
        let overlap = 441

        AudioUtils.crossfadeSplice(outgoing: outgoing, incoming: incoming, overlapFrames: overlap)

        let data = outgoing.floatChannelData![0]
        for index in (1152 - overlap) ..< 1152 {
            XCTAssertGreaterThan(data[index], 0.99, "sample \(index) dipped during the crossfade")
            XCTAssertLessThan(data[index], 1.5)
        }

        AudioUtils.trimLeadingFrames(incoming, frames: overlap)
        XCTAssertEqual(incoming.frameLength, AVAudioFrameCount(1152 - overlap))
    }

    func testTrimLeadingFramesShiftsOverlappingChannelData() {
        let firstChannel = (0 ..< 100).map(Float32.init)
        let secondChannel = firstChannel.map { $0 + 100 }
        let buffer = makePCMBuffer(samples: firstChannel, channels: 2)
        buffer.floatChannelData![1].update(from: secondChannel, count: secondChannel.count)

        AudioUtils.trimLeadingFrames(buffer, frames: 40)

        XCTAssertEqual(buffer.frameLength, 60)
        XCTAssertEqual(
            Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 60)),
            Array(firstChannel.dropFirst(40))
        )
        XCTAssertEqual(
            Array(UnsafeBufferPointer(start: buffer.floatChannelData![1], count: 60)),
            Array(secondChannel.dropFirst(40))
        )
    }

    func testTrimLeadingFramesEmptiesBufferWhenAllFramesAreRemoved() {
        let buffer = makePCMBuffer(samples: (0 ..< 100).map(Float32.init))

        AudioUtils.trimLeadingFrames(buffer, frames: 100)

        XCTAssertEqual(buffer.frameLength, 0)
    }

    func testTrimLeadingFramesEmptiesBufferWhenMoreFramesThanAvailableAreRemoved() {
        let buffer = makePCMBuffer(samples: (0 ..< 100).map(Float32.init))

        AudioUtils.trimLeadingFrames(buffer, frames: 101)

        XCTAssertEqual(buffer.frameLength, 0)
    }

    func testTruncateClampsFrameLength() {
        let buffer = makePCMBuffer(samples: (0 ..< 100).map(Float32.init))
        AudioUtils.truncate(buffer, toFrames: 25)
        XCTAssertEqual(buffer.frameLength, 25)

        // no-ops when the requested length is not smaller
        AudioUtils.truncate(buffer, toFrames: 100)
        XCTAssertEqual(buffer.frameLength, 25)
    }
}
