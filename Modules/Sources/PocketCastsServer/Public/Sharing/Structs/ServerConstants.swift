import Foundation

public enum ServerConstants {
    public enum Urls {
        struct Endpoints: Equatable {
            let main: String
            let api: String
            let cache: String
            let sharing: String
            let discover: String
            let image: String
            let share: String
            let lists: String
            let search: String
            let generatedTranscripts: String
            let tvPair: String
            let tvCreate: String
        }

        private static var currentEndpoints: Endpoints {
            resolvedEndpoints(
                production: production(),
                localBaseURL: ServerOriginPolicy.shared.origin?.absoluteString
            )
        }

        static func resolvedEndpoints(production: Bool, localBaseURL: String?) -> Endpoints {
            let hosted = if production {
                Endpoints(
                    main: "https://refresh.pocketcasts.com/",
                    api: "https://api.pocketcasts.com/",
                    cache: "https://cache.pocketcasts.com/",
                    sharing: "https://sharing.pocketcasts.com/",
                    discover: "https://static.pocketcasts.com/discover/",
                    image: "https://static.pocketcasts.com/",
                    share: "https://pca.st/",
                    lists: "https://lists.pocketcasts.com/",
                    search: "https://search.pocketcasts.com/",
                    generatedTranscripts: "https://shownotes.pocketcasts.com/generated_transcripts/",
                    tvPair: "https://pocketcasts.com/pair",
                    tvCreate: "https://pocketcasts.com/create"
                )
            } else {
                Endpoints(
                    main: "https://refresh.pocketcasts.net/",
                    api: "https://api.pocketcasts.net/",
                    cache: "https://podcast-api.pocketcasts.net/",
                    sharing: "https://sharing.pocketcasts.net/",
                    discover: "https://static.pocketcasts.net/discover/",
                    image: "https://static.pocketcasts.net/",
                    share: "https://pcast.pocketcasts.net/",
                    lists: "https://lists.pocketcasts.net/",
                    search: "https://search.pocketcasts.net/",
                    generatedTranscripts: "https://shownotes.pocketcasts.net/generated_transcripts/",
                    tvPair: "https://pocketcasts.net/pair",
                    tvCreate: "https://pocketcasts.net/create"
                )
            }

            guard let baseURL = normalizedLocalBaseURL(localBaseURL) else {
                return hosted
            }

            return Endpoints(
                main: baseURL,
                api: baseURL,
                cache: baseURL,
                sharing: baseURL,
                discover: baseURL + "discover/",
                image: baseURL,
                share: baseURL,
                lists: baseURL,
                search: baseURL,
                generatedTranscripts: baseURL + "generated_transcripts/",
                tvPair: hosted.tvPair,
                tvCreate: hosted.tvCreate
            )
        }

        static func normalizedLocalBaseURL(_ value: String?) -> String? {
            ServerOriginPolicy.normalizedOrigin(value, allowInsecureLoopback: true)
        }

        public static func main() -> String {
            currentEndpoints.main
        }

        public static func api() -> String {
            currentEndpoints.api
        }

        public static func cache() -> String {
            currentEndpoints.cache
        }

        public static func sharing() -> String {
            currentEndpoints.sharing
        }

        public static func discover() -> String {
            currentEndpoints.discover
        }

        public static func image() -> String {
            currentEndpoints.image
        }

        public static func share() -> String {
            currentEndpoints.share
        }

        public static func lists() -> String {
            currentEndpoints.lists
        }

        public static var search: String {
            currentEndpoints.search
        }

        public static var generatedTranscripts: String {
            currentEndpoints.generatedTranscripts
        }

        public static var tvPair: String {
            currentEndpoints.tvPair
        }

        public static var tvCreate: String {
            currentEndpoints.tvCreate
        }

        // Fork-owned transcript contribution endpoints (docs/TranscriptContributions.md §3).
        public static var transcriptContributeUrl: String {
            "\(api())transcripts/contribute"
        }

        public static var transcriptSightingUrl: String {
            "\(api())transcripts/sighting"
        }

        // Fork-owned App Attest endpoints (docs/AppAttest.md §1).
        public static var attestChallengeUrl: String {
            "\(api())attest/challenge"
        }

        public static var attestEnrollUrl: String {
            "\(api())attest/enroll"
        }

