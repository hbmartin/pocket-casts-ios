import Foundation
import PocketCastsDataModel
import PocketCastsServer

struct UserInfo {
    struct Profile {
        let isLoggedIn: Bool
        let displayName: String?
        let email: String?

        init(isLoggedIn: Bool = SyncManager.isUserLoggedIn(), email: String? = ServerSettings.syncingEmail(), displayName: String? = nil) {
            self.isLoggedIn = isLoggedIn
            self.email = isLoggedIn ? email : nil
            self.displayName = isLoggedIn ? displayName : nil // Placeholder, Not available yet
        }
    }

    struct Stats {
        /// The total number of podcasts the user is subscribed to
        let podcastCount: Int

        /// The total time the user has listened to podcasts
        let listeningTime: Stat

        /// The total time the user has saved from playback effects
        let savedTime: Stat

        init() {
            podcastCount = DataManager.sharedManager.podcastCount()
            listeningTime = .init(seconds: StatsManager.shared.totalListeningTimeInclusive())
            savedTime = .init(seconds: StatsManager.shared.totalSavedTime())
        }

        struct Stat {
            let seconds: TimeInterval
            let formatValues: Double.TimeFormatValueType

            init(seconds: TimeInterval) {
                self.seconds = seconds
                formatValues = seconds.timeFormatValues
            }
        }
    }
}
