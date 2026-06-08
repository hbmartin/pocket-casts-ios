import XCTest
@testable import PocketCastsUtils

class FeatureFlagTests: XCTestCase {
    var store: FeatureFlagOverrideStore!

    override func setUp() {
        store = FeatureFlagOverrideStore(store: UserDefaults(suiteName: "FeatureFlagTests-\(UUID().uuidString)")!)
    }

    func testEnabledFeatureFlagValueIsOverridden() {
        let flag = MockFeatureFlag.enabledFeature

        XCTAssertNil(store.overriddenValue(for: flag))
        try? store.override(flag, withValue: false)

        let value = store.overriddenValue(for: flag)
        XCTAssertNotNil(value)
        XCTAssert(value == false)
    }

    func testDisabledFeatureFlagValueIsOverridden() {
        let flag = MockFeatureFlag.disabledFeature

        XCTAssertNil(store.overriddenValue(for: flag))
        try? store.override(flag, withValue: true)

        let value = store.overriddenValue(for: flag)
        XCTAssertNotNil(value)
        XCTAssert(value == true)
    }

    func testNonOverrideableFeatureFlagCannotBeOverridden() {
        let flag = MockFeatureFlag.nonOverrideableFeature

        try? store.override(flag, withValue: false)
        XCTAssertFalse(store.isOverridden(flag))
    }

    func testEnabledFeatureFlagValueIsNotOverriddenWhenResetToNormalState() {
        let flag = MockFeatureFlag.enabledFeature

        XCTAssertFalse(store.isOverridden(flag))

        try? store.override(flag, withValue: false)
        XCTAssertTrue(store.isOverridden(flag))

        try? store.override(flag, withValue: true)
        XCTAssertFalse(store.isOverridden(flag))
    }

    func testDisabledFeatureFlagValueIsNotOverriddenWhenResetToNormalState() {
        let flag = MockFeatureFlag.disabledFeature

        XCTAssertFalse(store.isOverridden(flag))

        try? store.override(flag, withValue: true)
        XCTAssertTrue(store.isOverridden(flag))

        try? store.override(flag, withValue: false)
        XCTAssertFalse(store.isOverridden(flag))
    }

    func testRemoteConfigBooleanOverridesFeatureFlag() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FeatureFlagTests-\(UUID().uuidString)"))
        let remoteKey = try XCTUnwrap(FeatureFlag.defaultPlayerFilterCallbackFix.remoteKey)

        defaults.set(false, forKey: RemoteConfigValueStore.key(for: remoteKey))

        XCTAssertEqual(FeatureFlagRemoteConfigStore(store: defaults).overriddenValue(for: .defaultPlayerFilterCallbackFix), false)
    }

    func testRemoteConfigStringBooleanOverridesFeatureFlag() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FeatureFlagTests-\(UUID().uuidString)"))
        let remoteKey = try XCTUnwrap(FeatureFlag.defaultPlayerFilterCallbackFix.remoteKey)

        defaults.set("false", forKey: RemoteConfigValueStore.key(for: remoteKey))

        XCTAssertEqual(FeatureFlagRemoteConfigStore(store: defaults).overriddenValue(for: .defaultPlayerFilterCallbackFix), false)
    }

    func testRemoteConfigBareKeyDoesNotOverrideFeatureFlag() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FeatureFlagTests-\(UUID().uuidString)"))
        let remoteKey = try XCTUnwrap(FeatureFlag.defaultPlayerFilterCallbackFix.remoteKey)

        defaults.set(false, forKey: remoteKey)

        XCTAssertNil(FeatureFlagRemoteConfigStore(store: defaults).overriddenValue(for: .defaultPlayerFilterCallbackFix))
    }

    func testEnabledUsesRemoteConfigValueAfterLocalOverride() throws {
        let flag = FeatureFlag.defaultPlayerFilterCallbackFix
        let remoteKey = try XCTUnwrap(flag.remoteKey)
        let remoteConfigKey = RemoteConfigValueStore.key(for: remoteKey)
        defer {
            UserDefaults.standard.removeObject(forKey: remoteConfigKey)
            try? FeatureFlagOverrideStore().override(flag, withValue: flag.default)
        }

        UserDefaults.standard.set(false, forKey: remoteConfigKey)

        XCTAssertFalse(flag.enabled)

        try FeatureFlagOverrideStore().override(flag, withValue: true)

        XCTAssertTrue(flag.enabled)
    }
}

enum MockFeatureFlag: OverrideableFlag {
    case enabledFeature
    case disabledFeature
    case nonOverrideableFeature

    var enabled: Bool {
        switch self {
        case .enabledFeature:
            return true
        case .disabledFeature:
            return false
        case .nonOverrideableFeature:
            return true
        }
    }

    var canOverride: Bool {
        return self != .nonOverrideableFeature
    }

    var description: String {
        switch self {
        case .enabledFeature:
            return "Enabled feature"
        case .disabledFeature:
            return "Disabled feature"
        case .nonOverrideableFeature:
            return "Non overrideable feature"
        }
    }
}
