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
        let remoteKey = try XCTUnwrap(FeatureFlag.autoDownloadOnSubscribe.remoteKey)
        let remoteConfigStore = RemoteConfigValueStore(store: defaults)

        defaults.set(false, forKey: remoteConfigStore.key(for: remoteKey))

        XCTAssertEqual(FeatureFlagRemoteConfigStore(store: defaults).overriddenValue(for: .autoDownloadOnSubscribe), false)
    }

    func testRemoteConfigStringBooleanOverridesFeatureFlag() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FeatureFlagTests-\(UUID().uuidString)"))
        let remoteKey = try XCTUnwrap(FeatureFlag.autoDownloadOnSubscribe.remoteKey)
        let remoteConfigStore = RemoteConfigValueStore(store: defaults)

        defaults.set("false", forKey: remoteConfigStore.key(for: remoteKey))

        XCTAssertEqual(FeatureFlagRemoteConfigStore(store: defaults).overriddenValue(for: .autoDownloadOnSubscribe), false)
    }

    func testRemoteConfigValueStoreUsesCustomKeyPrefix() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FeatureFlagTests-\(UUID().uuidString)"))
        let defaultStore = RemoteConfigValueStore(store: defaults)
        let customStore = RemoteConfigValueStore(store: defaults, keyPrefix: "custom-prefix-")
        let remoteKey = "custom_remote_key"

        defaults.set(false, forKey: customStore.key(for: remoteKey))
        defaults.set(true, forKey: defaultStore.key(for: remoteKey))

        XCTAssertEqual(customStore.bool(forKey: remoteKey), false)
        XCTAssertEqual(defaultStore.bool(forKey: remoteKey), true)
    }

    func testRemoteConfigBareKeyDoesNotOverrideFeatureFlag() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FeatureFlagTests-\(UUID().uuidString)"))
        let remoteKey = try XCTUnwrap(FeatureFlag.autoDownloadOnSubscribe.remoteKey)

        defaults.set(false, forKey: remoteKey)

        XCTAssertNil(FeatureFlagRemoteConfigStore(store: defaults).overriddenValue(for: .autoDownloadOnSubscribe))
    }

    func testEnabledUsesRemoteConfigValueAfterLocalOverride() throws {
        let flag = FeatureFlag.autoDownloadOnSubscribe
        let remoteKey = try XCTUnwrap(flag.remoteKey)
        let remoteConfigKey = RemoteConfigValueStore().key(for: remoteKey)
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
