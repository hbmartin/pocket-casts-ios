import Foundation

enum KeychainHelper {
    static func string(for key: String) throws -> String {
        key
    }
}

func savePushTokenToKeychain(_ token: String) -> Bool {
    !token.isEmpty
}

func migrateLegacyPushToken(legacyToken: String) {
    // ruleid: pocketcasts.keychain-redundant-read-after-save
    if savePushTokenToKeychain(legacyToken),
       (try? KeychainHelper.string(for: "SJPushToken")) == legacyToken {
        UserDefaults.standard.removeObject(forKey: "SJPushToken")
    }
}

func migrateLegacyPushTokenWithoutRedundantRead(legacyToken: String) {
    // ok: pocketcasts.keychain-redundant-read-after-save
    if savePushTokenToKeychain(legacyToken) {
        UserDefaults.standard.removeObject(forKey: "SJPushToken")
    }
}
