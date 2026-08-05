import Foundation
import PocketCastsDataModel
import PocketCastsFileSync
import PocketCastsUtils
import UIKit

/// App-side driver for the uploads folder.
///
/// It configures the module once at launch, then runs a folder scan on app
/// activation and background refresh so files dropped into the folder from
/// other devices appear in the Files tab.
@MainActor
final class FileSyncCoordinator {
    private var isSetup = false

    func setup() {
        guard !isSetup else { return }
        isSetup = true

        // One-shot cleanup of keys owned by the removed sync engine.
        for deadKey in ["FileSync.deviceId", "FileSync.mirrorEnabled", "FileSync.mirrorWifiOnly",
                        "FileSync.mirrorMaxBytes", "FileSyncBannerDismissed"] {
            UserDefaults.standard.removeObject(forKey: deadKey)
        }

        Task {
            await FileSyncManager.shared.configure(
                isSupportedFile: { FileTypeUtil.isSupportedUserFileType(fileName: $0) },
                localPathResolver: { episode in
                    episode.pathToDownloadedFile(pathFinder: DownloadManager.shared)
                },
                onUploadsChanged: {
                    NotificationCenter.postOnMainThread(FileSyncUploadsChanged())
                }
            )
            await FileSyncManager.shared.restoreIfEnabled()
            await FileSyncManager.shared.enableICloudIfUnconfigured()
            await FileSyncManager.shared.syncNow()
        }
    }

    func handleAppBecameActive() {
        Task { await FileSyncManager.shared.syncNow() }
    }

    func performBackgroundSync() async {
        await FileSyncManager.shared.syncNow()
    }
}
