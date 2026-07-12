import Foundation
import SwiftUI

/// Reloaded and read synchronously inside each timeline-provider callback;
/// WidgetKit serializes those per provider, so access is effectively serial.
/// @unchecked Sendable: mutated only inside WidgetKit's serialized timeline-provider callbacks (see above).
final class WidgetData: ObservableObject, @unchecked Sendable {
    static let shared = WidgetData()

    @Published var nowPlayingEpisode: WidgetEpisode?
    @Published var isPlaying = false
    @Published var topFilterName: String?
    @Published var upNextEpisodes: [WidgetEpisode]?
    @Published var topFilterEpisodes: [WidgetEpisode]?
    @Published var upNextEpisodesCount: Int?

    func reload() {
        nowPlayingEpisode = CommonWidgetHelper.loadNowPlayingEpisode()
        isPlaying = CommonWidgetHelper.loadPlayingStatus()
        topFilterName = CommonWidgetHelper.loadTopFilterName()
        upNextEpisodes = CommonWidgetHelper.loadNowPlayingEpisodes()
        topFilterEpisodes = CommonWidgetHelper.loadTopFilterEpisodes()
        upNextEpisodesCount = CommonWidgetHelper.loadUpNextEpisodesCount()
    }
}
