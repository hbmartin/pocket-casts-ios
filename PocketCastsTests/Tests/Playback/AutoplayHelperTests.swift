import XCTest

@testable import PocketCastsServer
@testable import podcasts

class AutoplayHelperTests: XCTestCase {
    var autoplayHelper: AutoplayHelper!
    var userDefaults: UserDefaults!
    var suiteName: String!
    var previousAppSettings: SettingsStore<AppSettings>!

    override func setUp() {
        super.setUp()
        previousAppSettings = SettingsStore.appSettings
        suiteName = "AutoplayHelperTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        SettingsStore.appSettings = SettingsStore(userDefaults: userDefaults, key: "app_settings", value: AppSettings.defaults)
        autoplayHelper = AutoplayHelper(
            userDefaults: userDefaults
        )
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        SettingsStore.appSettings = previousAppSettings
        autoplayHelper = nil
        userDefaults = nil
        previousAppSettings = nil
        suiteName = nil
        super.tearDown()
    }

    func testInitialValueIsNil() {
        XCTAssertNil(autoplayHelper.lastPlaylist)
    }

    func testSaveLatestPlaylist() {
        autoplayHelper.playedFrom(playlist: .podcast(uuid: "fake-uuid"))

        switch autoplayHelper.lastPlaylist {
        case .podcast(uuid: let uuid):
            XCTAssertTrue(uuid == "fake-uuid")
        default:
            XCTFail()
        }
    }

    func testCorrectlyUpdateLatestPlaylist() {
        autoplayHelper.playedFrom(playlist: .podcast(uuid: "fake-uuid"))

        autoplayHelper.playedFrom(playlist: .starred)

        switch autoplayHelper.lastPlaylist {
        case .starred:
            break
        default:
            XCTFail()
        }
    }

    func testCorrectlyRemoveValueIfPlaylistIsUnknown() {
        autoplayHelper.playedFrom(playlist: .podcast(uuid: "fake-uuid"))

        autoplayHelper.playedFrom(playlist: nil)

        XCTAssertNil(autoplayHelper.lastPlaylist)
    }
}
