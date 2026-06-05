@testable import PocketCastsServer
import PocketCastsUtils
import SwiftUI
import XCTest

@testable import podcasts

final class BookmarkAnnouncementViewModelTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var previousFeaturesUnlocked = false

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: UUID().uuidString)!
        previousFeaturesUnlocked = SubscriptionHelper.featuresUnlocked
        SubscriptionHelper.featuresUnlocked = false
    }

    override func tearDown() {
        SubscriptionHelper.featuresUnlocked = previousFeaturesUnlocked
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

    func testDisplayTierIsShownForLockedEarlyAccess() {
        let betaModel = model(featureTier: .plus, environment: .testFlight, inEarlyAccess: true)
        XCTAssertEqual(betaModel.displayTier, .plus)

        let appStoreModel = model(featureTier: .plus, environment: .appStore, inEarlyAccess: true)
        XCTAssertEqual(appStoreModel.displayTier, .plus)
    }

    func testDisplayTierIsHiddenWhenFeatureIsUnlockedInFullRelease() {
        let model = model(featureTier: .plus, environment: .appStore, inEarlyAccess: false, activeTier: .patron)
        XCTAssertEqual(model.displayTier, .none)
    }

    func testDisplayTierIsShownForNoSubscriptionInFullRelease() {
        let model = model(featureTier: .plus, environment: .appStore, inEarlyAccess: false, activeTier: .none)
        XCTAssertEqual(model.displayTier, .plus)
    }
}

private extension BookmarkAnnouncementViewModelTests {
    func model(featureTier: SubscriptionTier,
               environment: BuildEnvironment,
               inEarlyAccess: Bool = false,
               activeTier: SubscriptionTier = .none) -> BookmarkAnnouncementViewModel {
        let feature = PaidFeature(tier: featureTier,
                                  inEarlyAccess: inEarlyAccess,
                                  subscriptionHelper: MockSubscriptionHelper(activeTier: activeTier),
                                  buildEnvironment: environment)

        return BookmarkAnnouncementViewModel(feature: feature,
                                             buildEnvironment: environment,
                                             activeTier: activeTier,
                                             userDefaults: userDefaults)
    }
}

private final class MockSubscriptionHelper: SubscriptionHelper {
    private let mockedActiveTier: SubscriptionTier

    init(activeTier: SubscriptionTier) {
        mockedActiveTier = activeTier
        super.init()
    }

    override var activeTier: SubscriptionTier {
        mockedActiveTier
    }
}
