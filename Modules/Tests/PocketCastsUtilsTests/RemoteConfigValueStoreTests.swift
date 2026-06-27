import XCTest
@testable import PocketCastsUtils

final class RemoteConfigValueStoreTests: XCTestCase {

    private let suiteName = "RemoteConfigValueStoreTests"
    private var defaults: UserDefaults!
    private var sut: RemoteConfigValueStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        sut = RemoteConfigValueStore(store: defaults, keyPrefix: "remote-config-")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        sut = nil
        super.tearDown()
    }

    private func seed(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: sut.key(for: key))
    }

    // MARK: - key prefixing

    func testKeyIsPrefixed() {
        XCTAssertEqual(sut.key(for: "myFlag"), "remote-config-myFlag")
    }

    // MARK: - missing keys

    func testMissingKeysReturnNil() {
        XCTAssertNil(sut.bool(forKey: "absent"))
        XCTAssertNil(sut.double(forKey: "absent"))
        XCTAssertNil(sut.int(forKey: "absent"))
    }

    // MARK: - bool coercion

    func testBoolFromBoolAndNumber() {
        seed(true, forKey: "b1"); XCTAssertEqual(sut.bool(forKey: "b1"), true)
        seed(false, forKey: "b2"); XCTAssertEqual(sut.bool(forKey: "b2"), false)
        seed(NSNumber(value: 1), forKey: "b3"); XCTAssertEqual(sut.bool(forKey: "b3"), true)
        seed(NSNumber(value: 0), forKey: "b4"); XCTAssertEqual(sut.bool(forKey: "b4"), false)
    }

    func testBoolFromStrings() {
        for truthy in ["true", "TRUE", "yes", "1"] {
            seed(truthy, forKey: "t"); XCTAssertEqual(sut.bool(forKey: "t"), true, "\(truthy)")
        }
        for falsy in ["false", "No", "0"] {
            seed(falsy, forKey: "f"); XCTAssertEqual(sut.bool(forKey: "f"), false, "\(falsy)")
        }
        seed("maybe", forKey: "u"); XCTAssertNil(sut.bool(forKey: "u"), "unrecognised string is nil")
    }

    // MARK: - double coercion

    func testDoubleCoercion() {
        seed(3.14, forKey: "d1"); XCTAssertEqual(sut.double(forKey: "d1"), 3.14)
        seed(NSNumber(value: 2.5), forKey: "d2"); XCTAssertEqual(sut.double(forKey: "d2"), 2.5)
        seed("1.5", forKey: "d3"); XCTAssertEqual(sut.double(forKey: "d3"), 1.5)
        seed("not-a-number", forKey: "d4"); XCTAssertNil(sut.double(forKey: "d4"))
    }

    // MARK: - int coercion

    func testIntCoercion() {
        seed(42, forKey: "i1"); XCTAssertEqual(sut.int(forKey: "i1"), 42)
        seed(NSNumber(value: 7), forKey: "i2"); XCTAssertEqual(sut.int(forKey: "i2"), 7)
        seed("99", forKey: "i3"); XCTAssertEqual(sut.int(forKey: "i3"), 99)
        seed("nope", forKey: "i4"); XCTAssertNil(sut.int(forKey: "i4"))
    }
}
