import AVFoundation
import Foundation
import Accelerate
import PocketCastsUtils

nonisolated class AudioUtils {
    private static let bufferLength = UInt32(Constants.Audio.defaultFrameSize)
    private static let bufferByteSize = Float32(MemoryLayout<Float32>.size)

    class func fadeAudio(_ audio: BufferedAudio, fadeOut: Bool, channelCount: UInt32) {
        let bufferList = UnsafeMutableAudioBufferListPointer(audio.audioBuffer.mutableAudioBufferList)
        let length = vDSP_Length(bufferList[0].mDataByteSize) / vDSP_Length(bufferByteSize)
        let data = bufferList[0].mData?.bindMemory(to: Float32.self, capacity: Int(length))

        AudioUtils.performFade(fadeOut, length: length, data: data)

        if channelCount > 1 {
            let extraChannelLength = vDSP_Length(bufferList[1].mDataByteSize) / vDSP_Length(bufferByteSize)
            let extraChannelData = bufferList[1].mData?.bindMemory(to: Float32.self, capacity: Int(extraChannelLength))

            AudioUtils.performFade(fadeOut, length: extraChannelLength, data: extraChannelData)
        }
    }

    class func performFade(_ fadeOut: Bool, length: vDSP_Length, data: UnsafeMutablePointer<Float32>?) {
        guard let data else { return }

        var ramp = [Float32](repeating: 0, count: Int(length))

        if fadeOut {
            vDSP_vgen([1.0], [0.0], &ramp, 1, length)
        } else {
            vDSP_vgen([0.0], [1.0], &ramp, 1, length)
        }

        vDSP_vmul(data, 1, ramp, 1, data, 1, length)
    }


    class func calculateStereoRms(_ leftBuffer: AudioBuffer, rightBuffer: AudioBuffer) -> Float32 {
        let leftRms = calculateRms(leftBuffer)
        let rightRms = calculateRms(rightBuffer)

        return (leftRms + rightRms) / 2
    }

    class func calculateRms(_ audioBuffer: AudioBuffer) -> Float32 {
        let bufferSize = Float32(audioBuffer.mDataByteSize) / bufferByteSize
        guard let buffer = audioBuffer.mData?.bindMemory(to: Float32.self, capacity: Int(bufferSize)) else { return 0 }

        let stride = vDSP_Stride(1)

        let n = vDSP_Length(bufferSize)

        var c = Float32()

        vDSP_rmsqv(buffer,
                   stride,
                   &c,
                   n)

        return c
    }

    /// Fraction of adjacent sample pairs whose sign flips (0…~0.5). High values
    /// on quiet audio indicate fricatives/noise rather than a true gap.
    class func calculateZeroCrossingRate(_ audioBuffer: AudioBuffer) -> Float32 {
        let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float32>.size
        guard count > 1, let data = audioBuffer.mData?.bindMemory(to: Float32.self, capacity: count) else { return 0 }

        var crossings = 0
        var previousPositive = data[0] >= 0
        for index in 1 ..< count {
            let positive = data[index] >= 0
            if positive != previousPositive {
                crossings += 1
                previousPositive = positive
            }
        }

        return Float32(crossings) / Float32(count - 1)
    }

    /// Equal-power crossfade splice: overlaps the last `overlapFrames` of
    /// `outgoing` with the first `overlapFrames` of `incoming` (cos/sin ramps),
    /// writing into `outgoing`. Trim the same leading frames off `incoming`
    /// afterwards with `trimLeadingFrames`.
    class func crossfadeSplice(outgoing: AVAudioPCMBuffer, incoming: AVAudioPCMBuffer, overlapFrames: Int) {
        let frames = min(overlapFrames, Int(outgoing.frameLength), Int(incoming.frameLength))
        guard frames > 1,
              let outData = outgoing.floatChannelData,
              let inData = incoming.floatChannelData else { return }

        var fadeOutRamp = [Float32](repeating: 0, count: frames)
        var fadeInRamp = [Float32](repeating: 0, count: frames)
        for index in 0 ..< frames {
            let theta = Float32(index) / Float32(frames - 1) * (.pi / 2)
            fadeOutRamp[index] = cos(theta)
            fadeInRamp[index] = sin(theta)
        }

        let channels = Int(min(outgoing.format.channelCount, incoming.format.channelCount))
        let outStart = Int(outgoing.frameLength) - frames
        for channel in 0 ..< channels {
            let outSamples = outData[channel] + outStart
            vDSP_vmul(outSamples, 1, fadeOutRamp, 1, outSamples, 1, vDSP_Length(frames))
            var faded = [Float32](repeating: 0, count: frames)
            vDSP_vmul(inData[channel], 1, fadeInRamp, 1, &faded, 1, vDSP_Length(frames))
            vDSP_vadd(outSamples, 1, faded, 1, outSamples, 1, vDSP_Length(frames))
        }
    }

    /// Drops the first `frames` frames of the buffer in place.
    class func trimLeadingFrames(_ buffer: AVAudioPCMBuffer, frames: Int) {
        let currentLength = Int(buffer.frameLength)
        guard frames > 0, frames < currentLength, let data = buffer.floatChannelData else { return }

        let remaining = currentLength - frames
        for channel in 0 ..< Int(buffer.format.channelCount) {
            memmove(
                data[channel],
                data[channel] + frames,
                remaining * MemoryLayout<Float32>.stride
            )
        }
        buffer.frameLength = AVAudioFrameCount(remaining)
    }

    /// Truncates the buffer to at most `frames` frames.
    class func truncate(_ buffer: AVAudioPCMBuffer, toFrames frames: Int) {
        guard frames > 0, frames < Int(buffer.frameLength) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
    }
}

