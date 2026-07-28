import Foundation
import PocketCastsUtils
#if os(iOS)
import UIKit
#endif

/// Serializes token acquisition so only one credential grant (refresh or login) is ever
/// in flight per process; concurrent callers await the same in-flight task and share its
/// result. Single-flight must precede server-side refresh-token rotation (plan C.0-3):
/// two concurrent refresh grants presenting the same token would race the rotation.
actor TokenAcquisitionSerializer {
    private var inFlightTask: Task<AuthenticationResponse?, Error>?

    func acquire(_ operation: @escaping @Sendable () async throws -> AuthenticationResponse?) async throws -> AuthenticationResponse? {
        if let inFlightTask {
            return try await inFlightTask.value
        }

        let task = Task { try await operation() }
        inFlightTask = task
        defer { inFlightTask = nil }
        return try await task.value
    }
}

// Token state lives in the keychain/ServerSettings; the only stored property
// is an immutable URLConnection.
final class TokenHelper: Sendable {

    static let shared = TokenHelper(urlConnection: URLConnection(handler: URLSession.shared))

    // Process-wide on purpose: helpers constructed with their own URLConnection
    // (DiscoverServerHandler's caching connection, tests) still share one single-flight
    // gate, so at most one credential grant is in flight regardless of instance.
    private static let acquisitionSerializer = TokenAcquisitionSerializer()

    private let urlConnection: URLConnection

    init(urlConnection: URLConnection) {
        self.urlConnection = urlConnection
    }

    func callSecureUrl(request: URLRequest, completion: @escaping @Sendable (HTTPURLResponse?, Data?, Error?) -> Void) {
        DispatchQueue.global().async { [weak self] in
            self?.performCallSecureUrl(request: request, retryOnUnauthorized: true, completion: completion)
        }
    }

