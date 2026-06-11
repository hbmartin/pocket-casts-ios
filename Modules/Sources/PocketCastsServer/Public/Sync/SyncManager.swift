import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import UIKit

public class SyncManager {
    public class func isUserLoggedIn() -> Bool {
        if let email = ServerSettings.syncingEmail(), !email.isEmpty {
            return true
        }
        return false
    }

    public class func isFirstSyncInProgress() -> Bool {
        let lastSyncStartDate = UserDefaults.standard.string(forKey: ServerConstants.UserDefaults.lastSyncStartDate)
        let lastModifiedServerDate = UserDefaults.standard.string(forKey: ServerConstants.UserDefaults.lastModifiedServerDate)

        return (lastSyncStartDate != nil && lastModifiedServerDate == nil)
    }

    public class func isRefreshInProgress() -> Bool {
        guard let lastRefreshStartDate = UserDefaults.standard.object(forKey: ServerConstants.UserDefaults.lastRefreshStartTime) as? Date else {
            return false
        }
        guard let lastRefreshEndDate = UserDefaults.standard.object(forKey: ServerConstants.UserDefaults.lastRefreshEndTime) as? Date else {
            return true
        }
        return lastRefreshStartDate.compare(lastRefreshEndDate) == .orderedDescending
    }

    /// Signs the user out
    /// - Parameter userInitiated: Whether the user initiated the sign out or not
    public class func signout(userInitiated: Bool = false) {
        FileLog.shared.addMessage("SyncManager.signout – userInitiated: \(userInitiated)")

        // Notify any listeners that the user login state will be changing
        NotificationCenter.postOnMainThread(notification: .serverUserWillBeSignedOut, userInfo: ["user_initiated": userInitiated])

        clearTokensFromKeyChain()
        FileLog.shared.addMessage("SyncManager.signout clearTokensFromKeyChain")

        ServerSettings.setSyncingEmail(email: nil)
        ServerSettings.userId = nil

        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.lastModifiedServerDate)
        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.upNextServerLastModified)
        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.historyServerLastModified)
        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.marketingOptInNeedsSyncKey)
        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.marketingOptInKey)
        ServerSettings.liveAnalyticsUrl = nil
        UserDefaults.standard.synchronize()

        ServerConfig.shared.syncDelegate?.cleanupCloudOnlyFiles()
    }

    public class func clearTokensFromKeyChain() {
        KeychainHelper.removeKey(ServerConstants.Values.syncingEmailKey)
        KeychainHelper.removeKey(ServerConstants.Values.syncingLoginItemName)
        KeychainHelper.removeKey(ServerConstants.Values.syncingV2TokenKey)
        KeychainHelper.removeKey(ServerConstants.Values.refreshTokenKey)
        KeychainHelper.removeKey(ServerConstants.Values.appleAuthUserIDKey)
    }
}

// MARK: - Sync Reason
public extension SyncManager {
    enum SyncingReason: String {
        case accountCreated
        case login
        case replace
        case remove
        case add
    }

    /// Defines a reason why a sync is being performed
    // nonisolated(unsafe): advisory flag set before a sync starts and cleared when it
    // completes; readers tolerate a stale value.
    nonisolated(unsafe) static var syncReason: SyncManager.SyncingReason? = nil
}