/// Owns the DFT setup, window, and scratch storage for spectral-flatness
/// extraction; create once per reader so the per-buffer path never allocates
/// vDSP setups. Not thread-safe — confined to AudioReadTask's read loop.
nonisolated final class SpectralFlatnessBox {
    static let fftSize = 1024

    private let setup: vDSP_DFT_Setup?
    private var window = [Float32](repeating: 0, count: SpectralFlatnessBox.fftSize)
    private var windowed = [Float32](repeating: 0, count: SpectralFlatnessBox.fftSize)
    private var realIn = [Float32](repeating: 0, count: SpectralFlatnessBox.fftSize / 2)
    private var imagIn = [Float32](repeating: 0, count: SpectralFlatnessBox.fftSize / 2)
    private var realOut = [Float32](repeating: 0, count: SpectralFlatnessBox.fftSize / 2)
    private var imagOut = [Float32](repeating: 0, count: SpectralFlatnessBox.fftSize / 2)
    private var power = [Float32](repeating: 0, count: SpectralFlatnessBox.fftSize / 2)
    private var logPower = [Float32](repeating: 0, count: SpectralFlatnessBox.fftSize / 2)

    init() {
        setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(Self.fftSize), .FORWARD)
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let setup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    /// Spectral flatness (geometric mean / arithmetic mean of the power
    /// spectrum, DC excluded): ~0 for tonal content, ~1 for noise. Analyzes the
    /// first `fftSize` samples (zero-padded when the buffer is shorter).
    func spectralFlatness(of audioBuffer: AudioBuffer) -> Float32 {
        guard let setup else { return 1 }
        let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float32>.size
        guard count > 0, let data = audioBuffer.mData?.bindMemory(to: Float32.self, capacity: count) else { return 1 }

        let analyzed = min(count, Self.fftSize)
        if analyzed < Self.fftSize {
            windowed.withUnsafeMutableBufferPointer { pointer in
                vDSP_vclr(pointer.baseAddress!, 1, vDSP_Length(Self.fftSize))
            }
        }
        vDSP_vmul(data, 1, window, 1, &windowed, 1, vDSP_Length(analyzed))

        // pack even/odd samples for the real-to-complex DFT
        windowed.withUnsafeBufferPointer { pointer in
            pointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.fftSize / 2) { complexPointer in
                realIn.withUnsafeMutableBufferPointer { real in
                    imagIn.withUnsafeMutableBufferPointer { imag in
                        var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imag.baseAddress!)
                        vDSP_ctoz(complexPointer, 2, &split, 1, vDSP_Length(Self.fftSize / 2))
                    }
                }
            }
        }

        vDSP_DFT_Execute(setup, realIn, imagIn, &realOut, &imagOut)

        realOut.withUnsafeMutableBufferPointer { real in
            imagOut.withUnsafeMutableBufferPointer { imag in
                var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imag.baseAddress!)
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(Self.fftSize / 2))
            }
        }

        // skip bin 0 (DC/Nyquist packing) for the flatness statistics
        let bins = vDSP_Length(Self.fftSize / 2 - 1)
        var epsilon = Float32(1e-12)
        power.withUnsafeMutableBufferPointer { pointer in
            var count32 = Int32(bins)
            vDSP_vsadd(pointer.baseAddress! + 1, 1, &epsilon, pointer.baseAddress! + 1, 1, bins)
            vvlogf(&logPower[1], pointer.baseAddress! + 1, &count32)
        }

        var meanLog = Float32(0)
        var meanPower = Float32(0)
        logPower.withUnsafeBufferPointer { pointer in
            vDSP_meanv(pointer.baseAddress! + 1, 1, &meanLog, bins)
        }
        power.withUnsafeBufferPointer { pointer in
            vDSP_meanv(pointer.baseAddress! + 1, 1, &meanPower, bins)
        }

        guard meanPower > 0 else { return 1 }
        let flatness = exp(meanLog) / meanPower
        return min(max(flatness, 0), 1)
    }
}
