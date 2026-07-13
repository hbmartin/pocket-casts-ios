import Foundation
import PocketCastsDataModel
import PocketCastsUtils

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; stored properties are immutable and set in init.
class ApiBaseTask: Operation, @unchecked Sendable {
    private let syncTimeout = 60 as TimeInterval
    private let isoDateFormatter = ISO8601DateFormatter()
    let apiVersion = "2"

    let dataManager: DataManager

    private let urlConnection: URLConnection
    private let tokenHelper: TokenHelper

    // The shared TokenHelper (not a per-task instance) so all tasks funnel token
    // acquisition through one single-flight gate; injectable for tests.
    init(dataManager: DataManager = .sharedManager, urlConnection: URLConnection = URLConnection(handler: URLSession.shared), tokenHelper: TokenHelper = .shared) {
        self.dataManager = dataManager
        self.urlConnection = urlConnection
        self.tokenHelper = tokenHelper
        super.init()
    }

    override func main() {
        autoreleasepool {
            runTaskSynchronously()
        }
    }

    func runTaskSynchronously() {
        if let token = acquiredToken() {
            apiTokenAcquired(token: token)
        } else {
            apiTokenAcquisitionFailed()
        }
    }

    func acquiredToken() -> String? {
        // A stored token past its expiry hint counts as absent, so the task refreshes
        // proactively instead of burning a request to collect the 401.
        if let token = ServerSettings.validSyncingV2Token() {
            return token
        } else if let token = tokenHelper.acquireToken() {
            return token
        }
        return nil
    }

    func postToServer(url: String, token: String, data: Data) -> (Data?, Int) {
        return performPostToServer(url: url, token: token, data: data)
    }

    func performPostToServer(url: String, token: String?, data: Data, retryOnUnauthorized: Bool = true, retryOnTooManyRequests: Bool = true) -> (Data?, Int) {
        let requestUrl = ServerHelper.asUrl(url)
        let method = "POST"
        var request = createRequest(url: requestUrl, method: method, token: token)
        do {
            request.httpBody = data

            let (responseData, response) = try urlConnection.sendSynchronousRequest(with: request)
            guard let httpResponse = response as? HTTPURLResponse else { return (nil, ServerConstants.HttpConstants.serverError) }
            if httpResponse.statusCode == ServerConstants.HttpConstants.unauthorized {
                if retryOnUnauthorized, let newToken = tokenHelper.acquireToken() {
                    FileLog.shared.addMessage("ApiBaseTask: Retrying 401 unauthorized POST to \(url)")
                    return performPostToServer(url: url, token: newToken, data: data, retryOnUnauthorized: false, retryOnTooManyRequests: retryOnTooManyRequests)
                }

                // our token may have expired, remove it so next time a sync happens we'll acquire a new one
                KeychainHelper.removeKey(ServerConstants.Values.syncingV2TokenKey)
                FileLog.shared.addMessage("ApiBaseTask: Removed syncingV2TokenKey due to 401 unauthorized POST from \(url)")
                return (nil, httpResponse.statusCode)
            }

            if httpResponse.statusCode == ServerConstants.HttpConstants.tooManyRequests, retryOnTooManyRequests {
                // Honor Retry-After with a single capped retry, not a loop. Blocking is
                // fine here: this always runs on an Operation's worker thread.
                let delay = httpResponse.tooManyRequestsRetryDelay()
                FileLog.shared.addMessage("ApiBaseTask: 429 rate limited POST to \(url), retrying once in \(delay)s")
                Thread.sleep(forTimeInterval: delay)
                return performPostToServer(url: url, token: token, data: data, retryOnUnauthorized: retryOnUnauthorized, retryOnTooManyRequests: false)
            }

            return (responseData, httpResponse.statusCode)
        } catch {
            logFailure(method: method, url: url, error: error)
        }

        return (nil, ServerConstants.HttpConstants.serverError)
    }

    func getToServer(url: String, token: String, customHeaders: [String: String]? = nil) -> (Data?, HTTPURLResponse?) {
        return performGetToServer(url: url, token: token, customHeaders: customHeaders)
    }

