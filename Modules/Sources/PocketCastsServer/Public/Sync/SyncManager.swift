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
        NotificationCenter.postOnMainThread(UserWillBeSignedOut(userInitiated: userInitiated))

        // Best-effort server-side revocation must read the tokens before they're wiped.
        revokeRefreshTokenOnServer()

        clearTokensFromKeyChain()
        FileLog.shared.addMessage("SyncManager.signout clearTokensFromKeyChain")

        ServerSettings.setSyncingEmail(email: nil)
        ServerSettings.userId = nil
        ServerSettings.setTokenExpiry(expiresIn: nil)
        ServerSettings.accountAuthMethod = nil

        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.lastModifiedServerDate)
        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.upNextServerLastModified)
        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.historyServerLastModified)
        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.marketingOptInNeedsSyncKey)
        UserDefaults.standard.removeObject(forKey: ServerConstants.UserDefaults.marketingOptInKey)
        UserDefaults.standard.synchronize()
    }

    public class func clearTokensFromKeyChain() {
        // SJSyncingPwd is wiped forever, even after refresh-token auth removes the last
        // writer — it cleans up stragglers migrated from older releases.
        KeychainHelper.removeKey(ServerConstants.Values.syncingEmailKey)
        KeychainHelper.removeKey(ServerConstants.Values.syncingLoginItemName)
        KeychainHelper.removeKey(ServerConstants.Values.syncingV2TokenKey)
        KeychainHelper.removeKey(ServerConstants.Values.refreshTokenKey)
        KeychainHelper.removeKey(ServerConstants.Values.appleAuthUserIDKey)
    }

    /// Fire-and-forget `POST user/token/revoke` so a backup-restored or exfiltrated refresh
    /// token doesn't outlive the sign-out (plan §2.3.3). Best-effort by design: sign-out
    /// must never block on the network, and a 404 is tolerated until the endpoint ships
    /// with the M1 server contract.
    private class func revokeRefreshTokenOnServer() {
        guard FeatureFlag.refreshTokenForPasswordAuth.enabled,
              let refreshToken = try? ServerSettings.refreshToken(), !refreshToken.isEmpty
        else {
            return
        }

        let url = ServerHelper.asUrl(ServerConstants.Urls.api() + "user/token/revoke")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15.seconds)
        request.httpMethod = "POST"
        request.addValue("application/octet-stream", forHTTPHeaderField: ServerConstants.HttpHeaders.accept)
        request.setValue("application/octet-stream", forHTTPHeaderField: ServerConstants.HttpHeaders.contentType)
        if let accessToken = try? KeychainHelper.string(for: ServerConstants.Values.syncingV2TokenKey), !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: ServerConstants.HttpHeaders.authorization)
        }
        request.httpBody = tokenRevokeRequestBody(refreshToken: refreshToken)

        URLSession.shared.dataTask(with: request) { _, response, _ in
            // Status marker only — never log token material.
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            FileLog.shared.addMessage("SyncManager.signout token revoke request finished, status: \(statusCode)")
        }.resume()
    }

    /// Protobuf wire encoding of `TokenRevokeRequest { string refresh_token = 1; }`
    /// (field 1, wire type LEN). Hand-encoded because the client stubs haven't been
    /// regenerated for the M1 contract yet; replace with the generated
    /// `Api_TokenRevokeRequest` once `mise run generate:proto` runs against the M1 API.
    static func tokenRevokeRequestBody(refreshToken: String) -> Data {
        let utf8 = Array(refreshToken.utf8)
        var body = Data([0x0A])
        var length = UInt(utf8.count)
        repeat {
            var byte = UInt8(length & 0x7F)
            length >>= 7
            if length > 0 { byte |= 0x80 }
            body.append(byte)
        } while length > 0
        body.append(contentsOf: utf8)
        return body
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
