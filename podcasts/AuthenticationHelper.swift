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
        handleSuccessfulSignIn(response)

        // If the server didn't return a new email, and the call was successful, then reset the email to the one used to
        // validate the login
        if ServerSettings.syncingEmail() == nil {
            ServerSettings.setSyncingEmail(email: username)
        }

        if FeatureFlag.refreshTokenForPasswordAuth.enabled {
            ServerSettings.accountAuthMethod = .password
        } else {
            // Legacy credential persistence until refresh-token auth for password accounts
            // ships (plan workstream A / M1); with the flag on, re-auth uses the refresh grant.
            ServerSettings.saveSyncingPassword(password) // nosemgrep: pocketcasts.no-persisted-account-password
        }

        return response
    }

    // MARK: Apple SSO

    static func validateLogin(identityToken: String, scope: AuthenticationScope = .mobile)  async throws -> AuthenticationResponse {
        let response = try await ApiServerHandler.shared.validateLogin(identityToken: identityToken, scope: scope)
        // handleSuccessfulSignIn persists the refresh token (guarded against empty values) —
        // the duplicate unguarded write that used to live here is gone.
        handleSuccessfulSignIn(response)

        if FeatureFlag.refreshTokenForPasswordAuth.enabled {
            ServerSettings.accountAuthMethod = .sso
        }

        return response
    }

    // MARK: Common

    /// Persists the credential material from an authentication response.
    /// Internal (not private) so the empty-refresh-token guard is unit-testable.
    static func persistSignInCredentials(from response: AuthenticationResponse) {
        ServerSettings.userId = response.uuid
        ServerSettings.syncingV2Token = response.token
        // Proto strings default to "" when omitted — never clobber a stored refresh token
        // with an empty value (it would silently brick future refreshes).
        if let refreshToken = response.refreshToken, !refreshToken.isEmpty {
            ServerSettings.setRefreshToken(refreshToken)
        }
        // Expiry is a hint; nil clears any stale hint from a previous token.
        ServerSettings.setTokenExpiry(expiresIn: response.expiresIn)
    }

    private static func handleSuccessfulSignIn(_ response: AuthenticationResponse) {
        SyncManager.clearTokensFromKeyChain()
        FileLog.shared.addMessage("AuthenticationHelper.handleSuccessfulSignIn clearTokensFromKeyChain")

        persistSignInCredentials(from: response)

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
        handleSuccessfulSignIn(response)

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
