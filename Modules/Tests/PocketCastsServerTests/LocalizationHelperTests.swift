import Foundation
import PocketCastsDataModel
@testable import PocketCastsServer
import XCTest

final class LocalizationHelperTests: XCTestCase {

    override class func tearDown() {
        LocalizationHelper.provider = nil
        super.tearDown()
    }

    func testInternationalizationProvider() throws {
        let provider = InternationalizationProvider(
            userRegion: "en",
            appLanguage: "en-US",
            allowedHosts: [
                "https://refresh.pocketcasts.com/",
                "https://api.pocketcasts.com/"
            ]
                .compactMap { URL(string: $0)?.host }
                .reduce(into: Set<String>()) { $0.insert($1) }
        )

        XCTAssertTrue(provider.userRegion == "en")
        XCTAssertTrue(provider.appLanguage == "en-US")

        let url = try XCTUnwrap(URL(string: "https://api.pocketcasts.com/"))
        let host = try XCTUnwrap(url.host())
        XCTAssertTrue(provider.allowedHosts.contains(host))
    }

    func testLocalizationHelper() {
        let provider = InternationalizationProvider(
            userRegion: "en",
            appLanguage: "en-US",
            allowedHosts: [
                "https://refresh.pocketcasts.com/",
                "https://api.pocketcasts.com/"
            ]
                .compactMap { URL(string: $0)?.host }
                .reduce(into: Set<String>()) { $0.insert($1) }
        )
        LocalizationHelper.provider = provider

        XCTAssertTrue(LocalizationHelper.provider?.userRegion == "en")
        XCTAssertTrue(LocalizationHelper.provider?.appLanguage == "en-US")

        LocalizationHelper.update(userRegion: "it")

        XCTAssertTrue(LocalizationHelper.provider?.userRegion == "it")
    }

    func testDefaultAllowedHostsUsesStagingFilesHostWhenServerIsNotProduction() {
        let previousDelegate = ServerConfig.shared.syncDelegate
        ServerConfig.shared.syncDelegate = TestServerSyncDelegate(isProduction: false)
        defer { ServerConfig.shared.syncDelegate = previousDelegate }

        let provider = InternationalizationProvider(userRegion: "en", appLanguage: "en-US")

        XCTAssertTrue(provider.allowedHosts.contains("files.pocketcasts.net"))
    }
}

private final class TestServerSyncDelegate: ServerSyncDelegate {
    private let isProduction: Bool

    init(isProduction: Bool) {
        self.isProduction = isProduction
    }

    func production() -> Bool {
        isProduction
    }
}

private final class TestFilePathProvider: NSObject, FilePathProtocol {
    func tempPathForEpisode(_ episode: BaseEpisode) -> String { "" }
    func pathForEpisode(_ episode: BaseEpisode) -> String { "" }
    func streamingBufferPathForEpisode(_ episode: BaseEpisode) -> String { "" }
}

extension ServerSyncDelegate {
    func podcastUpdated(podcastUuid: String) {}
    func podcastAdded(podcastUuid: String) {}
    func checkForUnusedPodcasts() {}
    func applyAutoArchivingToAllPodcasts() {}
    func subscribedToPodcast() {}
    func playlistChanged() {}
    func episodeStarredChanged(episode: Episode) {}
    func archiveEpisodeExternal(episode: Episode) {}
    func markEpisodeAsPlayedExternal(episode: Episode) {}
    func deselectedChaptersChanged() {}
    func episodeCanBeCleanedUp(episode: Episode) -> Bool { false }
    func autoDownloadLatestEpisodes(uuids: [String]) {}
    func cleanupAllUnusedEpisodeBuffers() {}
    func deleteFromDevice(userEpisode: UserEpisode) {}
    func autoDownloadUserEpisodes(episodes: [UserEpisode]) {}
    func userEpisodeFileProtocol() -> FilePathProtocol { TestFilePathProvider() }
    func cleanupCloudOnlyFiles() {}
    func performActionsAfterSync() {}
    func isPushEnabled() -> Bool { false }
    func defaultPodcastGrouping() -> Int32 { 0 }
    func defaultShowArchived() -> Bool { false }
    func uniqueAppId() -> String { "" }
    func appVersion() -> String { "" }
    func privateUserAgent() -> String { "" }
    func minTimeBetweenProgressSaves() -> Double { 0 }
}
