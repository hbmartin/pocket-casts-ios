import Dependencies
import Foundation
import PocketCastsUtils
import PocketCastsServer
import PocketCastsDataModel
import Synchronization

nonisolated enum NotificationType: String {

    case onboardingSignUp
    case onboardingImport
    case onboardingThemes
    case onboardingStaffPicks
    case onboardingUpNext
    case onboardingFilters

    case reengagementWeekly
    case reengagementDownloads

    case recommendationsTrending
    case recommendationsYouMightLike

    case newFeatureSuggestedFolders

    case highlightResurfacing

    var title: String {
        switch self {
        case .onboardingSignUp:
            return L10n.notificationsOnboardingSignupTitle
        case .onboardingImport:
            return L10n.notificationsOnboardingImportTitle
        case .onboardingThemes:
            return L10n.notificationsOnboardingThemesTitle
        case .onboardingUpNext:
            return L10n.notificationsOnboardingUpnextTitle
        case .onboardingFilters:
            return L10n.notificationsOnboardingFiltersTitle
        case .onboardingStaffPicks:
            return L10n.notificationsOnboardingStaffPicksTitle
        case .reengagementWeekly:
            return L10n.notificationsReengagementWeeklyTitle
        case .reengagementDownloads:
                return L10n.notificationsReengagementDownloadsTitle
        case .recommendationsTrending:
            return L10n.notificationsRecommendationsTrendingTitle
        case .recommendationsYouMightLike:
            return L10n.notificationsRecommendationsYouMightLikeTitle
        case .newFeatureSuggestedFolders:
            return L10n.notificationsNewFeatureSuggestedFoldersTitle
        case .highlightResurfacing:
            return L10n.notificationsHighlightResurfacingTitle
        }
    }

    var body: String {
        switch self {
        case .onboardingSignUp:
            return L10n.notificationsOnboardingSignupBody
        case .onboardingImport:
            return L10n.notificationsOnboardingImportBody
        case .onboardingThemes:
            return L10n.notificationsOnboardingThemesBody
        case .onboardingUpNext:
            return L10n.notificationsOnboardingUpnextBody
        case .onboardingFilters:
            return L10n.notificationsOnboardingFiltersBody
        case .onboardingStaffPicks:
            return L10n.notificationsOnboardingStaffPicksBody
        case .reengagementWeekly:
            return L10n.notificationsReengagementWeeklyBody
        case .reengagementDownloads:
            return L10n.notificationsReengagementDownloadsBody(NotificationsCoordinator.shared.numberOfDownloadsAvailable())
        case .recommendationsTrending:
            return L10n.notificationsRecommendationsTrendingBody
        case .recommendationsYouMightLike:
            return L10n.notificationsRecommendationsYouMightLikeBody
        case .newFeatureSuggestedFolders:
            return L10n.notificationsNewFeatureSuggestedFoldersBody
        case .highlightResurfacing:
            return NotificationsCoordinator.shared.resurfacedHighlightBody() ?? L10n.notificationsHighlightResurfacingBodyFallback
        }
    }

    var identifier: String {
        return self.rawValue
    }

    init?(requestIdentifier: String) {
        self.init(rawValue: requestIdentifier.components(separatedBy: ".").first ?? requestIdentifier)
    }

    var link: String {
        switch self {
        case .onboardingSignUp:
            return "thcast://signup"
        case .onboardingImport:
            return "thcast://settings/import"
        case .onboardingThemes:
            return "thcast://settings/themes"
        case .onboardingUpNext:
            return "thcast://upnext/?location=tab"
        case .onboardingFilters:
            return "thcast://filters"
        case .onboardingStaffPicks:
            return "thcast://discover/staff-picks"
        case .reengagementWeekly:
            return "thcast://discover"
        case .reengagementDownloads:
            return "thcast://profile/downloads"
        case .recommendationsTrending:
            return "thcast://discover/trending"
        case .recommendationsYouMightLike:
            return "thcast://discover/recommendations_user"
        case .newFeatureSuggestedFolders:
            return "thcast://features/suggestedFolders"
        case .highlightResurfacing:
            return "thcast://profile/bookmarks"
        }
    }

    var shouldSend: Bool {
        if !self.isRepeatable, Settings.notificationsLastTriggerDate[self.rawValue] != nil {
            return false
        }
        switch self {
            case .onboardingSignUp:
                return !SyncManager.isUserLoggedIn()
            case .recommendationsYouMightLike:
                return SyncManager.isUserLoggedIn()
            case .newFeatureSuggestedFolders:
                return Settings.suggestedFoldersUpsellCount < 2 && Settings.appVersion() == "7.90"
            case .reengagementDownloads:
                return NotificationsCoordinator.shared.numberOfDownloadsAvailable() > 0
            case .highlightResurfacing:
                // Only when there's something worth resurfacing.
                return NotificationsCoordinator.shared.resurfacedHighlightBody() != nil
            default:
                return true
        }
    }

    var isRepeatable: Bool {
        switch self {
            case .reengagementWeekly,
                 .reengagementDownloads,
                 .recommendationsTrending,
                 .recommendationsYouMightLike,
                 .highlightResurfacing:
                return true
            default:
                return false
        }
    }
}

