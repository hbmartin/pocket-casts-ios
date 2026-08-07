import AVFoundation
import Foundation
import PocketCastsReadAloud
import PocketCastsUtils

/// The assembled episode audio: where it landed and what the episode row
/// records about it.
nonisolated struct AssembledNarration: Sendable {
    let url: URL
    let duration: TimeInterval
    let sizeInBytes: Int64
}

/// Seam so the queue can be tested without synthesizing real audio.
nonisolated protocol NarrationAssembling: Sendable {
    /// - Parameter chunkURLs: rendered chunk files in narration order.
    /// - Parameter pauseBefore: indices into `chunkURLs` that open a block.
    func assemble(chunkURLs: [URL], pauseBefore: Set<Int>, outputURL: URL) async throws -> AssembledNarration
}

/// Joins a narration's rendered chunk files into the single `.m4a` that becomes
/// the episode.
///
/// An `AVMutableComposition` does the joining rather than concatenating PCM by
/// hand: chunks need not share a sample rate or channel layout, the paragraph
/// pauses fall out of an explicit cursor — each chunk is inserted after the
/// pause, leaving an implicit silent gap — rather than being synthesized, and
/// the encode itself is the same reader/writer loop that already ships for
/// upload transcoding.
///
/// Lives app-side rather than in `PocketCastsReadAloud` because that reuse is
/// the point — `AudioTranscodeHelper` is app-side, and duplicating its encode
/// loop into the module to keep the module "pure" would trade real shared code
/// for a tidier dependency diagram.
nonisolated struct NarrationAssembler: NarrationAssembling {
    /// Silence inserted before each chunk that opens a paragraph or heading.
    /// Long enough to read as a deliberate beat, short enough not to feel like a
    /// dropout — matched by ear against audiobook paragraph pacing.
    static let paragraphPause = CMTime(value: 350, timescale: 1000)

    /// Speech at 44.1 kHz mono. Higher does nothing audible for synthesized
    /// narration and only grows a file the user keeps on device.
    private static let bitRate = 64_000

    func assemble(chunkURLs: [URL], pauseBefore: Set<Int>, outputURL: URL) async throws -> AssembledNarration {
        guard !chunkURLs.isEmpty else { throw ReadAloudError.assemblyFailed }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ReadAloudError.assemblyFailed
        }

        // An explicit cursor, not `composition.duration`: a trailing empty range
        // does not extend a composition's duration, so appending at
        // `composition.duration` would place the next chunk straight over the
        // gap and silently drop every pause.
        var cursor = CMTime.zero

        for (index, chunkURL) in chunkURLs.enumerated() {
            // A pause before the first chunk would just be dead air at the head
            // of the episode.
            if index > 0, pauseBefore.contains(index) {
                cursor = cursor + Self.paragraphPause
            }

            let asset = AVURLAsset(url: chunkURL)
            guard let sourceTrack = try? await asset.loadTracks(withMediaType: .audio).first,
                  let duration = try? await asset.load(.duration), duration.isValid, duration.seconds > 0 else {
                // A chunk that renders to nothing means the checkpoint and the
                // workspace disagree; assembling around the gap would ship a
                // silently truncated episode.
                FileLog.shared.addMessage("ReadAloud: chunk \(index) is unreadable or empty")
                throw ReadAloudError.assemblyFailed
            }

            do {
                // Inserting past the current end leaves an implicit silent gap,
                // which is exactly the paragraph pause.
                try track.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: sourceTrack,
                    at: cursor
                )
            } catch {
                throw ReadAloudError.assemblyFailed
            }
            cursor = cursor + duration
        }

        do {
            try await AudioTranscodeHelper.encodeToMonoAAC(
                asset: composition,
                outputURL: outputURL,
                bitRate: Self.bitRate
            )
        } catch {
            throw ReadAloudError.assemblyFailed
        }

        let sizeInBytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? nil
        guard let sizeInBytes, sizeInBytes > 0 else { throw ReadAloudError.assemblyFailed }

        // Measured off the encoded file rather than the composition: the encoder
        // pads and trims at frame boundaries, and the episode row must agree
        // with what the player will actually report.
        let encodedDuration = (try? await AVURLAsset(url: outputURL).load(.duration).seconds) ?? composition.duration.seconds

        return AssembledNarration(url: outputURL, duration: encodedDuration, sizeInBytes: sizeInBytes)
    }
}
