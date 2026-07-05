import Foundation
@preconcurrency import AVFoundation
import PocketCastsUtils

struct MediaExporter {


    typealias ProgressCallback = (Float, Int64) -> ()

    // nonisolated(unsafe): single export flow at a time, driven from the clip-sharing UI
    nonisolated(unsafe) private static var currentExporter: AVAssetExportSession?

    private static func reportProgress(session: AVAssetExportSession, progressCallback: ProgressCallback? = nil) async {
        let size = (try? await session.estimatedOutputFileLengthInBytes) ?? 0
        for await state in session.states(updateInterval: 1) {
            guard !Task.isCancelled else { return }
            if case let .exporting(progress) = state {
                progressCallback?(Float(progress.fractionCompleted), size)
            }
        }
    }

    static func exportMediaItem(_ item: AVPlayerItem, to outputURL: URL, progressCallback: ProgressCallback? = nil) async -> Bool {
        currentExporter?.cancelExport()
        let composition = AVMutableComposition()

        guard let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid)),
            let tracks = try? await item.asset.loadTracks(withMediaType: .audio),
            let sourceAudioTrack = tracks.first,
            let duration = try? await item.asset.load(.duration) else {
            FileLog.shared.addMessage("DownloadManager export session: failed to create audio track")
            return false
        }
        do {
            try compositionAudioTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: duration), of: sourceAudioTrack, at: CMTime.zero)
        } catch {
            FileLog.shared.addMessage("DownloadManager export session: failed to create audio track -> \(error)")
            return false
        }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            FileLog.shared.addMessage("DownloadManager export session: failed to create export session")
            return false
        }
        currentExporter = exporter
        defer {
            if currentExporter === exporter {
                currentExporter = nil
            }
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            do {
                try FileManager.default.removeItem(at: outputURL)
            } catch {
                FileLog.shared.addMessage("DownloadManager export session: failed to delete file with error -> \(error)")
                return false
            }
        }
        do {
            let boxed = PocketCastsUtils.UncheckedSendable((exporter, progressCallback))
            let progressTask = Task {
                let (exporter, progressCallback) = boxed.value
                await reportProgress(session: exporter, progressCallback: progressCallback)
            }
            defer {
                progressTask.cancel()
            }

            try await exporter.export(to: outputURL, as: .m4a)
        } catch is CancellationError {
            FileLog.shared.addMessage("DownloadManager export session: cancelled")
            return false
        } catch {
            FileLog.shared.addMessage("DownloadManager export session: failed with error -> \(error)")
            return false
        }
        FileLog.shared.addMessage("DownloadManager export session: Finished exporting successfully")
        return true
    }
}