    func performGetToServer(url: String, token: String, retryOnUnauthorized: Bool = true, retryOnTooManyRequests: Bool = true, customHeaders: [String: String]? = nil) -> (Data?, HTTPURLResponse?) {
        let requestUrl = ServerHelper.asUrl(url)
        let method = "GET"
        var request = createRequest(url: requestUrl, method: method, token: token)
        if let customHeaders {
            for header in customHeaders {
                request.setValue(header.value, forHTTPHeaderField: header.key)
            }
        }

        do {
            let (responseData, response) = try urlConnection.sendSynchronousRequest(with: request)
            guard let httpResponse = response as? HTTPURLResponse else { return (nil, nil) }
            if httpResponse.statusCode == ServerConstants.HttpConstants.unauthorized {
                if retryOnUnauthorized, let newToken = tokenHelper.acquireToken() {
                    FileLog.shared.addMessage("ApiBaseTask: Retrying 401 unauthorized GET to \(url)")
                    return performGetToServer(url: url, token: newToken, retryOnUnauthorized: false, retryOnTooManyRequests: retryOnTooManyRequests, customHeaders: customHeaders)
                }

                // our token may have expired, remove it so next time a sync happens we'll acquire a new one
                KeychainHelper.removeKey(ServerConstants.Values.syncingV2TokenKey)
                FileLog.shared.addMessage("ApiBaseTask: Removed syncingV2TokenKey due to 401 unauthorized GET from \(url)")
                return (nil, httpResponse)
            }

            if httpResponse.statusCode == ServerConstants.HttpConstants.tooManyRequests, retryOnTooManyRequests {
                // Honor Retry-After with a single capped retry, not a loop. Blocking is
                // fine here: this always runs on an Operation's worker thread.
                let delay = httpResponse.tooManyRequestsRetryDelay()
                FileLog.shared.addMessage("ApiBaseTask: 429 rate limited GET to \(url), retrying once in \(delay)s")
                Thread.sleep(forTimeInterval: delay)
                return performGetToServer(url: url, token: token, retryOnUnauthorized: retryOnUnauthorized, retryOnTooManyRequests: false, customHeaders: customHeaders)
            }

            return (responseData, httpResponse)
        } catch {
            logFailure(method: method, url: url, error: error)
        }

        return (nil, nil)
    }

    func deleteToServer(url: String, token: String?, data: Data) -> (Data?, Int) {
        let url = ServerHelper.asUrl(url)
        let method = "DELETE"
        var request = createRequest(url: url, method: method, token: token)
        do {
            request.httpBody = data

            let (responseData, response) = try urlConnection.sendSynchronousRequest(with: request)
            guard let httpResponse = response as? HTTPURLResponse else { return (nil, ServerConstants.HttpConstants.serverError) }
            if httpResponse.statusCode == ServerConstants.HttpConstants.unauthorized {
                // our token may have expired, remove it so next time a sync happens we'll acquire a new one
                KeychainHelper.removeKey(ServerConstants.Values.syncingV2TokenKey)
                FileLog.shared.addMessage("ApiBaseTask: Removed syncingV2TokenKey due to 401 unauthorized DELETE from \(url)")
                return (nil, httpResponse.statusCode)
            }

            return (responseData, httpResponse.statusCode)
        } catch {
            logFailure(method: method, url: url.absoluteString, error: error)
        }

        return (nil, ServerConstants.HttpConstants.serverError)
    }

    func formatDate(_ date: Date?) -> String {
        if let date {
            return isoDateFormatter.string(from: date)
        }

        return ""
    }

    func createRequest(url: URL, method: String, token: String?) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: syncTimeout)
        request.httpMethod = method
        request.addValue("application/octet-stream", forHTTPHeaderField: ServerConstants.HttpHeaders.accept)
        request.setValue("application/octet-stream", forHTTPHeaderField: ServerConstants.HttpHeaders.contentType)
        request.addLocalizationHeaders()
        let privateUserAgent = ServerConfig.shared.syncDelegate?.privateUserAgent() ?? ""
        request.setValue(privateUserAgent, forHTTPHeaderField: ServerConstants.HttpHeaders.userAgent)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // for subclasses that talk to the API server to override
    func apiTokenAcquired(token: String) {}
    func apiTokenAcquisitionFailed() { print("\(self) apiTokenAcquisitionFailed") }

    private func logFailure(method: String, url: String, error: Error) {
        FileLog.shared.addMessage("[\(type(of: self))] Failed to \(method) to server (\(url)) \(error)")
    }
}
