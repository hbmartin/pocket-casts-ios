import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import Synchronization

public final class StatsManager: Sendable {
    public static let shared = StatsManager()

    private struct Stats: Sendable {
        var savedDynamicSpeed: TimeInterval
        var savedVariableSpeed: TimeInterval
        var totalListenedTo: TimeInterval
        var totalSkipped: TimeInterval
        var savedAutoSkipping: TimeInterval
        var isSynced = true
    }

    private let stats: Mutex<Stats>
    private let persistenceQueue: DispatchQueue
    private let userDefaults: UserDefaults

    public convenience init() {
        self.init(userDefaults: .standard)
    }

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        persistenceQueue = DispatchQueue(label: "au.com.pocketcasts.StatsManagerPersistenceQueue")

        if userDefaults.object(forKey: ServerConstants.UserDefaults.statsStartDate) as? Date == nil {
            userDefaults.set(Date(), forKey: ServerConstants.UserDefaults.statsStartDate)
            userDefaults.synchronize()
        }

        stats = Mutex(Stats(
            savedDynamicSpeed: userDefaults.double(forKey: ServerConstants.UserDefaults.statsDynamicSpeedSeconds),
            savedVariableSpeed: userDefaults.double(forKey: ServerConstants.UserDefaults.statsVariableSpeed),
            totalListenedTo: userDefaults.double(forKey: ServerConstants.UserDefaults.statsListenedTo),
            totalSkipped: userDefaults.double(forKey: ServerConstants.UserDefaults.statsSkipped),
            savedAutoSkipping: userDefaults.double(forKey: ServerConstants.UserDefaults.statsAutoSkip)
        ))
    }

    func updateStatsIfNeeded(savedDynamicSpeed: TimeInterval, savedVariableSpeed: TimeInterval, totalListenedTo: TimeInterval, totalSkipped: TimeInterval, savedAutoSkipping: TimeInterval) {
        let minimumStatsChangeToUpdate: TimeInterval = 100

        stats.withLock { stats in
            if savedDynamicSpeed - stats.savedDynamicSpeed > minimumStatsChangeToUpdate {
                FileLog.shared.addMessage("[StatsManager] Changing savedDynamicSpeed from \(stats.savedDynamicSpeed) to \(savedDynamicSpeed)")
                stats.savedDynamicSpeed = savedDynamicSpeed
            }

            if savedVariableSpeed - stats.savedVariableSpeed > minimumStatsChangeToUpdate {
                FileLog.shared.addMessage("[StatsManager] Changing savedVariableSpeed from \(stats.savedVariableSpeed) to \(savedVariableSpeed)")
                stats.savedVariableSpeed = savedVariableSpeed
            }

            if totalListenedTo - stats.totalListenedTo > minimumStatsChangeToUpdate {
                FileLog.shared.addMessage("[StatsManager] Changing totalListenedTo from \(stats.totalListenedTo) to \(totalListenedTo)")
                stats.totalListenedTo = totalListenedTo
            }

            if totalSkipped - stats.totalSkipped > minimumStatsChangeToUpdate {
                FileLog.shared.addMessage("[StatsManager] Changing totalSkipped from \(stats.totalSkipped) to \(totalSkipped)")
                stats.totalSkipped = totalSkipped
            }

            if savedAutoSkipping - stats.savedAutoSkipping > minimumStatsChangeToUpdate {
                FileLog.shared.addMessage("[StatsManager] Changing savedAutoSkipping from \(stats.savedAutoSkipping) to \(savedAutoSkipping)")
                stats.savedAutoSkipping = savedAutoSkipping
            }

            enqueuePersistence(stats)
        }
    }

    // MARK: - dynamic speed

    public func timeSavedDynamicSpeed() -> TimeInterval {
        stats.withLock { $0.savedDynamicSpeed }
    }

    public func addTimeSavedDynamicSpeed(_ seconds: TimeInterval) {
        stats.withLock {
            $0.savedDynamicSpeed += max(seconds, 0)
            $0.isSynced = false
        }
    }

    // MARK: - variable speed

    public func timeSavedVariableSpeed() -> TimeInterval {
        stats.withLock { $0.savedVariableSpeed }
    }

    public func addTimeSavedVariableSpeed(_ seconds: TimeInterval) {
        stats.withLock {
            $0.savedVariableSpeed += max(seconds, 0)
            $0.isSynced = false
        }
    }

    // MARK: - total listened

    public func totalListeningTime() -> TimeInterval {
        stats.withLock { $0.totalListenedTo }
    }

    public func addTotalListeningTime(_ seconds: TimeInterval) {
        stats.withLock {
            $0.totalListenedTo += max(seconds, 0)
            $0.isSynced = false
        }
    }

    // MARK: - total skipped

    public func totalSkippedTime() -> TimeInterval {
        stats.withLock { $0.totalSkipped }
    }

    public func addSkippedTime(_ seconds: TimeInterval) {
        stats.withLock {
            $0.totalSkipped += max(seconds, 0)
            $0.isSynced = false
        }
    }

    // MARK: - total auto skipped

    public func totalAutoSkippedTime() -> TimeInterval {
        stats.withLock { $0.savedAutoSkipping }
    }

    public func addAutoSkipTime(_ seconds: TimeInterval) {
        stats.withLock {
            $0.savedAutoSkipping += max(seconds, 0)
            $0.isSynced = false
        }
    }

    // MARK: - General

    /**
     * To conserve battery we want to keep these stats in memory. When it makes sense to, call this
     * method to actually save them between app launches.
     */
    public func persistTimes() {
        stats.withLock { enqueuePersistence($0) }
    }

    private func enqueuePersistence(_ stats: Stats) {
        persistenceQueue.async { [self] in
            persist(stats)
        }
    }

    private func persist(_ stats: Stats) {
        saveTime(stats.savedDynamicSpeed, key: ServerConstants.UserDefaults.statsDynamicSpeedSeconds)
        saveTime(stats.savedVariableSpeed, key: ServerConstants.UserDefaults.statsVariableSpeed)
        saveTime(stats.totalListenedTo, key: ServerConstants.UserDefaults.statsListenedTo)
        saveTime(stats.totalSkipped, key: ServerConstants.UserDefaults.statsSkipped)
        saveTime(stats.savedAutoSkipping, key: ServerConstants.UserDefaults.statsAutoSkip)

        userDefaults.set(stats.isSynced, forKey: ServerConstants.UserDefaults.statsSyncStatus)
        userDefaults.synchronize()
    }

    public func syncStatus() -> SyncStatus {
        let isSynced = userDefaults.bool(forKey: ServerConstants.UserDefaults.statsSyncStatus)

        return isSynced ? SyncStatus.synced : SyncStatus.notSynced
    }

    public func setSyncStatus(_ syncStatus: SyncStatus) {
        let isSynced = (syncStatus == SyncStatus.synced)

        userDefaults.set(isSynced, forKey: ServerConstants.UserDefaults.statsSyncStatus)
    }

    // MARK: - Remote Stats

    public func loadRemoteStats(completion: ((Bool) -> Void)?) {
        ApiServerHandler.shared.loadStatsRequest { [weak self] remoteStats in
            guard let strongSelf = self, let remoteStats else { return }

            strongSelf.saveTime(remoteStats.silenceRemovalTime, key: ServerConstants.UserDefaults.statsDynamicSpeedSecondsServer)
            strongSelf.saveTime(remoteStats.totalListenTime, key: ServerConstants.UserDefaults.statsListenedToServer)
            strongSelf.saveTime(remoteStats.autoSkipTime, key: ServerConstants.UserDefaults.statsAutoSkipServer)
            strongSelf.saveTime(remoteStats.variableSpeedTime, key: ServerConstants.UserDefaults.statsVariableSpeedServer)
            strongSelf.saveTime(remoteStats.skipTime, key: ServerConstants.UserDefaults.statsSkippedServer)

            strongSelf.userDefaults.setValue(remoteStats.startedStatsAt, forKey: ServerConstants.UserDefaults.statsStartedDateServer)

            completion?(true)
        }
    }

    public func statsStartedAt() -> Int64 {
        Int64(userDefaults.integer(forKey: ServerConstants.UserDefaults.statsStartedDateServer))
    }

    public func statsStartDate() -> Date {
        if let startDate = userDefaults.object(forKey: ServerConstants.UserDefaults.statsStartDate) as? Date {
            return startDate
        }

        let now = Date()
        userDefaults.set(now, forKey: ServerConstants.UserDefaults.statsStartDate)

        return now
    }

    public func timeSavedDynamicSpeedInclusive() -> TimeInterval {
        timeSavedDynamicSpeed() + timeForKey(ServerConstants.UserDefaults.statsDynamicSpeedSecondsServer)
    }

    public func timeSavedVariableSpeedInclusive() -> TimeInterval {
        timeSavedVariableSpeed() + timeForKey(ServerConstants.UserDefaults.statsVariableSpeedServer)
    }

    public func totalListeningTimeInclusive() -> TimeInterval {
        totalListeningTime() + timeForKey(ServerConstants.UserDefaults.statsListenedToServer)
    }

    public func totalSavedTime() -> TimeInterval {
        [
            totalSkippedTimeInclusive(),
            timeSavedVariableSpeedInclusive(),
            timeSavedDynamicSpeedInclusive(),
            totalAutoSkippedTimeInclusive()
        ].reduce(0, +)
    }

    public func totalSkippedTimeInclusive() -> TimeInterval {
        totalSkippedTime() + timeForKey(ServerConstants.UserDefaults.statsSkippedServer)
    }

    public func totalAutoSkippedTimeInclusive() -> TimeInterval {
        totalAutoSkippedTime() + timeForKey(ServerConstants.UserDefaults.statsAutoSkipServer)
    }

    // MARK: - Private Helpers

    private func parse(double: AnyObject?) -> Double {
        if let number = double as? Double {
            return number
        }
        if let number = double as? Int {
            return Double(number)
        }

        return 0
    }

    private func parse(integer: AnyObject?) -> Int64 {
        if let number = integer as? Int64 {
            return number
        }
        if let number = integer as? Int {
            return Int64(number)
        }

        return 0
    }

    private func timeForKey(_ key: String) -> TimeInterval {
        userDefaults.double(forKey: key)
    }

    private func saveTime(_ time: TimeInterval, key: String) {
        if time < 0, time < timeForKey(key) { return }

        userDefaults.set(time, forKey: key)
    }

    private func saveTime(_ time: Int64, key: String) {
        saveTime(TimeInterval(time), key: key)
    }

    func waitForPendingPersistence() {
        persistenceQueue.sync {}
    }
}
