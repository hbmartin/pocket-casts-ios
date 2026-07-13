import Foundation
import PocketCastsUtils

public class ServerSettings {
    // MARK: - Last Update Status

    private static let lastSyncSuccess = "LastSyncSuccess"
    public class func lastSyncSucceeded() -> Bool {
        if let succeeded = UserDefaults.standard.value(forKey: lastSyncSuccess) as? Bool {
            return succeeded
        }

        return true
    }

    public class func setLastSyncSucceeded(_ succeeded: Bool) {
        UserDefaults.standard.set(succeeded, forKey: lastSyncSuccess)
    }

    private static let lastRefreshSuccess = "LastRefreshSuccess"
    public class func lastRefreshSucceeded() -> Bool {
        if let succeeded = UserDefaults.standard.value(forKey: lastRefreshSuccess) as? Bool {
            return succeeded
        }

        return true
    }

    public class func setLastRefreshSucceeded(_ succeeded: Bool) {
        UserDefaults.standard.set(succeeded, forKey: lastRefreshSuccess)
    }

    // MARK: - Skip Forward

    private static let skipForwardAmount = "JumpForwardAmountInSeconds"
    private static let skipForwardNeedsSync = "JumpForwardSynced"
    public class func setSkipForwardTime(_ time: Int, syncChange: Bool = true) {
        UserDefaults.standard.set(time, forKey: ServerSettings.skipForwardAmount)

        if syncChange {
            UserDefaults.standard.set(true, forKey: ServerSettings.skipForwardNeedsSync)
        }
    }

    public class func skipForwardTime() -> Int {
        UserDefaults.standard.integer(forKey: ServerSettings.skipForwardAmount)
    }

    public class func skipForwardNeedsSyncing() -> Bool {
        UserDefaults.standard.bool(forKey: ServerSettings.skipForwardNeedsSync)
    }

    public class func setSkipForwardSynced() {
        UserDefaults.standard.set(false, forKey: ServerSettings.skipForwardNeedsSync)
    }

    // MARK: - Skip Back

    private static let skipBackAmount = "JumpBackAmountInSeconds"
    private static let skipBackNeedsSync = "JumpBackSynced"
    public class func setSkipBackTime(_ time: Int, syncChange: Bool = true) {
        UserDefaults.standard.set(time, forKey: ServerSettings.skipBackAmount)

        if syncChange {
            UserDefaults.standard.set(true, forKey: ServerSettings.skipBackNeedsSync)
        }
    }

    public class func skipBackTime() -> Int {
        UserDefaults.standard.integer(forKey: ServerSettings.skipBackAmount)
    }

    public class func skipBackNeedsSyncing() -> Bool {
        UserDefaults.standard.bool(forKey: ServerSettings.skipBackNeedsSync)
    }

    public class func setSkipBackSynced() {
        UserDefaults.standard.set(false, forKey: ServerSettings.skipBackNeedsSync)
    }

    // MARK: Home Grid Order

    private static let homeGridSortOrderKey = "SJPodcastLibrarySort"
    private static let homeGridSortModifiedKey = "SJPodcastLibrarySortModified"
    public class func homeGridSortOrderNeedsSyncing() -> Bool {
        UserDefaults.standard.bool(forKey: ServerSettings.homeGridSortModifiedKey)
    }

    public class func setHomeGridSortOrder(_ order: Int, syncChange: Bool = false) {
        UserDefaults.standard.set(order, forKey: homeGridSortOrderKey)
        if syncChange {
            UserDefaults.standard.set(true, forKey: homeGridSortModifiedKey)
        }
    }

    public class func setHomeGridSortOrderSynced() {
        UserDefaults.standard.set(false, forKey: homeGridSortModifiedKey)
    }

    public class func homeGridSortOrder() -> Int {
        UserDefaults.standard.integer(forKey: homeGridSortOrderKey)
    }

    // MARK: Home Grid Refresh

