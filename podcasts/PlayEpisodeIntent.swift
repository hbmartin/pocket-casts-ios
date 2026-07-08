import AppIntents
import WidgetKit
import PocketCastsUtils

struct PlayEpisodeIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play episode"
    static let isDiscoverable = false // for now only to be used in the Now Playing widget

    @Parameter(title: "EpisodeUUID")
    var episodeUuid: String

    init(episodeUuid: String) {
        self.episodeUuid = episodeUuid
    }

    init() {}

    static var openAppWhenRun: Bool { return false }

    static var supportedModes: IntentModes { return [.background] }

    @MainActor
    func perform() async throws -> some IntentResult {
        FileLog.shared.addMessage("PlayEpisodeIntent perform called for episode \(episodeUuid)")
        intentPlayback(episodeUuid)

        return .result()
    }
}
