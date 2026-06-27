import XCTest
@testable import podcasts
import PocketCastsDataModel

/// Pure-logic tests for EpisodeFilter+Formatting.swift: icon-name mapping, playlist style, and the
/// auto-download limit default. These read only record properties and a `PlaylistIcon` enum (no DB/UI),
/// so a plain `EpisodeFilter()` suffices. Image-loading and theme/playback helpers are intentionally
/// not covered here (they depend on the asset bundle / global theme / PlaybackManager).
final class EpisodeFilterFormattingTests: XCTestCase {

    // MARK: - imageName(forPlaylistIcon:)

    func testImageName_mapsEachIconGroup() {
        XCTAssertEqual(EpisodeFilter.imageName(forPlaylistIcon: .redPlaylist), "filter_list")
        XCTAssertEqual(EpisodeFilter.imageName(forPlaylistIcon: .bluemostPlayed), "filter_headphones")
        XCTAssertEqual(EpisodeFilter.imageName(forPlaylistIcon: .greenRecent), "filter_clock")
        XCTAssertEqual(EpisodeFilter.imageName(forPlaylistIcon: .purpleDownloading), "filter_downloaded")
        XCTAssertEqual(EpisodeFilter.imageName(forPlaylistIcon: .yellowUnplayed), "filter_play")
        XCTAssertEqual(EpisodeFilter.imageName(forPlaylistIcon: .redAudio), "filter_volume")
        XCTAssertEqual(EpisodeFilter.imageName(forPlaylistIcon: .blueVideo), "filter_video")
        XCTAssertEqual(EpisodeFilter.imageName(forPlaylistIcon: .greenTop), "filter_starred")
    }

    // MARK: - iconImageName / iconImageNameLarge

    func testIconImageName_derivesFromCustomIcon() {
        var filter = EpisodeFilter()
        filter.customIcon = PlaylistIcon.redPlaylist.rawValue
        XCTAssertEqual(filter.iconImageName(), "filter_list")
        XCTAssertEqual(filter.iconImageNameLarge(), "filter_list_large")
    }

    // MARK: - playlistStyle

    func testPlaylistStyle_mapsColorFamilyToThemeStyle() {
        func style(for icon: PlaylistIcon) -> ThemeStyle {
            var filter = EpisodeFilter()
            filter.customIcon = icon.rawValue
            return filter.playlistStyle()
        }
        XCTAssertEqual(style(for: .redPlaylist), .filter01)
        XCTAssertEqual(style(for: .bluemostPlayed), .filter05)
        XCTAssertEqual(style(for: .greenRecent), .filter04)
        XCTAssertEqual(style(for: .purpleDownloading), .filter06)
        XCTAssertEqual(style(for: .yellowUnplayed), .filter03)
    }

    // MARK: - maxAutoDownloadEpisodes

    func testMaxAutoDownloadEpisodes_usesDefaultWhenZero() {
        var filter = EpisodeFilter()
        filter.autoDownloadLimit = 0
        XCTAssertEqual(filter.maxAutoDownloadEpisodes(), Constants.Values.defaultPlaylistDownloadLimit)
    }

    func testMaxAutoDownloadEpisodes_usesConfiguredLimit() {
        var filter = EpisodeFilter()
        filter.autoDownloadLimit = 25
        XCTAssertEqual(filter.maxAutoDownloadEpisodes(), 25)
    }
}