    private static let homeGridNeedsRefreshKey = "SJHomeGridRefreshRequired"
    public class func setHomeGridNeedsRefresh(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: homeGridNeedsRefreshKey)
    }

    public class func homeGridNeedsRefresh() -> Bool {
        UserDefaults.standard.bool(forKey: homeGridNeedsRefreshKey)
    }

    // MARK: Clear Listening History Date

    public class func setLastClearHistoryDate(_ value: Date?) {
        if let newDate = value {
            UserDefaults.standard.set(newDate, forKey: ServerConstants.UserDefaults.lastClearHistoryDate)
        } else {
            UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.lastClearHistoryDate)
        }
    }

    public class func lastClearHistoryDate() -> Date? {
        UserDefaults.standard.value(forKey: ServerConstants.UserDefaults.lastClearHistoryDate) as? Date
    }

    // MARK: Marketing Opt In

    public class func setMarketingOptIn(_ value: Bool) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.marketingOptIn = value
        }
        UserDefaults.standard.set(value, forKey: ServerConstants.UserDefaults.marketingOptInKey)
        UserDefaults.standard.set(true, forKey: ServerConstants.UserDefaults.marketingOptInNeedsSyncKey)
    }

    public class func marketingOptIn() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.marketingOptIn
        } else {
            return UserDefaults.standard.bool(forKey: ServerConstants.UserDefaults.marketingOptInKey)
        }
    }

    public class func marketingOptInNeedsSyncing() -> Bool {
        UserDefaults.standard.bool(forKey: ServerConstants.UserDefaults.marketingOptInNeedsSyncKey)
    }

    public class func marketingOptInSynced() {
        UserDefaults.standard.set(false, forKey: ServerConstants.UserDefaults.marketingOptInNeedsSyncKey)
    }

    public class func syncingEmail() -> String? {
        try? KeychainHelper.string(for: ServerConstants.Values.syncingEmailKey)
    }

    public class func setSyncingEmail(email: String?) {
        if let email {
            KeychainHelper.save(string: email, key: ServerConstants.Values.syncingEmailKey, accessibility: kSecAttrAccessibleAfterFirstUnlock)
        } else {
            KeychainHelper.removeKey(ServerConstants.Values.syncingEmailKey)
        }
    }

    // The two methods below should only be used for migration purposes, it's the old way of storing email addresses we don't use anymore
    public class func syncingEmailLegacy() -> String? {
        UserDefaults.standard.string(forKey: ServerConstants.UserDefaults.syncingEmailLegacy)
    }

    public class func removeLegacySyncingEmail() {
        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.syncingEmailLegacy)
    }

    /// Legacy password persistence — the definition every allowlisted caller funnels
    /// through. Goes away entirely once `FeatureFlag.refreshTokenForPasswordAuth`
    /// migration completes fleet-wide (plan workstream A).
    public class func saveSyncingPassword(_ password: String) {
        KeychainHelper.save(string: password, key: ServerConstants.Values.syncingLoginItemName, accessibility: kSecAttrAccessibleAfterFirstUnlock) // nosemgrep: pocketcasts.no-persisted-account-password
    }

    public class func syncingPassword() -> String? {
        try? KeychainHelper.string(for: ServerConstants.Values.syncingLoginItemName)
    }

    public class func lastRefreshStartTime() -> Date? {
        UserDefaults.standard.object(forKey: ServerConstants.UserDefaults.lastRefreshStartTime) as? Date
    }

    public class func lastRefreshEndTime() -> Date? {
        UserDefaults.standard.object(forKey: ServerConstants.UserDefaults.lastRefreshEndTime) as? Date
    }

    public class func clearLastSyncTime() {
        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.lastSyncTime)
    }

    public class var lastSyncTime: Date? {
        UserDefaults.standard.object(forKey: ServerConstants.UserDefaults.lastSyncTime) as? Date
    }

    // Push Token
    public class func pushToken() -> String? {
        if let token = try? KeychainHelper.string(for: ServerConstants.Values.pushTokenKey) {
            return token
        }

        guard let legacyToken = UserDefaults.standard.string(forKey: ServerConstants.UserDefaults.pushToken) else {
            return nil
        }

        if savePushTokenToKeychain(legacyToken) {
            UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.pushToken)
        }

        return legacyToken
    }

    public class func setPushToken(token: String) {
        guard savePushTokenToKeychain(token) else { return }

        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.pushToken)
    }

    public class func removePushToken() {
        KeychainHelper.removeKey(ServerConstants.Values.pushTokenKey)
        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.pushToken)
    }

    @discardableResult
    private class func savePushTokenToKeychain(_ token: String) -> Bool {
        let saved = KeychainHelper.save(string: token, key: ServerConstants.Values.pushTokenKey, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        if !saved {
            FileLog.shared.addMessage("ServerSettings: Failed to save push token to Keychain")
        }

        return saved
    }

    // MARK: - Auto add to Up Next Limit

    public static let autoAddLimitKey = "AutoAddToUpNextLimit"
    public class func autoAddToUpNextLimit() -> Int {
        if FeatureFlag.newSettingsStorage.enabled {
            Int(SettingsStore.appSettings.autoUpNextLimit)
        } else {
            UserDefaults.standard.integer(forKey: autoAddLimitKey)
        }
    }

    public class func setAutoAddToUpNextLimit(_ limit: Int) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.autoUpNextLimit = Int32(limit)
        }
        UserDefaults.standard.setValue(limit, forKey: autoAddLimitKey)
    }

    public static let onAutoAddLimitReachedKey = "AutoAddLimitReachedKey"
    public class func onAutoAddLimitReached() -> AutoAddLimitReachedAction {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.autoUpNextLimitReached
        } else {
            let storedValue = UserDefaults.standard.integer(forKey: onAutoAddLimitReachedKey)

            return AutoAddLimitReachedAction(rawValue: Int32(storedValue)) ?? .stopAdding
        }
    }

    public class func setOnAutoAddLimitReached(action: AutoAddLimitReachedAction) {
        if FeatureFlag.newSettingsStorage.enabled {
            SettingsStore.appSettings.autoUpNextLimitReached = action
        }
        UserDefaults.standard.setValue(action.rawValue, forKey: onAutoAddLimitReachedKey)
    }

    public class func syncSettings() {
        guard SyncManager.isUserLoggedIn(), ServerSettings.marketingOptInNeedsSyncing() else { return }

        ApiServerHandler.shared.syncSettings()
    }
}

