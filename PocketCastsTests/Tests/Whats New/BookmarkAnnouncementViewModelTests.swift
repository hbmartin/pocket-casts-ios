import PocketCastsServer
import PocketCastsUtils
import SwiftUI
import XCTest

@testable import podcasts

final class BookmarkAnnouncementViewModelTests: XCTestCase {
    private var userDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: UUID().uuidString)!
        SubscriptionHelper.featuresUnlocked = false
    }

    override func tearDown() {
        SubscriptionHelper.featuresUnlocked = true
        super.tearDown()
    }

    // MARK: - Full Release

    func testFullReleaseAnnouncementIsEnabledInBeta() {
        let model = model(featureTier: .plus, environment: .testFlight)

        XCTAssertTrue(model.isReleaseAnnouncementEnabled)
    }

    func testFullReleaseAnnouncementIsEnabledInRelease() {
        let model = model(featureTier: .plus, environment: .appStore)

        XCTAssertTrue(model.isReleaseAnnouncementEnabled)
    }

    func testFullReleaseIsEnabledForNoSubscription() {
        let model = model(featureTier: .plus, environment: .appStore, activeTier: .none)

        XCTAssertTrue(model.isReleaseAnnouncementEnabled)
    }

    func testFullReleaseIsEnabledForPlus() {
        let model = model(featureTier: .plus, environment: .appStore, activeTier: .plus)

        XCTAssertTrue(model.isReleaseAnnouncementEnabled)
    }

    func testFullReleaseIsEnabledForPatron() {
        let model = model(featureTier: .plus, environment: .appStore, activeTier: .patron)

        XCTAssertTrue(model.isReleaseAnnouncementEnabled)
    }

    func testFullReleaseIsDisabledForPeopleWhoSawItBefore() {
        let model = model(featureTier: .plus, environment: .appStore)
        model.markAsSeen()

        XCTAssertFalse(model.isReleaseAnnouncementEnabled)
    }

    // MARK: - Display Tier

    func testDisplayTierIsHiddenForEarlyAccess() {
        let betaModel = model(featureTier: .plus, environment: .testFlight, inEarlyAccess: true)
        XCTAssertEqual(betaModel.displayTier, .none)

        let appStoreModel = model(featureTier: .plus, environment: .appStore, inEarlyAccess: true)
        XCTAssertEqual(appStoreModel.displayTier, .none)
    }

    func testDisplayTierIsHiddenWhenFeatureIsUnlockedInFullRelease() {
        let model = model(featureTier: .plus, environment: .appStore, inEarlyAccess: false, activeTier: .patron)
        XCTAssertEqual(model.displayTier, .none)
    }

    func testDisplayTierIsHiddenForNoSubscriptionInFullRelease() {
        let model = model(featureTier: .plus, environment: .appStore, inEarlyAccess: false, activeTier: .none)
        XCTAssertEqual(model.displayTier, .none)
    }
}

private extension BookmarkAnnouncementViewModelTests {
    func model(featureTier: SubscriptionTier,
               environment: BuildEnvironment,
               inEarlyAccess: Bool = false,
               activeTier: SubscriptionTier = .none) -> BookmarkAnnouncementViewModel {
        let feature = PaidFeature(tier: featureTier,
                                  inEarlyAccess: inEarlyAccess,
                                  buildEnvironment: environment)

        return BookmarkAnnouncementViewModel(feature: feature,
                                             buildEnvironment: environment,
                                             activeTier: activeTier,
                                             userDefaults: userDefaults)
    }
}
