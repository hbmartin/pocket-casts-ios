import XCTest

@testable import podcasts
import PocketCastsServer

final class PaidFeatureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SubscriptionHelper.featuresUnlocked = false
    }

    override func tearDown() {
        SubscriptionHelper.featuresUnlocked = true
        super.tearDown()
    }

    // MARK: - Free Features

    func testFreeFeatureIsUnlocked() {
        let feature = freeFeature()

        XCTAssertTrue(feature.isUnlocked)
    }

    // MARK: - Plus Features

    func testPlusFeatureIsUnlocked() {
        let feature = plusFeature()

        XCTAssertTrue(feature.isUnlocked)
    }

    // MARK: - Patron Features

    func testPatronFeatureIsUnlocked() {
        let feature = patronFeature()

        XCTAssertTrue(feature.isUnlocked)
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
}
