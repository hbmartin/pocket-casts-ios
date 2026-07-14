import AVFoundation
import Foundation
import PocketCastsUtils
import Synchronization

/// Receives timed metadata AVPlayer pushes mid-stream (`AVPlayerItemMetadataOutput`)
/// and forwards the chapter-relevant fields — title and artwork — to the chapter
/// manager, stamped with the group's position on the item timeline.
///
/// Groups are queued into a single serial consumer per playback session so the
/// async `AVMetadataItem` value loads complete strictly in arrival order —
/// with one untracked task per group, a slow artwork load lets a later group's
/// chapter land first and `ChapterManager.appendStreamedChapter` silently drops
/// the earlier one. Each session is scoped to an episode UUID: every forwarded
/// group carries it, so a load that outlives its player item can't mutate the
/// next episode's chapters, and `endSession()` cancels the consumer outright.
nonisolated final class StreamedChapterMetadataHandler: NSObject, AVPlayerItemMetadataOutputPushDelegate, Sendable {
    /// A metadata group queued for sequential processing, stamped with its
    /// position on the item timeline. The non-Sendable `AVMetadataItem`s are
    /// boxed: they are handed over wholesale at enqueue time and read once by
    /// the single consumer.
    struct QueuedGroup: Sendable {
        let time: TimeInterval
        var items: [AVMetadataItem] { boxedItems.value }

        private let boxedItems: UncheckedSendable<[AVMetadataItem]>

        init(time: TimeInterval, items: [AVMetadataItem]) {
            self.time = time
            boxedItems = UncheckedSendable(items)
        }
    }

    /// Resolves a queued group's async metadata values. Injectable so tests can
    /// control completion timing without AVFoundation loading semantics.
    typealias GroupLoader = @Sendable (QueuedGroup) async -> (title: String?, artworkData: Data?)

    /// Receives the loaded fields, in arrival order, tagged with the session's
    /// episode. Injectable so tests can observe ordering and scoping.
    typealias MetadataSink = @MainActor @Sendable (_ title: String?, _ artworkData: Data?, _ time: TimeInterval, _ episodeUuid: String) -> Void

    private struct Session {
        var continuation: AsyncStream<QueuedGroup>.Continuation?
        var consumer: Task<Void, Never>?
    }

    private let session = Mutex(Session())
    private let loadGroup: GroupLoader
    private let sink: MetadataSink

    init(loadGroup: @escaping GroupLoader = StreamedChapterMetadataHandler.loadValues,
         sink: @escaping MetadataSink = { title, artworkData, time, episodeUuid in
             PlaybackManager.shared.ingestStreamedChapterMetadata(title: title, artworkData: artworkData, at: time, episodeUuid: episodeUuid)
         }) {
        self.loadGroup = loadGroup
        self.sink = sink
    }

    /// Starts a fresh serial consumer scoped to `episodeUuid`, replacing (and
    /// cancelling) any previous session's consumer. Call when attaching the
    /// metadata output for a newly loaded episode.
    func startSession(episodeUuid: String) {
        let (stream, continuation) = AsyncStream.makeStream(of: QueuedGroup.self)
        let loadGroup = loadGroup
        let sink = sink
        let consumer = Task {
            for await group in stream {
                guard !Task.isCancelled else { break }
                let values = await loadGroup(group)
                guard !Task.isCancelled, values.title != nil || values.artworkData != nil else { continue }
                await sink(values.title, values.artworkData, group.time, episodeUuid)
            }
        }
        replaceSession(Session(continuation: continuation, consumer: consumer))
    }

    /// Tears down the current session: queued groups and in-flight loads are
    /// dropped instead of being applied to whatever plays next.
    func endSession() {
        replaceSession(Session())
    }

    private func replaceSession(_ new: Session) {
        let old = session.withLock { current in
            let old = current
            current = new
            return old
        }
        old.continuation?.finish()
        old.consumer?.cancel()
    }

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
            enqueue(QueuedGroup(time: time, items: relevantItems))
        }
    }

    /// Delegate-callback tail, split out so tests can drive arrival order
    /// directly. Groups yielded outside a session are dropped.
    func enqueue(_ group: QueuedGroup) {
        session.withLock { $0.continuation }?.yield(group)
    }

    /// AVMetadataItem values load asynchronously; awaited from inside the
    /// serial consumer so groups resolve in arrival order. Internal (not
    /// private) because it is the `init` default for `loadGroup`.
    static let loadValues: GroupLoader = { group in
        var title: String?
        var artworkData: Data?
        for item in group.items {
            switch item.commonKey {
            case .commonKeyTitle?:
                title = (try? await item.load(.stringValue)) ?? title
            case .commonKeyArtwork?:
                artworkData = (try? await item.load(.dataValue)) ?? artworkData
            default:
                break
            }
        }
        return (title, artworkData)
    }
}