// MARK: - Authentication Support

public extension ServerSettings {
    class var userId: String? {
        get {
            UserDefaults.standard.string(forKey: ServerConstants.UserDefaults.userId)
        }

        set {
            UserDefaults.standard.set(newValue, forKey: ServerConstants.UserDefaults.userId)
        }
    }

    // Credential Keychain items use AfterFirstUnlock (not WhenUnlocked) because background
    // refresh/sync legitimately reads them while the device is locked, and ThisDeviceOnly so
    // sessions don't restore onto another device from an encrypted backup. Existing items are
    // upgraded in place because KeychainHelper.save includes kSecAttrAccessible in the
    // attributes passed to SecItemUpdate. The email item intentionally stays AfterFirstUnlock
    // without ThisDeviceOnly: it's needed for prefill/display (PII but not a credential).
    class var syncingV2Token: String? {
        get {
            try? KeychainHelper.string(for: ServerConstants.Values.syncingV2TokenKey)
        }

        set {
            KeychainHelper.save(string: newValue, key: ServerConstants.Values.syncingV2TokenKey, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
        }
    }

    class func refreshToken() throws -> String? {
        try KeychainHelper.string(for: ServerConstants.Values.refreshTokenKey)
    }

    class func setRefreshToken(_ newValue: String?) {
        KeychainHelper.save(string: newValue, key: ServerConstants.Values.refreshTokenKey, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }
}

// MARK: - Access Token Expiry

public extension ServerSettings {
    /// How far ahead of the server-reported expiry the client treats a token as dead,
    /// so a token isn't presented moments before it lapses (clock skew + in-flight time).
    private static let tokenExpirySkew: TimeInterval = 5.minutes
    private static let tokenExpiryDateKey = "SJTokenExpiryDate"

    /// Persists the access-token expiry hint from an authentication response.
    ///
    /// The stored date is `now + expiresIn - 5 minutes` of skew. This is a *hint* only —
    /// the 401 retry path remains the authority. Passing nil (server didn't send
    /// `expires_in`) clears any previously stored hint so it can't apply to a newer token.
    /// TTLs at or below the skew are treated as "no hint" rather than storing an
    /// already-past date, which would put every request through a refresh first.
    class func setTokenExpiry(expiresIn: Int?) {
        guard let expiresIn, TimeInterval(expiresIn) > tokenExpirySkew else {
            setTokenExpiryDate(nil)
            return
        }

        setTokenExpiryDate(Date(timeIntervalSinceNow: TimeInterval(expiresIn) - tokenExpirySkew))
    }

    class func tokenExpiryDate() -> Date? {
        UserDefaults.standard.object(forKey: tokenExpiryDateKey) as? Date
    }

    /// Internal seam (used by `setTokenExpiry(expiresIn:)` and tests).
    internal class func setTokenExpiryDate(_ date: Date?) {
        if let date {
            UserDefaults.standard.set(date, forKey: tokenExpiryDateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: tokenExpiryDateKey)
        }
    }

    /// The stored sync token, treating a past-expiry token as absent so callers refresh
    /// proactively instead of burning a request to collect the 401.
    internal class func validSyncingV2Token() -> String? {
        guard let token = try? KeychainHelper.string(for: ServerConstants.Values.syncingV2TokenKey) else {
            return nil
        }

        if let expiryDate = tokenExpiryDate(), expiryDate.timeIntervalSinceNow <= 0 {
            return nil
        }

        return token
    }
}

// MARK: - Auth Method Marker

/// How the account was signed in. A non-secret marker persisted in UserDefaults so UI can
/// branch on auth method without inferring it from the presence of a stored password
/// (which goes away under `FeatureFlag.refreshTokenForPasswordAuth`).
public enum AccountAuthMethod: String, Sendable {
    case password
    case sso
}

public extension ServerSettings {
    private static let accountAuthMethodKey = "SJAccountAuthMethod"

    class var accountAuthMethod: AccountAuthMethod? {
        get {
            UserDefaults.standard.string(forKey: accountAuthMethodKey).flatMap(AccountAuthMethod.init(rawValue:))
        }

        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: accountAuthMethodKey)
            } else {
                UserDefaults.standard.removeObject(forKey: accountAuthMethodKey)
            }
        }
    }
}
