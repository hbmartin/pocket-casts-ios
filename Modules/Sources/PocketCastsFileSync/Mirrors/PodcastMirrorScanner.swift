import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// One reconcile pass over `Podcast Mirrors/`: publishes this device's downloads that
/// aren't mirrored yet, and (optionally) materializes mirrored audio this device is
/// missing. Policy: the mirror area is the *union* of downloads across devices —
/// evicting a local download doesn't remove the mirror; mirrors disappear only when
/// their episode row is deleted (which syncs via the regular record tombstones).
public actor PodcastMirrorScanner {
    private let folder: any SyncFolder
    private let dataManager: DataManager
    private let materializer: PodcastMirrorMaterializer

    public init(folder: any SyncFolder, dataManager: DataManager,
                materializer: PodcastMirrorMaterializer) {
        self.folder = folder
        self.dataManager = dataManager
        self.materializer = materializer
    }

    public struct ScanResult: Sendable {
        public var mirrored = 0
        public var materialized = 0
        public var skippedBySizeCap = 0
    }

    /// - Parameters:
    ///   - materializeIn: whether missing local audio may be pulled from the folder
    ///     this pass (the app gates this on the Wi-Fi-only setting).
    ///   - maxMaterializeBytes: cumulative per-pass budget for pulled audio
    ///     (0 = unlimited).
    @discardableResult
    public func scan(materializeIn: Bool, maxMaterializeBytes: Int64 = 0) async throws -> ScanResult {
        let listing = try await folder.list(FileSyncFormat.podcastMirrorsDirectory)
        let entries = listing.compactMap(PodcastMirrorFormat.entry(from:))
        let mirroredEpisodeUuids = Set(entries.map(\.episodeUuid))

        var result = ScanResult()

        // OUT: every locally downloaded episode that isn't in the mirror area yet.
        let downloaded = dataManager.findEpisodesWhere(
            customWhere: "episodeStatus = \(DownloadStatus.downloaded.rawValue)", arguments: nil)
        for episode in downloaded where !mirroredEpisodeUuids.contains(episode.uuid) {
            do {
                if try await materializer.mirror(episodeUuid: episode.uuid) {
                    result.mirrored += 1
                }
            } catch {
                FileLog.shared.addMessage("FileSync mirrors: failed to mirror \(episode.uuid): \(error)")
            }
        }

        // IN: mirrored audio for episode rows this device knows but hasn't downloaded.
        guard materializeIn else { return result }

        var budgetUsed: Int64 = 0
        for entry in entries {
            guard let episode = dataManager.findEpisode(uuid: entry.episodeUuid),
                  episode.episodeStatus != DownloadStatus.downloaded.rawValue,
                  !episode.archived else { continue }

            if maxMaterializeBytes > 0, budgetUsed + entry.sizeBytes > maxMaterializeBytes {
                result.skippedBySizeCap += 1
                continue
            }

            do {
                try await materializer.materialize(entry: entry)
                budgetUsed += entry.sizeBytes
                result.materialized += 1
            } catch {
                FileLog.shared.addMessage("FileSync mirrors: failed to materialize \(entry.episodeUuid): \(error)")
            }
        }

        return result
    }
}
