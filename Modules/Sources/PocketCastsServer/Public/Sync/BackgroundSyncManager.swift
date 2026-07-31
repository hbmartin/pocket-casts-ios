import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Runs the three reduced background-sync phases through the same serialized
/// App Attest transport as foreground requests. Network send and response
/// processing complete in order: refresh, Up Next, then regular sync.
/// @unchecked Sendable: mutable coordination state is serialized by `syncProcessQueue`.
public final class BackgroundSyncManager: @unchecked Sendable {
    public static let shared = BackgroundSyncManager()

    private var lastBackgroundSyncDate: Date?
    private var activeTask: Task<Void, Never>?
    private let urlConnection: URLConnection

    let syncProcessQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    public init(urlConnection: URLConnection = URLConnection(handler: URLSession.shared)) {
        self.urlConnection = urlConnection
    }

    public func performBackgroundRefresh(subscribedPodcasts: [Podcast]) {
        let podcasts = UncheckedSendable(subscribedPodcasts)
        syncProcessQueue.addOperation { [weak self] in
            guard let self,
                  self.activeTask == nil,
                  DateUtil.hasEnoughTimePassed(since: self.lastBackgroundSyncDate, time: 5.minutes),
                  let token = try? KeychainHelper.string(for: ServerConstants.Values.syncingV2TokenKey),
                  !token.isEmpty,
                  let refreshRequest = MainServerHandler.shared.createRefreshRequest(podcasts: podcasts.value),
                  let upNext = UpNextSyncTask().createUpNextUrlRequest(token: token),
                  let syncRequest = SyncTask().incrementalSyncRequest(token: token)
            else { return }

            self.lastBackgroundSyncDate = Date()
            self.activeTask = Task { [weak self] in
                guard let self else { return }
                await self.runSequentially(
                    refreshRequest: Self.authenticated(refreshRequest, token: token),
                    upNextRequest: Self.authenticated(upNext.urlRequest, token: token),
                    upNextActionTime: upNext.latestActionTime,
                    syncRequest: Self.authenticated(syncRequest, token: token)
                )
                self.syncProcessQueue.addOperation { [weak self] in
                    self?.activeTask = nil
                }
            }
        }
    }

    private func runSequentially(
        refreshRequest: URLRequest,
        upNextRequest: URLRequest,
        upNextActionTime: Int64,
        syncRequest: URLRequest
    ) async {
        if let refresh = await phase(named: "refresh", request: refreshRequest) {
            await onSyncQueue { self.processRefreshResponse(refresh.data) }
        }

        if let upNext = await phase(named: "up-next", request: upNextRequest) {
            await onSyncQueue {
                guard let data = upNext.data else { return }
                UpNextSyncTask().process(serverData: data, latestActionTime: upNextActionTime)
            }
        }

        if let sync = await phase(named: "sync", request: syncRequest) {
            await onSyncQueue {
                let episodes = DataManager.sharedManager.unsyncedEpisodes(limit: ServerConstants.Limits.maxEpisodesToSync)
                _ = SyncTask().processSyncData(sync.data, httpStatus: sync.statusCode, episodesToSync: episodes)
            }
        }

        await onSyncQueue {
            ServerNotificationsHelper.shared.fireSyncCompleted()
        }
    }

    private func phase(named name: String, request: URLRequest) async -> (data: Data?, statusCode: Int)? {
        do {
            let (data, response) = try await urlConnection.send(request: request)
            guard let response, let statusCode = (response as? HTTPURLResponse)?.statusCode else {
                FileLog.shared.addMessage("BackgroundSyncManager \(name) returned no HTTP response")
                return nil
            }
            guard Self.isDownloadComplete(
                receivedBytes: data?.count ?? 0,
                expectedContentLength: response.expectedContentLength
            ) else {
                FileLog.shared.addMessage("BackgroundSyncManager \(name) response was truncated")
                return nil
            }
            return (data, statusCode)
        } catch {
            FileLog.shared.addMessage("BackgroundSyncManager \(name) failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func onSyncQueue(_ operation: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            syncProcessQueue.addOperation {
                operation()
                continuation.resume()
            }
        }
    }

    private func processRefreshResponse(_ data: Data?) {
        guard let data else { return }
        let response = ServerHelper.decodeRefreshResponse(from: data)
        guard response.success(), let result = response.result else {
            FileLog.shared.addMessage("Background refresh server call failed")
            return
        }
        let status = RefreshOperation(result: result, completionHandler: nil).performRefresh()
        if status == .cancelled || status == .failed {
            FileLog.shared.addMessage("Background refresh failed processing data")
        }
    }

    private static func authenticated(_ request: URLRequest, token: String) -> URLRequest {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: ServerConstants.HttpHeaders.authorization)
        return request
    }

    /// `URLResponse.expectedContentLength` uses -1 when no length is known.
    static let unknownContentLength: Int64 = -1

    static func isDownloadComplete(receivedBytes: Int, expectedContentLength: Int64) -> Bool {
        guard expectedContentLength != unknownContentLength else { return true }
        return Int64(receivedBytes) == expectedContentLength
    }
}
