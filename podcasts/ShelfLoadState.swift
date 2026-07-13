import Foundation
import PocketCastsDataModel

struct ShelfLoadState {
    private var lastShelfActionsLoaded: [PlayerAction]?
    private var lastShelfEpisodeUuid: String?
    private var effectsAreOn = false
    private var sleepTimerIsOn = false
    // tracked separately from sleepTimerIsOn so the stop-after-episode button re-tints
    // when a time-based timer converts to an episode stop (sleepTimerActive() stays true)
    private var stopAfterEpisodeIsOn = false
    private var episodeIsStarred = false
    private var episodeStatus: Int32 = 0

    mutating func updateRequired(shelfActions: [PlayerAction], episodeUuid: String, effectsOn: Bool, sleepTimerOn: Bool, stopAfterEpisodeOn: Bool, episodeStarred: Bool, episodeStatus: Int32) -> Bool {
        if lastShelfActionsLoaded == shelfActions, lastShelfEpisodeUuid == episodeUuid, effectsAreOn == effectsOn, sleepTimerIsOn == sleepTimerOn, stopAfterEpisodeIsOn == stopAfterEpisodeOn, episodeIsStarred == episodeStarred, episodeStatus == self.episodeStatus {
            return false
        }

        lastShelfActionsLoaded = shelfActions
        lastShelfEpisodeUuid = episodeUuid
        effectsAreOn = effectsOn
        sleepTimerIsOn = sleepTimerOn
        stopAfterEpisodeIsOn = stopAfterEpisodeOn
        episodeIsStarred = episodeStarred
        self.episodeStatus = episodeStatus

        return true
    }
}