nonisolated enum NotificationsGroup: CaseIterable {

    case newEpisodes
    case dailyReminders
    case recommendations
    case newFeaturesAndTips
    // Reserved to keep the offers notification preference stable.
    case offers
    /// Opt-in weekly resurfacing of an old highlight (Highlights program).
    case fromYourHighlights

    var notifications: [NotificationType] {
        switch self {
            case .newEpisodes:
                return [] // New Episodes are notifications sent by the server, so they don't need a local implementation
            case .dailyReminders:
                return [.onboardingSignUp, .onboardingImport, .onboardingUpNext, .onboardingFilters, .onboardingThemes, .onboardingStaffPicks]
            case .recommendations:
                return [.recommendationsTrending, .recommendationsYouMightLike]
            case .newFeaturesAndTips:
                return [.newFeatureSuggestedFolders, .reengagementWeekly, .reengagementDownloads]
            case .offers:
                return []
            case .fromYourHighlights:
                return [.highlightResurfacing]
        }
    }

    var scheduleHour: Int {
        switch self {
            case .newEpisodes:
                return 0 // This is determined by the server
            case .dailyReminders:
                return 10
            case .recommendations:
                return 11
            case .newFeaturesAndTips:
                return 16
            case .offers:
                // Reserved for possible future local offer notifications.
                return 14
            case .fromYourHighlights:
                return 18
        }
    }

    var isEnabled: Bool {
        switch self {
            case .newEpisodes:
                return Settings.notificationsNewEpisodes
            case .dailyReminders:
                return Settings.notificationsDailyReminders
            case .recommendations:
                return Settings.notificationsRecommendations
            case .newFeaturesAndTips:
                return Settings.notificationsNewFeaturesAndTips
            case .offers:
                return Settings.notificationsOffers
            case .fromYourHighlights:
                return Settings.notificationsFromYourHighlights
        }
    }

    /// Groups enabled as part of the app-wide notification permission flow.
    /// Highlight resurfacing remains an explicit, separate opt-in.
    var isEnabledByDefault: Bool {
        self != .fromYourHighlights
    }

    func setEnabled(_ newValue: Bool) {
        switch self {
            case .newEpisodes:
                if newValue {
                    // the user has just turned on push, enable it for all their podcasts for simplicity
                    @Dependency(\.podcastRepository) var podcastRepository
                    podcastRepository.setPushForAllPodcasts(pushEnabled: true)
                    NotificationsHelper.shared.registerForPushNotifications()
                } else {
                    RefreshManager.shared.refreshPodcasts(forceEvenIfRefreshedRecently: true)
                }
                Settings.notificationsNewEpisodes = newValue
            case .dailyReminders:
                Settings.notificationsDailyReminders = newValue
            case .recommendations:
                Settings.notificationsRecommendations = newValue
            case .newFeaturesAndTips:
                Settings.notificationsNewFeaturesAndTips = newValue
            case .offers:
                Settings.notificationsOffers = newValue
            case .fromYourHighlights:
                Settings.notificationsFromYourHighlights = newValue
        }
    }

    // Variable to be used only in debugging/testing to accelarate notifications schedule
    // nonisolated(unsafe): developer-menu debug knob; written only from the debug UI
    nonisolated(unsafe) static var speedUpNotifications: Bool = false

    var timeIntervalStep: TimeInterval {
        switch self {
            case .newEpisodes:
                return 0
            case .dailyReminders:
                return Self.speedUpNotifications ? 10.seconds: 24.hours
            case .recommendations:
                return Self.speedUpNotifications ? 60.seconds: 3.days
            case .newFeaturesAndTips:
                return Self.speedUpNotifications ? 60.seconds: 1.week
            case .offers:
                // Reserved for possible future local offer notifications.
                return Self.speedUpNotifications ? 120.seconds: 2.week
            case .fromYourHighlights:
                return Self.speedUpNotifications ? 60.seconds: 1.week
        }
    }

    func trigger(order: Int, notification: NotificationType) -> UNNotificationTrigger? {
        if Self.speedUpNotifications {
            return UNTimeIntervalNotificationTrigger(
                timeInterval: Double(order + 1) * timeIntervalStep,
                repeats: notification.isRepeatable && notification != .highlightResurfacing
            )
        }
        let calendar = Calendar.current
        let maxWeekDays: Int = calendar.weekdaySymbols.count
        switch self {
            case .newEpisodes:
                return nil
            case .dailyReminders:
                let timeIntervalToSchedule: TimeInterval = calculateTimeIntervalToHour(scheduleHour)
                return UNTimeIntervalNotificationTrigger(timeInterval: timeIntervalToSchedule + (Double(order) * timeIntervalStep), repeats: notification.isRepeatable)
            case .recommendations:
                return makeTrigger(
                    days: (order + 1) * 3,
                    from: .now,
                    calendar: calendar,
                    repeats: notification.isRepeatable
                )

            case .newFeaturesAndTips:
                return makeTrigger(
                    days: (order + 1) * 2,
                    from: .now,
                    calendar: calendar,
                    repeats: notification.isRepeatable
                )

            case .offers:
                return makeTrigger(
                    days: maxWeekDays - order - 1,
                    from: .now,
                    calendar: calendar,
                    repeats: notification.isRepeatable
                )

            case .fromYourHighlights:
                return makeOneShotTrigger(
                    days: (order + 1) * maxWeekDays,
                    from: .now,
                    calendar: calendar
                )
        }
    }

    private func makeTrigger(days: Int, from date: Date = .now, calendar: Calendar, repeats: Bool) -> UNCalendarNotificationTrigger? {
        guard let fireDate = calendar.date(byAdding: .day, value: days, to: date) else {
            return nil
        }

        let weekday = calendar.component(.weekday, from: fireDate)
        let components = DateComponents(hour: scheduleHour, weekday: weekday)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
    }

    private func makeOneShotTrigger(days: Int, from date: Date, calendar: Calendar) -> UNCalendarNotificationTrigger? {
        guard let targetDay = calendar.date(byAdding: .day, value: days, to: date),
              let fireDate = calendar.date(bySettingHour: scheduleHour, minute: 0, second: 0, of: targetDay) else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    static var allDisabled: Bool {
        Self.allCases.allSatisfy() {
            $0.isEnabled == false
        }
    }

    private func calculateTimeIntervalToHour(_ hour: Int) -> TimeInterval {
        if Self.speedUpNotifications {
            return 1
        }
        guard let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date.now, matchingPolicy: .nextTime),
              let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: date)
        else {
            return 0
        }
        return nextDate.timeIntervalSince(Date.now)
    }
}

