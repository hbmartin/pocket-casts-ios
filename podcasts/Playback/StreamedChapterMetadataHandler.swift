import AVFoundation
import Foundation
import PocketCastsUtils

/// Receives timed metadata AVPlayer pushes mid-stream (`AVPlayerItemMetadataOutput`)
/// and forwards the chapter-relevant fields — title and artwork — to the chapter
/// manager, stamped with the group's position on the item timeline.
nonisolated final class StreamedChapterMetadataHandler: NSObject, AVPlayerItemMetadataOutputPushDelegate, Sendable {
    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        for group in groups {
            let time = group.timeRange.start.seconds
            guard time.isFinite, time >= 0 else { continue }

            let relevantItems = group.items.filter {
                $0.commonKey == .commonKeyTitle || $0.commonKey == .commonKeyArtwork
            }
            guard !relevantItems.isEmpty else { continue }

            // AVMetadataItem values load asynchronously; the items cross into the
            // task boxed (they are handed over wholesale and read once).
            let boxedItems = PocketCastsUtils.UncheckedSendable(relevantItems)
            Task {
                var title: String?
                var artworkData: Data?
                for item in boxedItems.value {
                    switch item.commonKey {
                    case .commonKeyTitle?:
                        title = (try? await item.load(.stringValue)) ?? title
                    case .commonKeyArtwork?:
                        artworkData = (try? await item.load(.dataValue)) ?? artworkData
                    default:
                        break
                    }
                }
                guard title != nil || artworkData != nil else { return }

                let groupTitle = title
                let groupArtwork = artworkData
                await MainActor.run {
                    PlaybackManager.shared.ingestStreamedChapterMetadata(title: groupTitle, artworkData: groupArtwork, at: time)
                }
            }
        }
    }
}
