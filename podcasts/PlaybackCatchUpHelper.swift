import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import PocketCastsServer

struct PlaybackCatchUpHelper {
    /// The rewind tiers (in seconds) that intelligent resumption can apply;
    /// Smart Resume precomputes a snap candidate for each at pause time.
    private static let rewindTiers = [10, 15, 30]

    private let analyzer: ResumeSnapAnalyzing
    private let defaults: UserDefaults

    init(analyzer: ResumeSnapAnalyzing = ResumeSnapAnalyzer(), defaults: UserDefaults = .standard) {
        self.analyzer = analyzer
        self.defaults = defaults
    }

    func adjustStartTimeIfNeeded(for episode: BaseEpisode, playedUpTo: TimeInterval) -> TimeInterval {
        // if it's a different episode, or not still at the time it was at when it was last paused, just play from where it's up to
        if !intelligentPlaybackResumptionEnabled() || episode.uuid != lastPausedEpisodeUuid() || playedUpTo != lastPausedAt() { return playedUpTo }

        guard let lastPauseTime = lastPauseTime() else { return playedUpTo }

        if DateUtil.hasEnoughTimePassed(since: lastPauseTime, time: 24.hours) {
            FileLog.shared.addMessage("More than 24 hours since this episode was paused, jumping back 30 seconds")
            return snappedIfValid(raw: max(0, playedUpTo - 30.seconds), tierSeconds: 30, episodeUuid: episode.uuid, playedUpTo: playedUpTo)
        } else if DateUtil.hasEnoughTimePassed(since: lastPauseTime, time: 1.hour) {
            FileLog.shared.addMessage("More than 1 hour since this episode was paused, jumping back 15 seconds")
            return snappedIfValid(raw: max(0, playedUpTo - 15.seconds), tierSeconds: 15, episodeUuid: episode.uuid, playedUpTo: playedUpTo)
        } else if DateUtil.hasEnoughTimePassed(since: lastPauseTime, time: 5.minutes) {
            FileLog.shared.addMessage("More than 5 minutes since this episode was paused, jumping back 10 seconds")
            return snappedIfValid(raw: max(0, playedUpTo - 10.seconds), tierSeconds: 10, episodeUuid: episode.uuid, playedUpTo: playedUpTo)
        }

        FileLog.shared.addMessage("Not enough time passed since this episode was last paused, no time adjustment required")
        return playedUpTo
    }

    func playbackDidPause(of episode: BaseEpisode, playedUpTo: TimeInterval) {
        setLastPauseTimeToNow()
        setLastPausedEpisodeUuid(episode.uuid)
        setLastPausedAt(playedUpTo)

        // candidates from a previous pause must never validate against this one
        defaults.removeObject(forKey: snapCandidatesKey)

        guard intelligentPlaybackResumptionEnabled(),
              playedUpTo > 10,
              !episode.videoPodcast(),
              episode.downloaded(pathFinder: DownloadManager.shared) else { return }

        let targets = Self.rewindTiers.map { playedUpTo - TimeInterval($0) }.filter { $0 > 0 }
        guard !targets.isEmpty else { return }

        let fileURL = URL(fileURLWithPath: episode.pathToDownloadedFile(pathFinder: DownloadManager.shared))
        let episodeUuid = episode.uuid
        analyzer.snapCandidates(for: fileURL, targets: targets) { snaps in
            self.persistSnapCandidates(snaps, episodeUuid: episodeUuid, playedUpTo: playedUpTo)
        }
    }

    // MARK: - Smart Resume Candidates

    private let snapCandidatesKey = "lastPauseSnapCandidates"
    private let candidateUuidKey = "uuid"
    private let candidatePlayedUpToKey = "playedUpTo"

    private func persistSnapCandidates(_ snaps: [TimeInterval: TimeInterval], episodeUuid: String, playedUpTo: TimeInterval) {
        // the pause that requested this analysis must still be the most recent one
        guard episodeUuid == lastPausedEpisodeUuid(), playedUpTo == lastPausedAt() else {
            FileLog.shared.addMessage("[SmartResume] pause state changed during analysis, discarding candidates for \(episodeUuid)")
            return
        }

        var candidates: [String: Any] = [candidateUuidKey: episodeUuid, candidatePlayedUpToKey: playedUpTo]
        for tier in Self.rewindTiers {
            if let snap = snaps[playedUpTo - TimeInterval(tier)] {
                candidates["\(tier)"] = snap
            }
        }

        guard candidates.count > 2 else {
            FileLog.shared.addMessage("[SmartResume] no snap candidates found for \(episodeUuid) at \(playedUpTo)")
            return
        }

        defaults.set(candidates, forKey: snapCandidatesKey)
        FileLog.shared.addMessage("[SmartResume] candidates for \(episodeUuid) paused at \(playedUpTo): \(snaps)")
    }

    /// Returns the precomputed snap for the given rewind tier when it belongs to
    /// this pause and stays within the allowed adjustment; otherwise the raw time.
    private func snappedIfValid(raw: TimeInterval, tierSeconds: Int, episodeUuid: String, playedUpTo: TimeInterval) -> TimeInterval {
        guard let candidates = defaults.dictionary(forKey: snapCandidatesKey),
              candidates[candidateUuidKey] as? String == episodeUuid,
              candidates[candidatePlayedUpToKey] as? Double == playedUpTo,
              let snap = candidates["\(tierSeconds)"] as? Double else {
            FileLog.shared.addMessage("[SmartResume] no valid candidate for the \(tierSeconds)s tier, resuming at the raw position")
            return raw
        }

        guard snap >= 0, abs(snap - raw) <= SilenceGapFinder.Parameters().maxAdjustment else {
            FileLog.shared.addMessage("[SmartResume] candidate \(snap) is out of range of the raw position \(raw), resuming at the raw position")
            return raw
        }

        FileLog.shared.addMessage("[SmartResume] snapping the \(tierSeconds)s rewind from \(raw) to \(snap)")
        return snap
    }

    // MARK: - Intelligent Resumption Setting

    private func intelligentPlaybackResumptionEnabled() -> Bool {
        if FeatureFlag.newSettingsStorage.enabled {
            return SettingsStore.appSettings.intelligentResumption
        }

        return defaults.bool(forKey: Constants.UserDefaults.intelligentPlaybackResumption)
    }

    // MARK: - Pause Time

    private let pauseTimeKey = "lastPauseTime"
    private func lastPauseTime() -> Date? {
        guard let time = defaults.object(forKey: pauseTimeKey) as? Date else { return nil }

        return time
    }

    private func setLastPauseTimeToNow() {
        defaults.setValue(Date(), forKey: pauseTimeKey)
    }

    // MARK: - Paused Episode

    private let pausedEpisodeUuidKey = "lastPausedEpisode"
    private func lastPausedEpisodeUuid() -> String? {
        guard let uuid = defaults.object(forKey: pausedEpisodeUuidKey) as? String else { return nil }

        return uuid
    }

    private func setLastPausedEpisodeUuid(_ uuid: String) {
        defaults.setValue(uuid, forKey: pausedEpisodeUuidKey)
    }

    // MARK: - Paused At

    private let pausedAtKey = "lastPausedAt"
    private func lastPausedAt() -> Double? {
        guard let time = defaults.object(forKey: pausedAtKey) as? Double else { return nil }

        return time
    }

    private func setLastPausedAt(_ time: Double) {
        defaults.setValue(time, forKey: pausedAtKey)
    }
}
