import Foundation
import AVFoundation
import UIKit
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

/// MediaExporterItemConfiguration global configuration.
// The mutable statics are test knobs: production only reads them; tests set and restore them.
enum MediaExporterItemConfiguration {
    // nonisolated(unsafe): / How much data is allowed to be read in memory at a time.
    nonisolated(unsafe) public static var readDataLimit: Int = 20.MB

    // nonisolated(unsafe): / Flag for deciding whether an error should be thrown when URLResponse's expectedContentLength is not equal with the downloaded media file bytes count. Defaults to `false`.
    nonisolated(unsafe) public static var shouldVerifyDownloadedFileSize: Bool = false

    /// If set greater than 0, the set value will be compared with the downloaded media size. If the size of the downloaded media is lower, an error will be thrown. Useful when `expectedContentLength` is unavailable.
    // nonisolated(unsafe): / Default value is `DownloadManager.badEpisodeSize` (10KB).
    nonisolated(unsafe) public static var minimumExpectedFileSize: Int = DownloadManager.badEpisodeSize
}

nonisolated fileprivate extension Int {
    var KB: Int { return self * 1024 }
    var MB: Int { return self * 1024 * 1024 }
}

/// Responsible for downloading media data and providing the requested data parts.
/// `URLSessionDelegate` requires `Sendable`; instances are handed to URLSession and
/// AVAssetResourceLoader queues by design, with mutable state guarded by `lock`.
/// @unchecked Sendable: mutable state is guarded by `lock`; Sendable is required by the URLSession delegate contract.
nonisolated final class MediaExporterResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    /// State transitions happen under this non-recursive lock. Calls into AVFoundation,
    /// URLSession, NotificationCenter, and client callbacks always happen after unlocking.
    private let lock = NSLock()

    private let readDataLimit = MediaExporterItemConfiguration.readDataLimit

    private var fileHandle: MediaFileHandle

    private var session: URLSession?
    private var storedResponse: URLResponse?
    private var pendingRequests = Set<AVAssetResourceLoadingRequest>()
    /// Requests currently owned by a delivery loop (`deliverChunks(for:)`). Only the
    /// owning thread may respond to or finish a request while it is a member, which
    /// keeps chunk offsets advancing on exactly one thread per request.
    private var inFlightRequests = Set<AVAssetResourceLoadingRequest>()
    /// Requests detached (e.g. by `invalidateAndCancelSession`) while a delivery loop
    /// owned them. The owner finishes them with the stored error on its next step so
    /// `finishLoading(with:)` never races the owner's `respond(with:)`.
    private var deferredSettlements = [AVAssetResourceLoadingRequest: DeferredSettlement]()
    private var isDownloadComplete = false
    private var terminalStatusReported = false
    private var terminalError: (any Error)?
    private var storedDeleteFileOnRelease = false
    private var storedHasRetriedWithoutUserAgent = false

    var response: URLResponse? {
        get { lock.withLock { storedResponse } }
        set { lock.withLock { storedResponse = newValue } }
    }

    var deleteFileOnRelease: Bool {
        get { lock.withLock { storedDeleteFileOnRelease } }
        set { lock.withLock { storedDeleteFileOnRelease = newValue } }
    }

    var hasRetriedWithoutUserAgent: Bool {
        get { lock.withLock { storedHasRetriedWithoutUserAgent } }
        set { lock.withLock { storedHasRetriedWithoutUserAgent = newValue } }
    }

    private let saveFilePath: String
    private let callback: FileExporterProgressReport?

    // Episode context for cellular tracking
    private let episodeUuid: String?
    private let podcastUuid: String?

    private let callbackQueue = DispatchQueue(label: "com.pocketcasts.MediaExporterResourceLoaderDelegate.callback", qos: .default, attributes: [])

    enum FileExportStatus {
        case downloading
        case completed
        case failed(Error)
    }

    typealias FileExporterProgressReport = (_ status: FileExportStatus, _ contentType: String?, _ downloaded: Int64, _ total: Int64) -> ()

    /// A pending request an exclusive delivery loop has claimed, with the response
    /// snapshot used to fill its content information request.
    private struct ClaimedRequest {
        let request: AVAssetResourceLoadingRequest
        let response: URLResponse
    }

    /// The settlement recorded for a request detached while a delivery loop owned it.
    private struct DeferredSettlement {
        let error: (any Error)?
    }

    /// One step of the chunked delivery loop, computed under `lock` and performed
    /// outside it. Every case except `.respond` releases the claim under the same
    /// lock hold that computed it.
    private enum DeliveryStep {
        /// Respond with one bounded chunk; the claim is retained and the loop continues.
        case respond(Data)
        /// The request is fulfilled; finish it successfully.
        case finish
        /// Finish the request with the given error (`nil` finishes without one).
        case finishWith((any Error)?)
        /// Delivery failed; perform the failure effect (it includes this request).
        case fail(FailureEffect)
        /// The request was cancelled while in flight; stop without touching it.
        case release
        /// No cached bytes are available yet; the request stays pending for the next trigger.
        case wait
    }

    /// Outcome of computing the next chunk for a data request under `lock`.
    private enum ChunkOutcome {
        case chunk(Data)
        case fulfilled
        case waiting
    }

    private struct FailureEffect {
        let session: URLSession?
        let requests: Set<AVAssetResourceLoadingRequest>
        let error: any Error
        let contentType: String?
        let notify: Bool
        let reportsTerminalStatus: Bool
    }

    // MARK: Init
    init(saveFilePath: String, episodeUuid: String? = nil, podcastUuid: String? = nil, callback: FileExporterProgressReport?) {
        self.saveFilePath = saveFilePath
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.callback = callback
        self.fileHandle = MediaFileHandle(filePath: saveFilePath)
        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(handleAppWillTerminate), name: UIApplication.willTerminateNotification, object: nil)
    }

    deinit {
        FileLog.shared.addMessage("MediaExporterResourceLoaderDelegate: Releasing loader for \(saveFilePath)")
        session?.invalidateAndCancel()
        if storedDeleteFileOnRelease {
            fileHandle.deleteFile()
        }
    }

    static let schemePrefix = "custom-"

    static func makeCustomURL(_ original: URL) -> URL? {
        return URL(string: "\(Self.schemePrefix)\(original.absoluteString)")
    }

    static func resolveOriginalURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = components.scheme?.replacingOccurrences(of: Self.schemePrefix, with: "")
        return components.url
    }

    func debugLogRequestInfo(_ loadingRequest: AVAssetResourceLoadingRequest, state: String) {
        #if DEBUG
        if let dataRequest = loadingRequest.dataRequest {
            FileLog.shared.addMessage("MediaExporterResourceLoaderDelegate: \(state) Request \(dataRequest.currentOffset) - \(dataRequest.requestedOffset + Int64(dataRequest.requestedLength))")
        }
        #endif
    }
    // MARK: AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url,
              let originalURL = Self.resolveOriginalURL(from: url)
        else {
            return false
        }

        let state = lock.withLock { () -> (shouldStart: Bool, terminalError: (any Error)?) in
            if let terminalError {
                return (false, terminalError)
            }
            pendingRequests.insert(loadingRequest)
            return (session == nil && !isDownloadComplete && !terminalStatusReported, nil)
        }
        debugLogRequestInfo(loadingRequest, state: "Add")
        if let terminalError = state.terminalError {
            loadingRequest.finishLoading(with: terminalError)
            return true
        }
        if state.shouldStart {
            // If we're playing from a URL, start downloading on the first request.
            startDataRequest(with: originalURL)
        }
        processPendingRequests()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        debugLogRequestInfo(loadingRequest, state: "Cancel")
        lock.withLock {
            pendingRequests.remove(loadingRequest)
            deferredSettlements.removeValue(forKey: loadingRequest)
        }
    }

    // MARK: URLSessionDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let transition = lock.withLock { () -> (claims: [ClaimedRequest], failure: FailureEffect?, progress: (String?, Int64)?) in
            guard !terminalStatusReported else { return ([], nil, nil) }
            do {
                try fileHandle.append(data: data)
                return (claimDeliverableRequestsLocked(), nil, (storedResponse?.mimeType, Int64(fileHandle.safeFileSize)))
            } catch {
                FileLog.shared.addMessage("MediaExporterResourceLoaderDelegate: failed to write data to file: \(error)")
                return ([], transitionToFailureLocked(error: error, notify: true), nil)
            }
        }
        transition.claims.forEach { deliverChunks(for: $0) }
        if let failure = transition.failure {
            performFailureEffect(failure)
        } else if let progress = transition.progress {
            let total = dataTask.countOfBytesExpectedToReceive
            callbackQueue.async { [weak self] in
                self?.callback?(.downloading, progress.0, progress.1, total)
            }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Claiming cannot throw, so this path has no failure branch: read errors
        // surface inside the per-request delivery loops instead.
        let claims = lock.withLock { () -> [ClaimedRequest] in
            guard !terminalStatusReported else { return [] }
            storedResponse = response
            return claimDeliverableRequestsLocked()
        }
        claims.forEach { deliverChunks(for: $0) }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            downloadFailed(with: error)
            return
        }

        let error = verifyResponse()

        guard error == nil else {
            if shouldRetryWithoutUserAgent() {
                retryWithoutUserAgent(originalURL: task.originalRequest?.url)
                return
            }

            downloadFailed(with: error!)
            return
        }

        downloadComplete()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let bytesReceived = task.countOfBytesReceived
        let connectionType = NetworkDataUsageManager.connectionType(from: metrics)

        guard bytesReceived > 0 else { return }

        DataManager.sharedManager.networkDataUsageManager.add(
            episodeUuid: episodeUuid,
            podcastUuid: podcastUuid,
            bytesStreamed: bytesReceived,
            operationType: .stream,
            connectionType: connectionType,
            sessionType: .foreground
        )
    }

    // MARK: Internal methods

    func startDataRequest(with url: URL) {
        startDataRequest(with: url, retryWithoutUserAgent: false)
    }

    @objc func startDataRequest(with url: URL, retryWithoutUserAgent: Bool) {
        FileLog.shared.addMessage("MediaExporterResourceLoaderDelegate: Start data request for \(url)")

        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.networkServiceType = .avStreaming
        configuration.allowsCellularAccess = true
        configuration.timeoutIntervalForRequest = 60 // seconds
        configuration.timeoutIntervalForResource = 3600 * 2 // seconds
        configuration.waitsForConnectivity = false
        configuration.multipathServiceType = .handover // allows switching between celular/wifi

        var urlRequest = URLRequest(url: url)
        if !retryWithoutUserAgent {
            urlRequest.setValue(ServerConstants.Values.appUserAgent, forHTTPHeaderField: ServerConstants.HttpHeaders.userAgent)
        }

        let candidateSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = candidateSession.dataTask(with: urlRequest)
        task.priority = URLSessionTask.highPriority
        let installation = lock.withLock { () -> (installed: Bool, replaced: URLSession?) in
            guard !terminalStatusReported else { return (false, nil) }
            if !retryWithoutUserAgent, session != nil {
                return (false, nil)
            }
            let replacedSession = retryWithoutUserAgent ? session : nil
            session = candidateSession
            if retryWithoutUserAgent {
                storedHasRetriedWithoutUserAgent = true
            }
            return (true, replacedSession)
        }
        installation.replaced?.invalidateAndCancel()
        if installation.installed {
            if retryWithoutUserAgent {
                FileLog.shared.addMessage("MediaExporterResourceLoaderDelegate: Starting request without User-Agent header")
            }
            task.resume()
        } else {
            candidateSession.invalidateAndCancel()
        }
    }

    func invalidateAndCancelSession(shouldResetData: Bool = true, error: Error? = nil) {
        let detached = lock.withLock { () -> (URLSession?, Set<AVAssetResourceLoadingRequest>) in
            let detachedSession = session
            session = nil
            let detachedRequests: Set<AVAssetResourceLoadingRequest>
            if shouldResetData {
                // Requests owned by a delivery loop must be finished by their owner so
                // finishLoading(with:) cannot race the owner's respond(with:).
                for request in pendingRequests.intersection(inFlightRequests) {
                    deferredSettlements[request] = DeferredSettlement(error: error)
                }
                detachedRequests = pendingRequests.subtracting(inFlightRequests)
                pendingRequests.removeAll()
            } else {
                detachedRequests = []
            }

            // We need to only remove the file if it hasn't been fully downloaded.
            if !isDownloadComplete {
                fileHandle.deleteFile()
            }
            return (detachedSession, detachedRequests)
        }

        detached.0?.invalidateAndCancel()
        detached.1.forEach { $0.finishLoading(with: error) }
    }

    // MARK: Private methods

    private func processPendingRequests() {
        let claims = lock.withLock { claimDeliverableRequestsLocked() }
        claims.forEach { deliverChunks(for: $0) }
    }

    /// Claims every pending request no delivery loop currently owns. Caller must hold `lock`.
    private func claimDeliverableRequestsLocked() -> [ClaimedRequest] {
        guard let response = storedResponse, terminalError == nil else { return [] }
        let claimable = pendingRequests.subtracting(inFlightRequests)
        inFlightRequests.formUnion(claimable)
        return claimable.map { ClaimedRequest(request: $0, response: response) }
    }

    /// Drives the delivery loop for one claimed request. The claim guarantees this
    /// thread is the only one responding to or finishing the request, so the
    /// request's `currentOffset` advances strictly between locked steps and no two
    /// passes can compute overlapping chunk ranges. AVFoundation calls happen with
    /// the lock released.
    private func deliverChunks(for claim: ClaimedRequest) {
        if let contentInformationRequest = claim.request.contentInformationRequest {
            contentInformationRequest.contentType = claim.response.mimeType
            contentInformationRequest.contentLength = claim.response.expectedContentLength
            contentInformationRequest.isByteRangeAccessSupported = true
            FileLog.shared.addMessage(
                "MediaExporterResourceLoaderDelegate: Content Information Request filled: \(contentInformationRequest.contentLength)"
            )
        }
        while true {
            let step = lock.withLock { deliveryStepLocked(for: claim.request) }
            switch step {
            case .respond(let data):
                claim.request.dataRequest?.respond(with: data)
            case .finish:
                debugLogRequestInfo(claim.request, state: "Finish")
                claim.request.finishLoading()
                return
            case .finishWith(let error):
                claim.request.finishLoading(with: error)
                return
            case .fail(let failure):
                performFailureEffect(failure)
                return
            case .release:
                return
            case .wait:
                debugLogRequestInfo(claim.request, state: "Partial")
                return
            }
        }
    }

    /// Computes the next action for a claimed request. Caller must hold `lock`.
    /// Every case except `.respond` removes the claim before the lock is dropped,
    /// so ownership state always matches the returned step.
    private func deliveryStepLocked(for request: AVAssetResourceLoadingRequest) -> DeliveryStep {
        if let settlement = deferredSettlements.removeValue(forKey: request) {
            inFlightRequests.remove(request)
            return .finishWith(settlement.error)
        }
        if let terminalError {
            inFlightRequests.remove(request)
            pendingRequests.remove(request)
            return .finishWith(terminalError)
        }
        guard pendingRequests.contains(request) else {
            // Cancelled via resourceLoader(_:didCancel:) while in flight.
            inFlightRequests.remove(request)
            return .release
        }
        guard let dataRequest = request.dataRequest else {
            inFlightRequests.remove(request)
            pendingRequests.remove(request)
            return .finish
        }
        do {
            switch try nextChunkLocked(for: dataRequest) {
            case .chunk(let data):
                return .respond(data)
            case .fulfilled:
                inFlightRequests.remove(request)
                pendingRequests.remove(request)
                return .finish
            case .waiting:
                inFlightRequests.remove(request)
                return .wait
            }
        } catch {
            inFlightRequests.remove(request)
            pendingRequests.remove(request)
            // The owner settles its own request, so fold it into the failure effect.
            // When the export already settled terminally, only this request is
            // finished and no terminal status is reported again.
            let transition = transitionToFailureLocked(error: error, notify: true)
            return .fail(FailureEffect(
                session: transition?.session,
                requests: (transition?.requests ?? []).union([request]),
                error: error,
                contentType: transition?.contentType ?? storedResponse?.mimeType,
                notify: true,
                reportsTerminalStatus: transition != nil
            ))
        }
    }

    /// Reads at most one `readDataLimit`-bounded chunk so peak memory and lock hold
    /// time stay bounded; the delivery loop responds outside the lock and re-enters
    /// for the next chunk. Caller must hold `lock`.
    private func nextChunkLocked(for dataRequest: AVAssetResourceLoadingDataRequest) throws -> ChunkOutcome {
        let requestedOffset = Int(dataRequest.requestedOffset)
        let requestedLength = dataRequest.requestedLength
        let currentOffset = Int(dataRequest.currentOffset)
        if currentOffset >= requestedOffset + requestedLength {
            return .fulfilled
        }
        let bytesCached = try fileHandle.fileSize()
        if isDownloadComplete, currentOffset == bytesCached {
            return .fulfilled
        }

        try validateCurrentOffsetLocked(currentOffset, bytesCached: bytesCached)

        guard let range = Self.nextChunkRange(
            currentOffset: currentOffset,
            requestedOffset: requestedOffset,
            requestedLength: requestedLength,
            bytesCached: bytesCached,
            readDataLimit: readDataLimit
        ) else {
            return .waiting
        }
        guard let data = try fileHandle.readData(withOffset: range.lowerBound, forLength: range.count),
              !data.isEmpty
        else {
            throw MediaFileHandleError.readAfterEndOfFile
        }
        return .chunk(data)
    }

    /// Pure bookkeeping for the delivery loop: the next byte range to read for a
    /// request whose delivery has advanced to `currentOffset`. Returns `nil` when
    /// the request is fulfilled or no cached byte is available yet, and never spans
    /// more than `readDataLimit` bytes. Internal so tests can pin the chunk math.
    static func nextChunkRange(currentOffset: Int, requestedOffset: Int, requestedLength: Int, bytesCached: Int, readDataLimit: Int) -> Range<Int>? {
        let deliverableEnd = min(requestedOffset + requestedLength, bytesCached)
        guard currentOffset < deliverableEnd else { return nil }
        let length = min(deliverableEnd - currentOffset, readDataLimit)
        guard length > 0 else { return nil }
        return currentOffset ..< currentOffset + length
    }

    /// Validates a read position against locked completion/file state.
    private func validateCurrentOffsetLocked(_ currentOffset: Int, bytesCached: Int) throws {
        if isDownloadComplete, currentOffset > bytesCached {
            FileLog.shared.addMessage("MediaExporterResourceLoaderDelegate: try to read a position after the end of a file")
            throw MediaFileHandleError.readAfterEndOfFile
        }
    }

    func releaseIfDownloadComplete() {
        let detachedSession = lock.withLock { () -> URLSession? in
            guard isDownloadComplete else { return nil }
            defer { session = nil }
            return session
        }
        detachedSession?.invalidateAndCancel()
    }

    private func downloadComplete() {
        let claims = lock.withLock { () -> [ClaimedRequest]? in
            guard !terminalStatusReported else { return nil }
            isDownloadComplete = true
            return claimDeliverableRequestsLocked()
        }
        guard let claims else { return }
        claims.forEach { deliverChunks(for: $0) }
        let completion = lock.withLock { () -> (contentType: String?, fileSize: Int, expectedSize: Int64)? in
            guard !terminalStatusReported else {
                // A delivery (or cancel) raced this completion into a terminal failure.
                // That path skipped the file cleanup because `isDownloadComplete` was
                // already set, so clean up here and keep the failure settlement.
                isDownloadComplete = false
                fileHandle.deleteFile()
                return nil
            }
            terminalStatusReported = true
            terminalError = nil
            return (storedResponse?.mimeType, fileHandle.safeFileSize, storedResponse?.expectedContentLength ?? 0)
        }
        guard let completion else { return }
        FileLog.shared.addMessage(
            "MediaExporterResourceLoaderDelegate: Download completed. File Size:\(completion.fileSize) ExpectedSize:\(completion.expectedSize)"
        )
        callbackQueue.async { [weak self] in
            self?.callback?(.completed, completion.contentType, Int64(completion.fileSize), Int64(completion.fileSize))
        }
    }

    func verifyResponse() -> NSError? {
        lock.lock()
        defer { lock.unlock() }
        guard let response = storedResponse as? HTTPURLResponse else { return nil }

        let shouldVerifyDownloadedFileSize = MediaExporterItemConfiguration.shouldVerifyDownloadedFileSize
        let minimumExpectedFileSize = MediaExporterItemConfiguration.minimumExpectedFileSize
        var error: NSError?
        let fileSize = fileHandle.safeFileSize
        if response.statusCode >= 400 {
            error = errorFromStatusCode(response.statusCode)
        } else if shouldVerifyDownloadedFileSize && response.expectedContentLength != -1 && response.expectedContentLength != fileSize {
            error = NSError(domain: NSURLErrorDomain, code: NSURLErrorResourceUnavailable, userInfo: [NSLocalizedDescriptionKey: "Failed downloading asset. Reason: wrong file size, expected: \(response.expectedContentLength), actual: \(fileSize)."])
        } else if minimumExpectedFileSize > 0 && minimumExpectedFileSize > fileSize {
            error = NSError(domain: NSURLErrorDomain, code: NSURLErrorZeroByteResource, userInfo: [NSLocalizedDescriptionKey: "Failed downloading asset. Reason: file size \(fileSize) is smaller than minimumExpectedFileSize"])
        }

        return error
    }

    func errorFromStatusCode(_ statusCode: Int) -> NSError {
        switch statusCode {
        case 401, 403:
            return NSError(domain: NSURLErrorDomain, code: NSURLErrorUserAuthenticationRequired, userInfo: [NSLocalizedDescriptionKey: "Failed stream/downloading asset. Reason: response status code \(statusCode)."])
        case 404, 410:
            return NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist, userInfo: [NSLocalizedDescriptionKey: "Failed stream/downloading asset. Reason: response status code \(statusCode)."])
        case 400, 405, 408, 409, 429, 500..<1000:
            return NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse, userInfo: [NSLocalizedDescriptionKey: "Failed stream/downloading asset. Reason: response status code \(statusCode)."])
        default:
            return NSError(domain: NSURLErrorDomain, code: NSURLErrorResourceUnavailable, userInfo: [NSLocalizedDescriptionKey: "Failed stream/downloading asset. Reason: response status code \(statusCode)."])
        }
    }

    func shouldRetryWithoutUserAgent() -> Bool {
        lock.withLock {
            guard let response = storedResponse as? HTTPURLResponse else { return false }
            // Only retry if we haven't already retried without User-Agent and the response status code is >= 400
            return !storedHasRetriedWithoutUserAgent && (response.statusCode >= 400)
        }
    }

    private func retryWithoutUserAgent(originalURL: URL?) {
        guard let originalURL else {
            FileLog.shared.addMessage("MediaExporterResourceLoaderDelegate: Cannot retry without User-Agent - no original URL")
            return
        }

        FileLog.shared.addMessage("MediaExporterResourceLoaderDelegate: Retrying without User-Agent header for URL: \(originalURL)")

        let detachedSession = lock.withLock { () -> URLSession? in
            fileHandle.close()
            let detached = session
            session = nil
            storedResponse = nil
            if !isDownloadComplete {
                fileHandle.deleteFile()
            }
            fileHandle = MediaFileHandle(filePath: saveFilePath)
            return detached
        }

        detachedSession?.invalidateAndCancel()
        startDataRequest(with: originalURL, retryWithoutUserAgent: true)
    }

    private func downloadFailed(with error: Error, notify: Bool = false) {
        FileLog.shared.addMessage("MediaExporterResourceLoaderDelegate: Download failed with error: \(error)")
        let effect = lock.withLock {
            transitionToFailureLocked(error: error, notify: notify)
        }
        if let effect {
            performFailureEffect(effect)
        }
    }

    /// Cancels the export and settles it as a failure exactly once.
    func cancel(with error: any Error) {
        downloadFailed(with: error)
    }

    /// Detaches failure effects and updates terminal state. Caller must hold `lock`.
    private func transitionToFailureLocked(error: any Error, notify: Bool) -> FailureEffect? {
        guard !terminalStatusReported else { return nil }
        terminalStatusReported = true
        terminalError = error
        let detachedSession = session
        session = nil
        // Requests owned by a delivery loop settle themselves: the owner observes
        // `terminalError` on its next locked step and finishes its own request, so
        // finishing them here cannot race the owner's respond(with:).
        let requests = pendingRequests.subtracting(inFlightRequests)
        pendingRequests.subtract(requests)
        let contentType = storedResponse?.mimeType
        if !isDownloadComplete {
            fileHandle.deleteFile()
        }
        return FailureEffect(
            session: detachedSession,
            requests: requests,
            error: error,
            contentType: contentType,
            notify: notify,
            reportsTerminalStatus: true
        )
    }

    private func performFailureEffect(_ effect: FailureEffect) {
        effect.session?.invalidateAndCancel()
        effect.requests.forEach { $0.finishLoading(with: effect.error) }
        if effect.notify {
            NotificationCenter.default.post(
                name: AVPlayerItem.failedToPlayToEndTimeNotification,
                object: nil,
                userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: effect.error]
            )
        }
        if effect.reportsTerminalStatus {
            let error = PocketCastsUtils.UncheckedSendable(effect.error)
            let contentType = effect.contentType
            callbackQueue.async { [weak self, error] in
                self?.callback?(.failed(error.value), contentType, 0, 0)
            }
        }
    }

    @objc private func handleAppWillTerminate() {
        invalidateAndCancelSession(shouldResetData: false)
    }
}
