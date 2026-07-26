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

    private struct RequestEffect {
        let request: AVAssetResourceLoadingRequest
        let response: URLResponse
        let data: [Data]
        let shouldFinish: Bool
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
        _ = lock.withLock { pendingRequests.remove(loadingRequest) }
    }

    // MARK: URLSessionDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let transition = lock.withLock { () -> (effects: [RequestEffect], failure: FailureEffect?, progress: (String?, Int64)?) in
            guard !terminalStatusReported else { return ([], nil, nil) }
            do {
                try fileHandle.append(data: data)
                let effects = try pendingRequestEffectsLocked()
                return (effects, nil, (storedResponse?.mimeType, Int64(fileHandle.safeFileSize)))
            } catch {
                FileLog.shared.addMessage("MediaExporterResourceLoaderDelegate: failed to write data to file: \(error)")
                return ([], transitionToFailureLocked(error: error, notify: true), nil)
            }
        }
        performRequestEffects(transition.effects)
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
        let transition = lock.withLock { () -> (effects: [RequestEffect], failure: FailureEffect?) in
            guard !terminalStatusReported else { return ([], nil) }
            storedResponse = response
            do {
                return (try pendingRequestEffectsLocked(), nil)
            } catch {
                if let failure = transitionToFailureLocked(error: error, notify: true) {
                    return ([], failure)
                }
                let requests = pendingRequests
                pendingRequests.removeAll()
                return ([], FailureEffect(
                    session: nil,
                    requests: requests,
                    error: error,
                    contentType: storedResponse?.mimeType,
                    notify: true,
                    reportsTerminalStatus: false
                ))
            }
        }
        performRequestEffects(transition.effects)
        if let failure = transition.failure {
            performFailureEffect(failure)
        }
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
        let installed = lock.withLock {
            guard session == nil, !terminalStatusReported else { return false }
            session = candidateSession
            if retryWithoutUserAgent {
                storedHasRetriedWithoutUserAgent = true
            }
            return true
        }
        if installed {
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
                detachedRequests = pendingRequests
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
        let transition = lock.withLock { () -> (effects: [RequestEffect], failure: FailureEffect?) in
            guard terminalError == nil else { return ([], nil) }
            do {
                return (try pendingRequestEffectsLocked(), nil)
            } catch {
                if let failure = transitionToFailureLocked(error: error, notify: true) {
                    return ([], failure)
                }
                let requests = pendingRequests
                pendingRequests.removeAll()
                return ([], FailureEffect(
                    session: nil,
                    requests: requests,
                    error: error,
                    contentType: storedResponse?.mimeType,
                    notify: true,
                    reportsTerminalStatus: false
                ))
            }
        }
        performRequestEffects(transition.effects)
        if let failure = transition.failure {
            performFailureEffect(failure)
        }
    }

    /// Prepares reads and detaches fulfilled requests. Caller must hold `lock`.
    private func pendingRequestEffectsLocked() throws -> [RequestEffect] {
        guard let response = storedResponse else { return [] }

        var effects: [RequestEffect] = []
        var fulfilled = Set<AVAssetResourceLoadingRequest>()
        for request in pendingRequests {
            let prepared: (data: [Data], fulfilled: Bool)
            if let dataRequest = request.dataRequest {
                prepared = try dataForRequestLocked(dataRequest)
            } else {
                prepared = ([], true)
            }
            effects.append(RequestEffect(
                request: request,
                response: response,
                data: prepared.data,
                shouldFinish: prepared.fulfilled
            ))
            if prepared.fulfilled {
                fulfilled.insert(request)
            }
        }
        pendingRequests.subtract(fulfilled)
        return effects
    }

    private func performRequestEffects(_ effects: [RequestEffect]) {
        for effect in effects {
            if let contentInformationRequest = effect.request.contentInformationRequest {
                contentInformationRequest.contentType = effect.response.mimeType
                contentInformationRequest.contentLength = effect.response.expectedContentLength
                contentInformationRequest.isByteRangeAccessSupported = true
                FileLog.shared.addMessage(
                    "MediaExporterResourceLoaderDelegate: Content Information Request filled: \(contentInformationRequest.contentLength)"
                )
            }
            if let dataRequest = effect.request.dataRequest {
                effect.data.forEach { dataRequest.respond(with: $0) }
            }
            if effect.shouldFinish {
                debugLogRequestInfo(effect.request, state: "Finish")
                effect.request.finishLoading()
            } else {
                debugLogRequestInfo(effect.request, state: "Partial")
            }
        }
    }

    /// Reads response chunks while the file handle is protected. Caller must hold `lock`.
    private func dataForRequestLocked(_ dataRequest: AVAssetResourceLoadingDataRequest) throws -> (data: [Data], fulfilled: Bool) {
        let requestedOffset = Int(dataRequest.requestedOffset)
        let requestedLength = dataRequest.requestedLength
        var currentOffset = Int(dataRequest.currentOffset)
        let bytesCached = try fileHandle.fileSize()

        try validateCurrentOffsetLocked(currentOffset, bytesCached: bytesCached)

        guard bytesCached > currentOffset else {
            return ([], false)
        }

        var chunks: [Data] = []
        while currentOffset < min(requestedOffset + requestedLength, bytesCached) {
            let bytesToRespond = min(bytesCached - currentOffset, requestedLength - (currentOffset - requestedOffset), readDataLimit)
            guard bytesToRespond > 0 else { break }
            guard let data = try fileHandle.readData(withOffset: currentOffset, forLength: bytesToRespond) else {
                throw MediaFileHandleError.readAfterEndOfFile
            }
            chunks.append(data)
            currentOffset += data.count
        }

        return (chunks, currentOffset >= requestedLength + requestedOffset)
    }

    /// Validates a read position against locked completion/file state.
    private func validateCurrentOffsetLocked(_ currentOffset: Int, bytesCached: Int) throws {
        if isDownloadComplete, currentOffset >= bytesCached {
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
        let transition = lock.withLock { () -> (effects: [RequestEffect], contentType: String?, fileSize: Int, expectedSize: Int64, failure: FailureEffect?)? in
            guard !terminalStatusReported else { return nil }
            isDownloadComplete = true
            let fileSize = fileHandle.safeFileSize
            let expectedSize = storedResponse?.expectedContentLength ?? 0
            do {
                let effects = try pendingRequestEffectsLocked()
                terminalStatusReported = true
                terminalError = nil
                return (effects, storedResponse?.mimeType, fileSize, expectedSize, nil)
            } catch {
                isDownloadComplete = false
                return ([], storedResponse?.mimeType, fileSize, expectedSize, transitionToFailureLocked(error: error, notify: true))
            }
        }
        guard let transition else { return }
        if let failure = transition.failure {
            performFailureEffect(failure)
            return
        }
        FileLog.shared.addMessage(
            "MediaExporterResourceLoaderDelegate: Download completed. File Size:\(transition.fileSize) ExpectedSize:\(transition.expectedSize)"
        )
        performRequestEffects(transition.effects)
        callbackQueue.async { [weak self] in
            self?.callback?(.completed, transition.contentType, Int64(transition.fileSize), Int64(transition.fileSize))
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
        let requests = pendingRequests
        pendingRequests.removeAll()
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