    /// Makes an authentication URL request and returns the response and data asynchronously
    /// - Parameter request: The URLRequest to execute using URLConnection
    /// - Returns: A tuple containing the HTTPURLResponse and Data
    /// - Throws: Any error returned from the URLConnection
    func callSecureUrl(request: URLRequest) async throws -> (HTTPURLResponse?, Data?) {
        try await withCheckedThrowingContinuation { continuation in
            performCallSecureUrl(request: request, retryOnUnauthorized: true) { response, data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (response, data))
            }
        }
    }

    private func performCallSecureUrl(request: URLRequest, retryOnUnauthorized: Bool = true, retryOnTooManyRequests: Bool = true, completion: @escaping @Sendable (HTTPURLResponse?, Data?, Error?) -> Void) {
        var mutableRequest = request

        if let privateUserAgent = ServerConfig.shared.syncDelegate?.privateUserAgent() {
            mutableRequest.setValue(privateUserAgent, forHTTPHeaderField: ServerConstants.HttpHeaders.userAgent)
        }

        if SyncManager.isUserLoggedIn() {
            let token: String
            // A stored token past its expiry hint counts as absent, so we refresh
            // proactively instead of burning a request to collect the 401.
            if let storedToken = ServerSettings.validSyncingV2Token() {
                token = storedToken
            } else if let newToken = acquireToken() {
                token = newToken
            } else {
                completion(nil, nil, nil)
                return
            }

            mutableRequest.setValue("Bearer \(token)", forHTTPHeaderField: ServerConstants.HttpHeaders.authorization)
        }

        urlConnection.send(request: mutableRequest) { [weak self] data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(nil, nil, error)
                return
            }

            if httpResponse.statusCode == ServerConstants.HttpConstants.unauthorized {
                if SyncManager.isUserLoggedIn(), retryOnUnauthorized {
                    KeychainHelper.removeKey(ServerConstants.Values.syncingV2TokenKey)
                    FileLog.shared.addMessage("TokenHelper: Removed syncingV2TokenKey due to 401 unauthorized retrying url: \(request.url?.absoluteString ?? "unknown")")
                    self?.performCallSecureUrl(request: request, retryOnUnauthorized: false, retryOnTooManyRequests: retryOnTooManyRequests, completion: completion)
                } else {
                    completion(httpResponse, nil, error)
                }

                return
            }

            if httpResponse.statusCode == ServerConstants.HttpConstants.tooManyRequests {
                if let self, retryOnTooManyRequests {
                    // Honor Retry-After with a single capped retry, not a loop.
                    let delay = httpResponse.tooManyRequestsRetryDelay()
                    FileLog.shared.addMessage("TokenHelper: 429 rate limited, retrying once in \(delay)s url: \(request.url?.absoluteString ?? "unknown")")
                    // Strong capture: a one-shot retry must deliver its completion even if
                    // no other reference to this helper remains while we wait.
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.performCallSecureUrl(request: request, retryOnUnauthorized: retryOnUnauthorized, retryOnTooManyRequests: false, completion: completion)
                    }
                } else {
                    completion(httpResponse, data, error)
                }

                return
            }

            completion(httpResponse, data, error)
        }
    }

    func acquireToken() -> String? {
        // The semaphore establishes the happens-before edge for the boxed result.
        let semaphore = DispatchSemaphore(value: 0)
        let box = UncheckedSendableBox<(response: AuthenticationResponse?, error: Error?)>((nil, nil))

        asyncAcquireToken { result in
            switch result {
            case .success(let authenticationResponse):
                box.value.response = authenticationResponse
            case .failure(let resultError):
                box.value.error = resultError
            }
            semaphore.signal()
        }

        semaphore.wait()

        let (response, error) = box.value
        guard let refreshedToken = response?.token, !refreshedToken.isEmpty else {
            if isApplicationBackgrounded() {
                FileLog.shared.addMessage("TokenHelper: Skipped logout in background due to error: \(String(describing: error))")
            } else {
                // if the user doesn't have an email and password or SSO token, they aren't going to be able to acquire a sync token
                switch error as? APIError {
                case APIError.TOKEN_DEAUTH?, APIError.PERMISSION_DENIED?:
                    tokenCleanUp()
                default:
                    // Do nothing so the user is not disrupted in the case of non-auth errors
                    FileLog.shared.addMessage("TokenHelper: Unable to acquire token but avoided logout due to error: \(String(describing: error))")
                }
            }

            return nil
        }

        ServerSettings.syncingV2Token = refreshedToken
        // C.0-1: proto strings default to "" when omitted — never overwrite the stored
        // refresh token with an empty value (it would silently brick future refreshes).
        // Keep the previous token when the response didn't carry one.
        if let refreshedRefreshToken = response?.refreshToken, !refreshedRefreshToken.isEmpty {
            if !ServerSettings.setRefreshToken(refreshedRefreshToken) {
                // The server rotated the presented token away, so a failed persist leaves a
                // dead refresh token stored. Nothing can restore it client-side; log loudly
                // so the eventual forced reauthentication is diagnosable.
                FileLog.shared.addMessage("TokenHelper: CRITICAL keychain write of rotated refresh token failed; the stored refresh token is now stale and the next refresh will force reauthentication")
            }
        }
        // C.0-2: persist the expiry hint for the new token; when the server didn't send
        // expires_in this clears any stale hint (the 401 path remains the authority).
        ServerSettings.setTokenExpiry(expiresIn: response?.expiresIn)

        return refreshedToken
    }

    private func isApplicationBackgrounded() -> Bool {
        // The semaphore establishes the happens-before edge for the boxed result.
        let semaphore = DispatchSemaphore(value: 0)
        let isBackgrounded = UncheckedSendableBox(false)

        DispatchQueue.main.async {
            #if os(iOS)
            isBackgrounded.value = UIApplication.shared.applicationState == .background
            #endif

            semaphore.signal()
        }

        semaphore.wait()
        return isBackgrounded.value
    }

    // MARK: - Token Acquisition

    func asyncAcquireToken(completion: @escaping @Sendable (Result<AuthenticationResponse?, Error>) -> Void) {
        Task {
            do {
                let response = try await Self.acquisitionSerializer.acquire { [self] in
                    try await performTokenAcquisition()
                }
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// The single-flight acquisition body. Runs at most once per in-flight window;
    /// concurrent acquirers share the result.
    private func performTokenAcquisition() async throws -> AuthenticationResponse? {
        if FeatureFlag.refreshTokenForPasswordAuth.enabled {
            return try await performTokenAcquisitionPreferringRefreshGrant()
        }

        // Legacy order: replay the stored password when present, otherwise the SSO refresh grant.
        if let authenticationResponse = try await acquirePasswordToken() {
            return authenticationResponse
        }

        return try await acquireIdentityToken()
    }

    /// Workstream A (plan §2.4.1/§2.4.3): the refresh grant comes first whenever a refresh
    /// token exists, regardless of account type. A stored password is used for at most one
    /// final user/login to migrate the account to a refresh-token pair.
    private func performTokenAcquisitionPreferringRefreshGrant() async throws -> AuthenticationResponse? {
        if let refreshToken = try? ServerSettings.refreshToken(), !refreshToken.isEmpty {
            return try await acquireIdentityToken()
        }

        if let authenticationResponse = try await acquirePasswordToken() {
            migratePasswordAccountIfPossible(response: authenticationResponse)
            return authenticationResponse
        }

        // No refresh token and no stored password: not signed in (nothing to recover with).
        return nil
    }

    /// §2.4.3 step 2: one-shot upgrade of a password account to refresh-token auth.
    /// Persists the token pair and deletes the stored password ONLY when the server
    /// returned a non-empty refresh token (server ≥ M1) AND the keychain write of that
    /// token succeeded. Otherwise today's behavior is kept — the password stays put and
    /// migration retries on a later acquire, which makes this client release safe to
    /// ship before the server flips and tolerant of a server rollback.
    func migratePasswordAccountIfPossible(response: AuthenticationResponse) {
        guard FeatureFlag.refreshTokenForPasswordAuth.enabled,
              let refreshToken = response.refreshToken, !refreshToken.isEmpty
        else {
            return
        }

        if let token = response.token, !token.isEmpty {
            ServerSettings.syncingV2Token = token
        }
        guard ServerSettings.setRefreshToken(refreshToken) else {
            // A failed keychain write must not delete the password below: it's the only
            // remaining recoverable credential, so keep it and retry on a later acquire.
            FileLog.shared.addMessage("TokenHelper: keychain write of refresh token failed during password-account migration; keeping stored password so migration can retry")
            return
        }
        ServerSettings.setTokenExpiry(expiresIn: response.expiresIn)
        KeychainHelper.removeKey(ServerConstants.Values.syncingLoginItemName)
        ServerSettings.accountAuthMethod = .password
        // Migration marker only — never log token or password material.
        FileLog.shared.addMessage("TokenHelper: password account migrated to refresh-token auth; stored password removed")
    }

    // MARK: - Email / Password Token

    func acquirePasswordToken() async throws -> AuthenticationResponse? {
        try await acquirePasswordToken(retryOnTooManyRequests: true)
    }

    private func acquirePasswordToken(retryOnTooManyRequests: Bool) async throws -> AuthenticationResponse? {
        guard let email = ServerSettings.syncingEmail(), let password = ServerSettings.syncingPassword() else {
            // if the user doesn't have an email and password, then we'll check if they're using SSO
            return nil
        }

        let url = ServerHelper.asUrl(ServerConstants.Urls.api() + "user/login")
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30.seconds)
            request.httpMethod = "POST"
            request.addValue("application/octet-stream", forHTTPHeaderField: ServerConstants.HttpHeaders.accept)
            request.setValue("application/octet-stream", forHTTPHeaderField: ServerConstants.HttpHeaders.contentType)
            request.addLocalizationHeaders()
            if let privateUserAgent = ServerConfig.shared.syncDelegate?.privateUserAgent() {
                request.setValue(privateUserAgent, forHTTPHeaderField: ServerConstants.HttpHeaders.userAgent)
            }

            var loginRequest = Api_UserLoginRequest()
            loginRequest.email = email
            loginRequest.password = password
            loginRequest.scope = ServerConstants.Values.apiScope
            let deviceId = ServerConfig.shared.syncDelegate?.uniqueAppId() ?? ""
            if deviceId.isEmpty {
                FileLog.shared.addMessage("TokenHelper: no uniqueAppId available at login; tokens will be issued without device binding")
            }
            loginRequest.device = deviceId
            let data = try loginRequest.serializedData()
            request.httpBody = data

            let (responseData, response) = try await urlConnection.send(request: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                FileLog.shared.addMessage("TokenHelper: Unable to acquire token")
                return nil
            }

            // Before the body guard: rate-limit responses legitimately carry no body.
            if httpResponse.statusCode == ServerConstants.HttpConstants.tooManyRequests, retryOnTooManyRequests {
                // Honor Retry-After with a single capped retry, not a loop.
                let delay = httpResponse.tooManyRequestsRetryDelay()
                FileLog.shared.addMessage("TokenHelper: user/login rate limited (429), retrying once in \(delay)s")
                try await Task.sleep(for: .seconds(delay))
                return try await acquirePasswordToken(retryOnTooManyRequests: false)
            }

            guard let validData = responseData else {
                FileLog.shared.addMessage("TokenHelper: Unable to acquire token")
                return nil
            }

            if httpResponse.statusCode == ServerConstants.HttpConstants.ok {
                let userLoginResponse = try Api_UserLoginResponse(serializedBytes: validData)
                return AuthenticationResponse(from: userLoginResponse)
            }

            if httpResponse.statusCode == ServerConstants.HttpConstants.unauthorized {
                FileLog.shared.addMessage("TokenHelper logging user out, invalid password")
                SyncManager.signout()
            }

            let errorResponse = ApiServerHandler.extractErrorResponse(data: responseData, response: response, error: nil)
            throw errorResponse ?? .UNKNOWN
        } catch {
            FileLog.shared.addMessage("TokenHelper acquireToken failed \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - SSO Identity Token

    private func acquireIdentityToken() async throws -> AuthenticationResponse {
        return try await ApiServerHandler.shared.refreshIdentityToken()
    }

    // MARK: Cleanup

    private func tokenCleanUp() {
        var logMessages = [String]()

        defer {
            FileLog.shared.addMessage("Acquire Token was called, however the user has \(logMessages.joined(separator: ", ")).")
        }

        if ServerSettings.syncingEmail() == nil {
            logMessages.append("no email address")
        }

        // Workstream A: once refresh-token auth is on, "can this account recover?" is a
        // has-refresh-token question only; the stored password no longer participates.
        if !FeatureFlag.refreshTokenForPasswordAuth.enabled, ServerSettings.syncingPassword() == nil {
            logMessages.append("no password")
        }

        do {
            if try ServerSettings.refreshToken() == nil {
                logMessages.append("no SSO token")
            }
        } catch {
            if case let KeychainHelper.KeychainError.status(status) = error, status == errSecInteractionNotAllowed {
                logMessages.append("no SSO token")
                FileLog.shared.addMessage("Acquire Token was called, however the user has \(logMessages.joined(separator: ", ")).")
                return
            }
        }

        FileLog.shared.addMessage("Sync account is in a weird state, logging user out")
        SyncManager.signout()
    }
}
