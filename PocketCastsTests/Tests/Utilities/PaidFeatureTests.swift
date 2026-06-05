import XCTest

@testable import podcasts
@testable import PocketCastsServer

final class PaidFeatureTests: XCTestCase {
    private var previousFeaturesUnlocked = false
    private var previousSubscriptionPaidStatus = 0
    private var previousSubscriptionTier: SubscriptionTier = .none

    override func setUp() {
        super.setUp()
        previousFeaturesUnlocked = SubscriptionHelper.featuresUnlocked
        previousSubscriptionPaidStatus = SubscriptionHelper.hasActiveSubscription() ? 1 : 0
        previousSubscriptionTier = SubscriptionHelper.subscriptionTier
        SubscriptionHelper.featuresUnlocked = false
        setSubscription(tier: .none)
    }

    override func tearDown() {
        SubscriptionHelper.featuresUnlocked = previousFeaturesUnlocked
        SubscriptionHelper.setSubscriptionPaid(previousSubscriptionPaidStatus)
        SubscriptionHelper.subscriptionTier = previousSubscriptionTier
        super.tearDown()
    }

    // MARK: - Free Features

    func testFreeFeatureIsUnlocked() {
        let feature = freeFeature()

        XCTAssertTrue(feature.isUnlocked)
    }

    // MARK: - Plus Features

    func testPlusFeatureIsLockedWithoutSubscription() {
        let feature = plusFeature()

        XCTAssertFalse(feature.isUnlocked)
    }

    func testPlusFeatureIsUnlockedForPlusSubscription() {
        setSubscription(tier: .plus)
        let feature = plusFeature()

        XCTAssertTrue(feature.isUnlocked)
    }

    func testPlusFeatureIsUnlockedForPatronSubscription() {
        setSubscription(tier: .patron)
        let feature = plusFeature()

        XCTAssertTrue(feature.isUnlocked)
    }

    // MARK: - Patron Features

    func testPatronFeatureIsLockedForPlusSubscription() {
        setSubscription(tier: .plus)
        let feature = patronFeature()

        XCTAssertFalse(feature.isUnlocked)
    }

    func testPatronFeatureIsUnlockedForPatronSubscription() {
        setSubscription(tier: .patron)
        let feature = patronFeature()

        XCTAssertTrue(feature.isUnlocked)
    }

    func testFeaturesUnlockedOverrideUnlocksPaidFeatures() {
        SubscriptionHelper.featuresUnlocked = true
        setSubscription(tier: .none)

        XCTAssertTrue(plusFeature().isUnlocked)
        XCTAssertTrue(patronFeature().isUnlocked)
    }

    // MARK: - Beta Testing

    func testPatronFeatureWithBetaPlusUsesPlusTierInBeta() {
        let feature = PaidFeature(tier: .patron,
                                  betaTier: .plus,
                                  buildEnvironment: .testFlight)

        XCTAssertEqual(feature.tier, .plus)
    }

    func testPatronFeatureWithBetaPlusUsesPatronTierForAppStore() {
        let feature = PaidFeature(tier: .patron,
                                  betaTier: .plus,
                                  buildEnvironment: .appStore)

        XCTAssertEqual(feature.tier, .patron)
    }

    func testEarlyAccessFlagIsStored() {
        let feature = PaidFeature(tier: .plus, inEarlyAccess: true)

        XCTAssertTrue(feature.inEarlyAccess)
    }

    // MARK: - Private
    private func freeFeature() -> PaidFeature {
        feature(tier: .none)
    }

    private func plusFeature() -> PaidFeature {
        feature(tier: .plus)
    }

    private func patronFeature() -> PaidFeature {
        feature(tier: .patron)
    }

    private func feature(tier: SubscriptionTier) -> PaidFeature {
        PaidFeature(tier: tier)
    }

    private func setSubscription(tier: SubscriptionTier) {
        SubscriptionHelper.setSubscriptionPaid(tier == .none ? 0 : 1)
        SubscriptionHelper.subscriptionTier = tier
    }
}
