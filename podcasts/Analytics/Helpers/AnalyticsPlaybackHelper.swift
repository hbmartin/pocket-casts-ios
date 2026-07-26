import PocketCastsUtils
import PocketCastsDataModel
import Foundation
import Synchronization

/// Helper used to track playback
// This restates AnalyticsCoordinator's conformance, as Swift requires
// @unchecked Sendable: subclass state is guarded by Mutex.
nonisolated class AnalyticsPlaybackHelper: AnalyticsCoordinator, @unchecked Sendable {
    static let shared = AnalyticsPlaybackHelper()

    /// Whether to ignore the next seek event
    private let ignoreNextSeek = Mutex(false)

    func play() {
        track(.playbackPlay)
    }

    func pause() {
        track(.playbackPause)
    }

    func skipBack() {
        ignoreNextSeek.withLock { $0 = true }
        track(.playbackSkipBack)
    }

    func skipForward() {
        ignoreNextSeek.withLock { $0 = true }
        track(.playbackSkipForward)
    }

    func seek(from: TimeInterval, to: TimeInterval, duration: TimeInterval) {
        // Atomic read-and-reset: every path through the original guard left the
        // flag false, so exchange first, then decide.
        let wasIgnoringSeek = ignoreNextSeek.withLock { ignore in
            defer { ignore = false }
            return ignore
        }

        // Currently ignore a seek event that is triggered by a sync process
        // Using the skip buttons triggers a seek, ignore this as well
        guard currentSource != .sync, wasIgnoringSeek == false else {
            return
        }

        let from = (from / duration)
        let to = (to / duration)

        // Validate the values are valid
        guard from.isNumeric, to.isNumeric else { return }

        // Use percents to relativize the seeking across any duration episode
        let seekFrom = Int(from * 100)
        let seekPercent = Int(to * 100)

        track(.playbackSeek, properties: ["seek_to_percent": seekPercent, "seek_from_percent": seekFrom])
    }

    func playbackSpeedChanged(to speed: Double, currentSettings: String? = nil) {
        track(.playbackEffectSpeedChanged, currentSettings: currentSettings, properties: ["speed": speed])
    }

    func trimSilenceToggled(enabled: Bool, currentSettings: String? = nil) {
        track(.playbackEffectTrimSilenceToggled, currentSettings: currentSettings, properties: ["enabled": enabled])
    }

    func trimSilenceAmountChanged(amount: TrimSilenceAmount, currentSettings: String? = nil) {
        track(.playbackEffectTrimSilenceAmountChanged, currentSettings: currentSettings, properties: ["amount": amount.analyticsDescription])
    }

    func volumeBoostToggled(enabled: Bool, currentSettings: String? = nil) {
        track(.playbackEffectVolumeBoostToggled, currentSettings: currentSettings, properties: ["enabled": enabled])
    }

    func chapterSkipped(properties: [String: Any]?) {
        track(.playbackChapterSkipped, properties: properties)
    }

    func viewDidAppear(currentSettings: String) {
        track(.playbackEffectSettingsViewAppeared, properties: ["settings": currentSettings])
    }

    func effectSettingsChanged(currentSettings: String) {
        track(.playbackEffectSettingsChanged, properties: ["settings": currentSettings])
    }

    func playbackFailed(episodeUUID: String, error: String, player: PlaybackProtocol?) {
        track(.playbackFailed, properties: ["episode_uuid": episodeUUID,
                                            "error": error,
                                            "player": playerString(player: player)])
    }

    enum PlayerSource: String {
        case fullPlayer = "full_player"
        case miniPlayer = "mini_player"
    }

    func playbackErrorShown(playerSource: PlayerSource) {
        track(.playbackErrorShown, properties: ["player_source": playerSource.rawValue])
    }

    func playbackErrorTapped(playerSource: PlayerSource) {
        track(.playbackErrorTapped, properties: ["player_source": playerSource.rawValue])
    }

    private func track(_ event: AnalyticsEvent, currentSettings: String?, properties: [String: Any]? = nil) {
        var properties = properties
        if let currentSettings {
            properties?["settings"] = currentSettings
        }
        track(event, properties: properties)
    }

    func playerString(player: PlaybackProtocol?) -> String {
        if player is EffectsPlayer {
            return "effects"
        }

        if player is DefaultPlayer {
            return "default"
        } else {
            return "unknown"
        }
    }
}
