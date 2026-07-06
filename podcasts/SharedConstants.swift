import Foundation

nonisolated enum SharedConstants {
    enum GroupUserDefaults {
        /// Resolved from the PCAppGroupIdentifier Info.plist key, which every app and
        /// extension target maps to the APP_GROUP_IDENTIFIER build setting. Keep the
        /// fallback in sync with APP_GROUP_IDENTIFIER in config/PocketCasts.base.xcconfig.
        public static let groupContainerId: String = {
            if let identifier = Bundle.main.object(forInfoDictionaryKey: "PCAppGroupIdentifier") as? String, !identifier.isEmpty {
                return identifier
            }
            return "group.au.com.shiftyjelly.pocketcasts"
        }()
        public static let upNextItems = "upNextItems"
        public static let upNextItemsCount = "upNextItemsCount"
        public static let siriSearchItems = "siriSearchItems"
        public static let topFilterName = "topFilterTitle"
        public static let topFilterItems = "topFilterItems"
        public static let isPlaying = "isPlaying"
        public static let appIcon = "appIcon"
    }

    enum PlaybackEffects {
        public static let maximumPlaybackSpeed = 3.0
        public static let minimumPlaybackSpeed = 0.5
    }
}
