import PocketCastsDataModel
import PocketCastsServer
import XCTest

@testable import podcasts

/// Tests the pure badge-input mapping backing `BadgeHelper.updateBadge()` (B6
/// ValueObservation pilot): which combinations of the non-database inputs clear
/// the badge, disable the setting, or start a database count observation.
@MainActor
final class BadgeHelperTests: XCTestCase {
    private var badgeFilter: EpisodeFilter {
        var filter = EpisodeFilter()
        filter.uuid = "badge-filter-uuid"
        return filter
    }

    func testNoSettingLeavesBadgeUntouched() {
        let action = BadgeHelper.badgeAction(setting: nil, pushEnabled: true, lastAppCloseDate: nil, badgeFilter: nil, episodeUuidToAdd: nil)
        XCTAssertEqual(action, .leaveUntouched)
    }

    func testBadgeAndPushBothOffLeavesBadgeUntouched() {
        // Touching the badge with both off would trigger the push permission popup.
        let action = BadgeHelper.badgeAction(setting: .off, pushEnabled: false, lastAppCloseDate: nil, badgeFilter: nil, episodeUuidToAdd: nil)
        XCTAssertEqual(action, .leaveUntouched)
    }

    func testBadgeOffWithPushOnClears() {
        let action = BadgeHelper.badgeAction(setting: .off, pushEnabled: true, lastAppCloseDate: nil, badgeFilter: nil, episodeUuidToAdd: nil)
        XCTAssertEqual(action, .clear)
    }

    func testPushOffClearsEvenWhenBadgeModeIsSet() {
        let action = BadgeHelper.badgeAction(setting: .totalUnplayed, pushEnabled: false, lastAppCloseDate: nil, badgeFilter: nil, episodeUuidToAdd: nil)
        XCTAssertEqual(action, .clear)
    }

    func testTotalUnplayedObservesUnrestrictedCount() {
        let action = BadgeHelper.badgeAction(setting: .totalUnplayed, pushEnabled: true, lastAppCloseDate: nil, badgeFilter: nil, episodeUuidToAdd: nil)
        XCTAssertEqual(action, .observe(.subscribedUnplayed(addedAfter: nil)))
    }

    func testNewSinceLastOpenedObservesCountAfterCloseDate() {
        let closeDate = Date(timeIntervalSince1970: 1_000_000)
        let action = BadgeHelper.badgeAction(setting: .newSinceLastOpened, pushEnabled: true, lastAppCloseDate: closeDate, badgeFilter: nil, episodeUuidToAdd: nil)
        XCTAssertEqual(action, .observe(.subscribedUnplayed(addedAfter: closeDate)))
    }

    func testNewSinceLastOpenedWithoutCloseDateClears() {
        let action = BadgeHelper.badgeAction(setting: .newSinceLastOpened, pushEnabled: true, lastAppCloseDate: nil, badgeFilter: nil, episodeUuidToAdd: nil)
        XCTAssertEqual(action, .clear)
    }

    func testFilterCountObservesPlaylistWithPinnedEpisode() {
        let action = BadgeHelper.badgeAction(setting: .filterCount, pushEnabled: true, lastAppCloseDate: nil, badgeFilter: badgeFilter, episodeUuidToAdd: "playing-episode")
        XCTAssertEqual(action, .observe(.playlistEpisodes(playlistUuid: "badge-filter-uuid", episodeUuidToAdd: "playing-episode")))
    }

    func testFilterCountWithMissingFilterDisablesBadgeSetting() {
        let action = BadgeHelper.badgeAction(setting: .filterCount, pushEnabled: true, lastAppCloseDate: nil, badgeFilter: nil, episodeUuidToAdd: nil)
        XCTAssertEqual(action, .disableBadgeSetting)
    }
}
