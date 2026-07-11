import Foundation
import PocketCastsFileSync
import PocketCastsUtils

/// Owns a `CustomRefreshControl` and wires it up to local File Sync.
///
/// The owner is responsible for assigning `refreshControl` to a scroll view
/// and customising its appearance.
@MainActor
final class UploadedFilesRefreshController {
    let refreshControl = CustomRefreshControl()

    private let source: AnalyticsSource

    init(source: AnalyticsSource) {
        self.source = source

        refreshControl.perform = { [weak self] _ in
            self?.beginRefreshing()
        }
    }

    private func beginRefreshing() {
        refreshControl.set(text: L10n.refreshControlRefreshingFiles)
        Task { @MainActor [weak self] in
            await FileSyncManager.shared.syncNow()
            self?.finishRefreshing(message: L10n.refreshControlRefreshComplete)
        }
        Analytics.track(.pulledToRefresh, properties: ["source": source])
    }

    private func finishRefreshing(message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.refreshControl.isRefreshing else { return }
            self.refreshControl.set(text: message)
            self.refreshControl.endRefreshing()
        }
    }
}
