import PocketCastsUtils

// Stub so `PlaybackControlIntent` compiles inside the widget extension, which
// references it from the controls but never executes it: as an
// `AudioPlaybackIntent` its `perform()` always runs in the app process, where
// the real `performPlaybackControlAction(_:)` lives. Mirrors
// `WidgetPlayEpisodeIntentExtension`.
extension PlaybackControlIntent {
    func performPlaybackControlAction(_ action: PlaybackControlAction) {
        FileLog.shared.addMessage("PlaybackControlIntent stub invoked in widget extension for \(action.rawValue)")
    }
}
