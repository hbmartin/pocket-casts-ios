import Foundation

enum Constants {
    static let passwordKey = "accountPassword"
    static let refreshTokenKey = "refreshToken"
    static let apiKey = "apiKey"
    static let homeGridSortOrderKey = "SJPodcastLibrarySort"
    static let marketingOptInNeedsSyncKey = "SJMarketingOptInNeedsSync"
    static let filesLastModifiedKey = "UserFilesLastModified"
    static let cleanupInProgress = "CleanupInProgress"
    static let podcastGroupingDefaultKey = "PodcastGroupingDefault"
    static let pinCodeKey = "PinCode"
}

enum ServerConstants {
    enum UserDefaults {
        static let pushToken = "SJPushToken"
    }
}

func storesCredentials(accessToken: String, password: String, refreshToken: String, apiKey: String) {
    // ruleid: insecure_storage
    UserDefaults.standard.set(accessToken, forKey: "accessToken")

    // ruleid: insecure_storage
    UserDefaults.standard.set(password, forKey: Constants.passwordKey)

    // ruleid: insecure_storage
    NSUserDefaults.standardUserDefaults().setObject(refreshToken, forKey: Constants.refreshTokenKey)

    // ruleid: insecure_storage
    UserDefaults.standard.set(apiKey, forKey: Constants.apiKey)

    // ruleid: insecure_storage
    UserDefaults.standard.set("1234", forKey: Constants.pinCodeKey)
}

func storesPreferences(order: Int, optedIn: Bool, lastModified: String, pushToken: String) {
    // ok: insecure_storage
    UserDefaults.standard.set(order, forKey: Constants.homeGridSortOrderKey)

    // ok: insecure_storage
    UserDefaults.standard.set(optedIn, forKey: Constants.marketingOptInNeedsSyncKey)

    // ok: insecure_storage
    UserDefaults.standard.set(lastModified, forKey: Constants.filesLastModifiedKey)

    // ok: insecure_storage
    UserDefaults.standard.set(true, forKey: Constants.cleanupInProgress)

    // ok: insecure_storage
    UserDefaults.standard.set(order, forKey: Constants.podcastGroupingDefaultKey)

    // ok: insecure_storage
    UserDefaults.standard.set(pushToken, forKey: ServerConstants.UserDefaults.pushToken)
}

func storesValueWithGenericKey(value: TimeInterval, key: String) {
    // ok: insecure_storage
    UserDefaults.standard.set(value, forKey: key)
}

// ruleid: pocketcasts.no-sentry-or-automattic-tracks
import Sentry
