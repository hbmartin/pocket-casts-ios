import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

class AuthenticationHelper {

    @discardableResult
    static func refreshLogin(scope: AuthenticationScope = .mobile) async throws -> String? {
        if let username = ServerSettings.syncingEmail(), let password = ServerSettings.syncingPassword(), !password.isEmpty {
            return try await validateLogin(username: username, password: password, scope: scope).token
        }
        else if let token = try? ServerSettings.refreshToken() {
            return try await validateLogin(identityToken: token, scope: scope).token
        }

        return nil
    }

    // MARK: Password

    static func validateLogin(username: String, password: String, scope: AuthenticationScope) async throws -> AuthenticationResponse {
        let response = try await ApiServerHandler.shared.validateLogin(username: username, password: password, scope: scope.rawValue)
        try validatePasswordSignInResponse(response)
        try handleSuccessfulSignIn(response, requireRefreshTokenPersistence: FeatureFlag.refreshTokenForPasswordAuth.enabled)

        // If the server didn't return a new email, and the call was successful, then reset the email to the one used to
        // validate the login
        if ServerSettings.syncingEmail() == nil {
            ServerSettings.setSyncingEmail(email: username)
        }

        persistPasswordForLegacyAuthenticationIfNeeded(password)

        return response
    }

    /// Password-auth sessions must be renewable before they replace the current session.
    /// The flag remains off until user/login can return this field; rejecting an omitted or
    /// empty value keeps early flag enablement and server rollback fail-closed.
    static func validatePasswordSignInResponse(_ response: AuthenticationResponse) throws {
        let requiresRefreshToken = FeatureFlag.refreshTokenForPasswordAuth.enabled
        guard !requiresRefreshToken || response.refreshToken?.isEmpty == false else {
            throw APIError.TOKEN_DEAUTH
        }
    }

    /// The plaintext password remains a rollback credential only while the legacy path is
    /// explicitly selected. ServerSettings repeats this guard at the Keychain sink so a new
    /// call site cannot bypass the feature policy.
    static func persistPasswordForLegacyAuthenticationIfNeeded(_ password: String) {
        guard !FeatureFlag.refreshTokenForPasswordAuth.enabled else {
            ServerSettings.accountAuthMethod = .password
            return
        }

        ServerSettings.saveSyncingPassword(password) // nosemgrep: pocketcasts.no-persisted-account-password
    }

    // MARK: Apple SSO

    static func validateLogin(identityToken: String, scope: AuthenticationScope = .mobile)  async throws -> AuthenticationResponse {
        let response = try await ApiServerHandler.shared.validateLogin(identityToken: identityToken, scope: scope)
        // handleSuccessfulSignIn persists the refresh token (guarded against empty values) —
        // the duplicate unguarded write that used to live here is gone.
        try handleSuccessfulSignIn(response)

        if FeatureFlag.refreshTokenForPasswordAuth.enabled {
            ServerSettings.accountAuthMethod = .sso
        }

        return response
    }

    // MARK: Common

    /// Persists the credential material from an authentication response.
    /// Internal (not private) so the empty-refresh-token guard is unit-testable.
    @discardableResult
    static func persistSignInCredentials(from response: AuthenticationResponse) -> Bool {
        ServerSettings.userId = response.uuid
        ServerSettings.syncingV2Token = response.token
        // Proto strings default to "" when omitted — never clobber a stored refresh token
        // with an empty value (it would silently brick future refreshes).
        var refreshTokenPersisted = true
        if let refreshToken = response.refreshToken, !refreshToken.isEmpty {
            refreshTokenPersisted = ServerSettings.setRefreshToken(refreshToken)
        }
        // Expiry is a hint; nil clears any stale hint from a previous token.
        ServerSettings.setTokenExpiry(expiresIn: response.expiresIn)
        return refreshTokenPersisted
    }

    static func handleSuccessfulSignIn(
        _ response: AuthenticationResponse,
        requireRefreshTokenPersistence: Bool = false
    ) throws {
        SyncManager.clearTokensFromKeyChain()
        FileLog.shared.addMessage("AuthenticationHelper.handleSuccessfulSignIn clearTokensFromKeyChain")

        let refreshTokenPersisted = persistSignInCredentials(from: response)
        guard !requireRefreshTokenPersistence || refreshTokenPersisted else {
            // Never report a renewable password-auth session when the replacement
            // refresh token could not be committed to the Keychain.
            SyncManager.clearTokensFromKeyChain()
            ServerSettings.userId = nil
            ServerSettings.setTokenExpiry(expiresIn: nil)
            throw APIError.TOKEN_DEAUTH
        }

        // we've signed in, set all our existing podcasts to
        // be non synced if the user never logged in before
        if (FeatureFlag.onlyMarkPodcastsUnsyncedForNewUsers.enabled && ServerSettings.lastSyncTime == nil)
            || !FeatureFlag.onlyMarkPodcastsUnsyncedForNewUsers.enabled {
            DataManager.sharedManager.markAllPodcastsUnsynced()
        }

        SyncManager.syncReason = .login
        ServerSettings.clearLastSyncTime()

        // This check may not be necessary in the long run see: https://github.com/Automattic/pocket-casts-ios/issues/412
        if let email = response.email, !email.isEmpty {
            ServerSettings.setSyncingEmail(email: response.email)
        }

        NotificationCenter.postOnMainThread(UserLoginDidChange())

        RefreshManager.shared.refreshPodcasts(forceEvenIfRefreshedRecently: true)
    }

    // MARK: Code Login - For tv login using a QR Code

    @discardableResult
    static func deviceAuthorizeCode(scope: AuthenticationScope = .tv) async throws -> DeviceAuthorizationResponse {
        let response = try await ApiServerHandler.shared.deviceAuthorizeRequest(scope: scope.rawValue)
        return response
    }

    @discardableResult
    static func deviceGetToken(deviceCode: String, scope: AuthenticationScope = .tv) async throws -> AuthenticationResponse {
        let response = try await ApiServerHandler.shared.deviceGetToken(deviceCode: deviceCode)
        try handleSuccessfulSignIn(response)

        return response
    }

    static func deviceWaitForApproval(deviceCode: String) async throws {
        var shouldContinue = true
        let sleepTime = 2
        while shouldContinue {
            try await Task.sleep(for: .seconds(sleepTime))
            do {
                let response = try await AuthenticationHelper.deviceGetToken(deviceCode: deviceCode)
                if response.token == nil { // DO we have a token?
                    throw APIError.UNKNOWN
                } else {
                    // We have a token so we can return
                    return
                }
            } catch let error as APIError {
                switch error {
                case .AUTHORIZATION_PENDING:
                    shouldContinue = true
                default:
                    throw error
                }
            }
        }
        // If we got to here it's because the max retries expired
        throw APIError.UNKNOWN
    }
}