        public static let support = "https://support.pocketcasts.com/ios/"
        public static let termsOfUse = "https://support.pocketcasts.com/article/terms-of-use/"
        public static let privacyPolicy = "https://support.pocketcasts.com/article/privacy-policy/"
        public static let pocketcastsDotCom = "https://pocketcasts.com/"
        public static let automatticDotCom = "https://automattic.com/"
        public static let automatticWorkWithUs = "https://automattic.com/work-with-us/"
        public static let appStore = "https://apps.apple.com/app/id414834813"
        public static let podrollLearnMore = "https://support.pocketcasts.com/knowledge-base/podroll/"
        public static let supportPlaybackDownloadErrors = "https://support.pocketcasts.com/knowledge-base/download-and-playback-errors/"
        public static let supportEpisodeAccessIssues = "https://support.pocketcasts.com/knowledge-base/episode-access-issues/"
        public static let supportEpisodeNotFound = "https://support.pocketcasts.com/knowledge-base/episode-not-found/"
        public static let supportEpisodeServerProblem = "https://support.pocketcasts.com/knowledge-base/episode-server-problem/"
    }

    private static func production() -> Bool {
        guard let delegate = ServerConfig.shared.syncDelegate else {
            return true
        }
        return delegate.production()
    }

    public enum HttpConstants {
        public static let ok = 200
        public static let accepted = 202
        public static let notModified = 304
        public static let unauthorized = 401
        public static let forbidden = 403
        public static let notFound = 404
        public static let tooManyRequests = 429
        public static let serverError = 500
        public static let badRequest = 400
        public static let conflict = 409
        public static let unprocessableEntity = 422
        public static let serviceUnavailable = 503
    }

    public enum HttpHeaders {
        public static let lastModified = "Last-Modified"
        public static let ifModifiedSince = "If-Modified-Since"
        public static let ifNoneMatch = "If-None-Match"
        public static let contentType = "Content-Type"
        public static let accept = "Accept"
        public static let userAgent = "User-Agent"
        public static let authorization = "Authorization"
        public static let expires = "Expires"
        public static let cacheControl = "Cache-Control"
        public static let date = "Date"
        public static let etag = "ETag"
        public static let userRegion = "X-User-Region"
        public static let appLanguage = "X-App-Language"
        public static let installationID = "X-Installation-ID"
    }

    public enum Timeouts {
        static let sync = 60 as TimeInterval
        static let general = 60 as TimeInterval
        static let cache = 30 as TimeInterval
    }

    public enum Values {
        static let apiScope = "mobile"
        static let deviceTypeiOS: Int32 = 1
        static let syncingEmailKey = "SJSyncingEmail"
        static let syncingLoginItemName = "SJSyncingPwd" // NOSONAR - Legacy Keychain item name, not a credential value.
        static let syncingV2TokenKey = "SJSyncV2Token"
        static let refreshTokenKey = "SJRefreshToken"
        static let pushTokenKey = "SJPushToken" // NOSONAR - Keychain item name, not a credential.
        static let appleAuthUserIDKey = "SJAppleAuthUserID"
        public static let appUserAgent = "Pocket Casts"
        static let oldEpisodeCutoff = 2.weeks
    }

    public enum UserDefaults {
        static let lastModifiedServerDate = "PCLastModifiedServerDate"
        static let lastSyncStartDate = "PCLastSyncStartDate"
        static let lastRefreshStartTime = "LastRefreshStartTime"
        static let lastRefreshEndTime = "SJLastRefreshDate"
        static let lastSyncTime = "SJLastSyncDate"
        static let syncingEmailLegacy = "SJSyncingEmail"
        static let historyServerLastModified = "SJHistoryServerLastModified"
        static let upNextServerLastModified = "SJUpNextServerLastModified"
        static let lastClearHistoryDate = "SJLastClearHistoryDate"
        static let pushToken = "SJPushToken"
        public static let marketingOptInKey = "SJMarketingOptIn"
        static let marketingOptInNeedsSyncKey = "SJMarketingOptInNeedsSync"
        static let statsStartDate = "StatsStartDate"
        static let statsSyncStatus = "StatsSyncStatus"
        static let statsDynamicSpeedSeconds = "StatsDynamicSpeed"
        static let statsVariableSpeed = "StatsVariableSpeed"
        static let statsListenedTo = "StatsListenedTo"
        static let statsSkipped = "StatsSkipped"
        static let statsAutoSkip = "StatsIntroSKip"
        static let statsDynamicSpeedSecondsServer = "StatsDynamicSpeedServer"
        static let statsVariableSpeedServer = "StatsVariableSpeedServer"
        static let statsListenedToServer = "StatsListenedToServer"
        static let statsSkippedServer = "StatsSkippedServer"
        static let statsAutoSkipServer = "StatsIntroSkipServer"
        static let statsStartedDateServer = "StatsStartedDateServer"
        static let userId = "UserId"
    }

    public enum Limits {
        static let maxHistoryItems = 100
        static let maxEpisodesToSync = 2000
    }
}