/// State is an immutable (thread-safe) UNUserNotificationCenter plus a lock-backed debug toggle.
/// @unchecked Sendable: notificationCenter is immutable and thread-safe; debugMode is protected by Mutex.
nonisolated final class NotificationsCoordinator: @unchecked Sendable {

    static let shared = NotificationsCoordinator()

    private let debugModeState = Mutex(false)
    var debugMode: Bool {
        get { debugModeState.withLock { $0 } }
        set { debugModeState.withLock { $0 = newValue } }
    }

    private let notificationCenter: UNUserNotificationCenter
    private static let highlightScheduleCount = 8

    private init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    @discardableResult
    func requestAndSetupInitialPermissions() async -> Bool {
        await withCheckedContinuation { continuation in
            NotificationsHelper.shared.registerForPushNotifications() { granted in
                guard granted else {
                    continuation.resume(returning: false)
                    return
                }
                // Activate the default groups. Highlight resurfacing has its
                // own explicit opt-in in Highlights settings.
                for group in NotificationsGroup.allCases where group.isEnabledByDefault {
                    self.setupNotifications(for: group)
                }
                continuation.resume(returning: granted)
            }
        }
    }

    func setupNotifications(for group: NotificationsGroup) {
        group.setEnabled(true)
        NotificationsHelper.shared.enablePush()
        NotificationsHelper.shared.registerForPushNotifications { [weak self] granted in
            guard let self, granted else { return }
            updateNotifications(for: group)
        }
    }

    func updateNotifications(for group: NotificationsGroup) {
        cancelNotifications(for: group)

        if group == .fromYourHighlights {
            let bodies = resurfacedHighlightBodies(limit: Self.highlightScheduleCount)
            for (order, body) in bodies.enumerated() {
                guard let trigger = group.trigger(order: order, notification: .highlightResurfacing) else { continue }
                scheduleNotification(
                    .highlightResurfacing,
                    identifier: "\(NotificationType.highlightResurfacing.identifier).\(order)",
                    body: body,
                    trigger: trigger
                )
            }
            printPendingNotifications()
            return
        }

        var order = 0
        for notification in group.notifications {
            guard notification.shouldSend,
                  let trigger = group.trigger(order: order, notification: notification)
            else {
                continue
            }
            scheduleNotification(notification, trigger: trigger)
            order += 1
        }
        printPendingNotifications()
    }

    /// Replenishes an exhausted highlight batch without postponing requests
    /// that are already pending every time the app launches.
    func refreshHighlightNotificationsIfNeeded() {
        guard NotificationsGroup.fromYourHighlights.isEnabled else { return }
        guard FeatureFlag.highlightEditor.enabled else {
            cancelNotifications(for: .fromYourHighlights)
            return
        }

        Task {
            let requests = await notificationCenter.pendingNotificationRequests()
            let hasPendingHighlight = requests.contains {
                NotificationType(requestIdentifier: $0.identifier) == .highlightResurfacing
            }
            guard !hasPendingHighlight else { return }
            updateNotifications(for: .fromYourHighlights)
        }
    }

    private func printPendingNotifications() {
        guard debugMode else {
            return
        }
        Task {
            FileLog.shared.addMessage("\n---- Notification Schedule ----\n")
            let pendingNotifications = await self.notificationCenter.pendingNotificationRequests()
            for notificationRequest in pendingNotifications {
                if let calendarTrigger = notificationRequest.trigger as? UNCalendarNotificationTrigger {
                    let date = calendarTrigger.nextTriggerDate() ?? Date()
                    FileLog.shared.addMessage("Notification: \(notificationRequest.identifier) - \(date.formatted())\n")
                }
                if let intervalTrigger = notificationRequest.trigger as? UNTimeIntervalNotificationTrigger {
                    let date = intervalTrigger.nextTriggerDate() ?? Date()
                    FileLog.shared.addMessage("Notification: \(notificationRequest.identifier) - \(date.formatted())\n")
                }
            }
            FileLog.shared.addMessage("\n---- End ----\n")
        }
    }

    func disableNotifications(for group: NotificationsGroup) {
        group.setEnabled(false)
        cancelNotifications(for: group)
        if NotificationsGroup.allDisabled {
            NotificationsHelper.shared.disablePush()
        }
    }

    func scheduleNotification(
        _ type: NotificationType,
        identifier: String? = nil,
        body: String? = nil,
        trigger: UNNotificationTrigger
    ) {
        let content = UNMutableNotificationContent()
        content.title = type.title
        content.body = body ?? type.body
        content.categoryIdentifier = NotificationsHelper.NotificationsCategory.deepLink.rawValue
        content.userInfo = ["destination_url": type.link]

        let request = UNNotificationRequest(identifier: identifier ?? type.identifier, content: content, trigger: trigger)

        // Schedule the request with the system. The request is freshly built and
        // handed over wholesale.
        let boxedRequest = PocketCastsUtils.UncheckedSendable(request)
        Task {
            do {
                try await notificationCenter.add(boxedRequest.value)
            } catch {
                // Handle errors that may occur during add.
                FileLog.shared.addMessage("[Notifications Coordinator] Error adding notification: \(error)")
            }
        }
    }

    func markNotification(_ notification: NotificationType) {
        var notificationDates = Settings.notificationsLastTriggerDate
        notificationDates[notification.rawValue] = Date.now
        Settings.notificationsLastTriggerDate = notificationDates
    }

    func cancelNotifications(for group: NotificationsGroup) {
        var identifiers = group.notifications.map { $0.identifier }
        if group == .fromYourHighlights {
            identifiers.append(contentsOf: (0..<Self.highlightScheduleCount).map {
                "\(NotificationType.highlightResurfacing.identifier).\($0)"
            })
        }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        printPendingNotifications()
    }

    func cancelNotification(_ type: NotificationType) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [type.identifier])
    }

    private let episodesDataManager = EpisodesDataManager()

    func numberOfDownloadsAvailable() -> Int {
        episodesDataManager.downloadedEpisodes().reduce(0) { partialResult, list in
            return partialResult + list.elements.count
        }
    }

    /// The resurfacing notification's body (Highlights program): a highlight
    /// at least a week old, chosen pseudo-randomly per day so repeat schedules
    /// don't pin the same one. nil = nothing old enough to resurface.
    func resurfacedHighlightBody() -> String? {
        resurfacedHighlightBodies(limit: 1).first
    }

    /// Builds a batch of one-shot weekly messages. Each request owns its body,
    /// so the system does not repeat one captured highlight forever.
    func resurfacedHighlightBodies(limit: Int) -> [String] {
        guard FeatureFlag.highlightEditor.enabled else { return [] }

        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let eligible = DataManager.sharedManager.bookmarks
            .allBookmarks(includeDeleted: false)
            .filter { $0.created < cutoff }
        guard !eligible.isEmpty, limit > 0 else { return [] }

        let dayIndex = Int(Date().timeIntervalSince1970 / 86_400)
        let ordered = eligible.sorted {
            if $0.created != $1.created { return $0.created < $1.created }
            return $0.uuid < $1.uuid
        }
        let start = dayIndex % ordered.count

        return (0..<limit).map { offset in
            let pick = ordered[(start + offset) % ordered.count]
            if let excerpt = pick.excerpt, !excerpt.isEmpty {
                return "\u{201C}\(excerpt.prefix(120))\u{201D}"
            }
            return pick.title
        }
    }
}
