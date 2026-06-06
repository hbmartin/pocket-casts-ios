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
    func tempPathForEpisode(_: BaseEpisode) -> String { "" }
    func pathForEpisode(_: BaseEpisode) -> String { "" }
    func streamingBufferPathForEpisode(_: BaseEpisode) -> String { "" }
}

private enum TestServerDefaults {
    static let pushNotificationsEnabled = false
    static let defaultPodcastGrouping: Int32 = 0
    static let showArchivedEpisodes = false
    static let appId = "test-app-id"
    static let appVersion = "test-app-version"
    static let privateUserAgent = "test-user-agent"
    static let minimumSecondsBetweenProgressSaves = 0.0
}

private func testNoOp() { _ = () }

extension ServerSyncDelegate {
    func podcastUpdated(podcastUuid _: String) { testNoOp() }
    func podcastAdded(podcastUuid _: String) { testNoOp() }
    func checkForUnusedPodcasts() { testNoOp() }
    func applyAutoArchivingToAllPodcasts() { testNoOp() }
    func subscribedToPodcast() { testNoOp() }
    func playlistChanged() { testNoOp() }
    func episodeStarredChanged(episode _: Episode) { testNoOp() }
    func archiveEpisodeExternal(episode _: Episode) { testNoOp() }
    func markEpisodeAsPlayedExternal(episode _: Episode) { testNoOp() }
    func deselectedChaptersChanged() { testNoOp() }
    func episodeCanBeCleanedUp(episode _: Episode) -> Bool {
        testNoOp()
        return false
    }
    func autoDownloadLatestEpisodes(uuids _: [String]) { testNoOp() }
    func cleanupAllUnusedEpisodeBuffers() { testNoOp() }
    func deleteFromDevice(userEpisode _: UserEpisode) { testNoOp() }
    func autoDownloadUserEpisodes(episodes _: [UserEpisode]) { testNoOp() }
    func userEpisodeFileProtocol() -> FilePathProtocol {
        testNoOp()
        return TestFilePathProvider()
    }
    func cleanupCloudOnlyFiles() { testNoOp() }
    func performActionsAfterSync() { testNoOp() }
    func isPushEnabled() -> Bool {
        TestServerDefaults.pushNotificationsEnabled
    }

    func defaultPodcastGrouping() -> Int32 {
        TestServerDefaults.defaultPodcastGrouping
    }

    func defaultShowArchived() -> Bool {
        TestServerDefaults.showArchivedEpisodes
    }

    func uniqueAppId() -> String {
        TestServerDefaults.appId
    }

    func appVersion() -> String {
        TestServerDefaults.appVersion
    }

    func privateUserAgent() -> String {
        TestServerDefaults.privateUserAgent
    }

    func minTimeBetweenProgressSaves() -> Double {
        TestServerDefaults.minimumSecondsBetweenProgressSaves
    }
}
