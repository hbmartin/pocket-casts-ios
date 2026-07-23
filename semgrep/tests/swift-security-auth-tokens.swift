// Fixtures for the API-auth-hardening guardrails (plans/API Auth Hardening Plan.md):
// pocketcasts.no-persisted-account-password, pocketcasts.auth-keychain-items-device-only,
// and pocketcasts.no-empty-refresh-token-persist.

import Foundation

// MARK: - pocketcasts.no-persisted-account-password

func signInLegacy(password: String) {
    // ruleid: pocketcasts.no-persisted-account-password
    ServerSettings.saveSyncingPassword(password)
}

func writePasswordDirectly(password: String) {
    // ruleid: pocketcasts.no-persisted-account-password
    KeychainHelper.save(string: password, key: ServerConstants.Values.syncingLoginItemName, accessibility: kSecAttrAccessibleAfterFirstUnlock)
}

func writePasswordWithLiteralKey(password: String) {
    // ruleid: pocketcasts.no-persisted-account-password
    KeychainHelper.save(string: password, key: "SJSyncingPwd", accessibility: kSecAttrAccessibleAfterFirstUnlock)
}

func removePasswordIsFine() {
    // ok: pocketcasts.no-persisted-account-password
    KeychainHelper.removeKey(ServerConstants.Values.syncingLoginItemName)
}

public class UnsafePasswordSettings {
    // ruleid: pocketcasts.password-writer-must-reject-refresh-auth
    public class func saveSyncingPassword(_ password: String) {
        // ruleid: pocketcasts.no-persisted-account-password
        KeychainHelper.save(string: password, key: ServerConstants.Values.syncingLoginItemName, accessibility: kSecAttrAccessibleAfterFirstUnlock)
    }
}

public class SafePasswordSettings {
    // ok: pocketcasts.password-writer-must-reject-refresh-auth
    public class func saveSyncingPassword(_ password: String) {
        guard !FeatureFlag.refreshTokenForPasswordAuth.enabled else {
            return
        }

        // ruleid: pocketcasts.no-persisted-account-password
        KeychainHelper.save(string: password, key: ServerConstants.Values.syncingLoginItemName, accessibility: kSecAttrAccessibleAfterFirstUnlock)
    }
}

// MARK: - pocketcasts.auth-keychain-items-device-only

func saveRefreshTokenBackupRestorable(token: String) {
    // ruleid: pocketcasts.auth-keychain-items-device-only
    KeychainHelper.save(string: token, key: ServerConstants.Values.refreshTokenKey, accessibility: kSecAttrAccessibleAfterFirstUnlock)
}

func saveSyncTokenBackupRestorable(token: String) {
    // ruleid: pocketcasts.auth-keychain-items-device-only
    KeychainHelper.save(string: token, key: ServerConstants.Values.syncingV2TokenKey, accessibility: kSecAttrAccessibleWhenUnlocked)
}

func saveRefreshTokenLiteralKeyBackupRestorable(token: String) {
    // ruleid: pocketcasts.auth-keychain-items-device-only
    KeychainHelper.save(string: token, key: "SJRefreshToken", accessibility: kSecAttrAccessibleAfterFirstUnlock)
}

func saveRefreshTokenDeviceOnly(token: String) {
    // ok: pocketcasts.auth-keychain-items-device-only
    KeychainHelper.save(string: token, key: ServerConstants.Values.refreshTokenKey, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
}

func saveSyncTokenDeviceOnly(token: String) {
    // ok: pocketcasts.auth-keychain-items-device-only
    KeychainHelper.save(string: token, key: "SJSyncV2Token", accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
}

func saveEmailStaysBackupRestorable(email: String) {
    // The email item is PII but not a credential; it intentionally stays restorable.
    // ok: pocketcasts.auth-keychain-items-device-only
    KeychainHelper.save(string: email, key: ServerConstants.Values.syncingEmailKey, accessibility: kSecAttrAccessibleAfterFirstUnlock)
}

// MARK: - pocketcasts.no-empty-refresh-token-persist

func persistResponseFieldDirectly(response: AuthenticationResponse) {
    // ruleid: pocketcasts.no-empty-refresh-token-persist
    ServerSettings.setRefreshToken(response.refreshToken)
}

func persistGuardedRefreshToken(response: AuthenticationResponse) {
    if let refreshToken = response.refreshToken, !refreshToken.isEmpty {
        // ok: pocketcasts.no-empty-refresh-token-persist
        ServerSettings.setRefreshToken(refreshToken)
    }
}
