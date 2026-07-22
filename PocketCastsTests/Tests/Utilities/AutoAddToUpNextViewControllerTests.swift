import XCTest
import PocketCastsDataModel
import PocketCastsUtils
@testable import podcasts

@MainActor
final class AutoAddToUpNextViewControllerTests: DBTestCase {
    func testEscapingActionPreservesConcurrentFieldUpdateWithLegacyStorage() throws {
        try assertEscapingActionPreservesConcurrentFieldUpdate(newSettingsStorage: false)
    }

    func testEscapingActionPreservesConcurrentFieldUpdateWithNewSettingsStorage() throws {
        try assertEscapingActionPreservesConcurrentFieldUpdate(newSettingsStorage: true)
    }

    private func assertEscapingActionPreservesConcurrentFieldUpdate(newSettingsStorage: Bool) throws {
        let store = FeatureFlagOverrideStore()
        defer { store.resetOverrides() }
        try store.override(FeatureFlag.newSettingsStorage, withValue: newSettingsStorage)

        var podcast = Podcast()
        podcast.uuid = "auto-add-action-\(newSettingsStorage)"
        podcast.title = "Title when the option opened"
        podcast.author = "Original author"
        podcast.addedDate = Date()
        podcast.syncStatus = SyncStatus.synced.rawValue
        podcast = dataManager.save(podcast: podcast)
        track(podcast: podcast)

        var controller: AutoAddToUpNextViewController? = AutoAddToUpNextViewController()
        let action = try XCTUnwrap(controller).actionForPodcast(podcast: podcast, setting: .addLast, label: "Bottom")
        controller = nil

        var concurrentlyUpdatedPodcast = podcast
        concurrentlyUpdatedPodcast.title = "Title from background refresh"
        concurrentlyUpdatedPodcast.author = "Updated author"
        concurrentlyUpdatedPodcast.syncStatus = SyncStatus.synced.rawValue
        dataManager.save(podcast: concurrentlyUpdatedPodcast)

        action.action()

        let found = try XCTUnwrap(dataManager.findPodcast(uuid: podcast.uuid))
        XCTAssertEqual(found.title, concurrentlyUpdatedPodcast.title)
        XCTAssertEqual(found.author, concurrentlyUpdatedPodcast.author)
        XCTAssertEqual(found.autoAddToUpNext, AutoAddToUpNextSetting.addLast.rawValue)
        XCTAssertEqual(found.syncStatus, SyncStatus.notSynced.rawValue)
        if newSettingsStorage {
            XCTAssertTrue(found.settings.addToUpNext)
            XCTAssertEqual(found.settings.addToUpNextPosition, .bottom)
        }
    }
}
