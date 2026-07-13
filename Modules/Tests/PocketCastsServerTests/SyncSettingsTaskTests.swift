import XCTest
@testable import PocketCastsServer
import SwiftProtobuf
@testable import PocketCastsUtils

class SyncSettingsTaskTests: XCTestCase {

    private let userDefaultsSuiteName = "PocketCastsTests-SyncSettingsTaskTests"
    private let defaultsKey = "app_settings"
    private let token = "1234"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
        FeatureFlagMock().set(.settingsSync, value: true)
    }

    override func tearDown() {
        FeatureFlagMock().reset()
    }

    /// Tests sending a request with updates from `SettingsStore`
    func testRequest() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: userDefaultsSuiteName), "User Defaults suite should load")

        XCTAssertNil(defaults.data(forKey: defaultsKey), "User Defaults data should not exist yet for \(defaultsKey)")

        let store = SettingsStore(userDefaults: defaults, key: defaultsKey, value: AppSettings.defaults)
        let changedValue = true
        let changedDate = Date()
        store.openLinks = changedValue

        let expectation = XCTestExpectation(description: "Request method should be called")
        let task = SyncSettingsTask(appSettings: store, urlConnection: URLConnection { urlRequest in

            let data = try XCTUnwrap(urlRequest.httpBody, "Request body should exist")
            let request = try Api_NamedSettingsRequest(serializedBytes: data)

            XCTAssertTrue(request.changedSettings.openLinks.hasValue, "Change value should be included")
            XCTAssertEqual(request.changedSettings.openLinks.modifiedAt.timeIntervalSinceReferenceDate, changedDate.timeIntervalSinceReferenceDate, accuracy: 0.01, "Modified at should be around the time the value was updated")
            XCTAssertEqual(request.changedSettings.openLinks.value.value, changedValue, "Value should be changed")
            XCTAssertFalse(request.changedSettings.rowAction.hasChanged, "Unchanged value should not be included")
            XCTAssertFalse(request.changedSettings.rowAction.hasValue, "Unchanged value should not be included")

            let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)

            expectation.fulfill()
            return (Data(), response)
        })

        task.apiTokenAcquired(token: token)

        wait(for: [expectation])
    }

    /// Tests sending a response with updates from `SettingsStore`
    func testResponse() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: userDefaultsSuiteName), "User Defaults suite should load")

        XCTAssertNil(defaults.data(forKey: defaultsKey), "User Defaults data should not exist yet for \(defaultsKey)")

        let store = SettingsStore(userDefaults: defaults, key: defaultsKey, value: AppSettings.defaults)
        let changedValue = true
        let changedDate = Date()

        XCTAssertFalse(store.openLinks, "Initial value should be false")

        let expectation = XCTestExpectation(description: "Request method should be called")
        let task = SyncSettingsTask(appSettings: store, urlConnection: URLConnection { urlRequest in

            var serverResponse = Api_NamedSettingsResponse()
            serverResponse.openLinks.value.value = changedValue
            serverResponse.openLinks.modifiedAt = Google_Protobuf_Timestamp(date: changedDate)
            let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)

            let data = try! XCTUnwrap(serverResponse.serializedData(), "Response should serialize to Data")

            expectation.fulfill()

            return (data, response)
        })

        task.apiTokenAcquired(token: token)

        wait(for: [expectation])

        XCTAssertEqual(store.openLinks, changedValue, "Value should be changed")
        XCTAssertNil(store.$openLinks.modifiedAt, "Modified date should be nil")
    }

    // MARK: - FORK fields (1001 tap_to_play / 1002 seek_acceleration)

    /// Tests that changed fork settings are uploaded in the request
    func testRequestIncludesForkFields() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: userDefaultsSuiteName), "User Defaults suite should load")

        let store = SettingsStore(userDefaults: defaults, key: defaultsKey, value: AppSettings.defaults)
        store.tapToPlay = true
        store.seekAcceleration = true

        let expectation = XCTestExpectation(description: "Request method should be called")
        let task = SyncSettingsTask(appSettings: store, urlConnection: URLConnection { urlRequest in

            let data = try XCTUnwrap(urlRequest.httpBody, "Request body should exist")
            let request = try Api_NamedSettingsRequest(serializedBytes: data)

            XCTAssertTrue(request.changedSettings.tapToPlay.hasValue, "Changed tapToPlay should be included")
            XCTAssertTrue(request.changedSettings.tapToPlay.value.value, "tapToPlay value should be uploaded")
            XCTAssertTrue(request.changedSettings.seekAcceleration.hasValue, "Changed seekAcceleration should be included")
            XCTAssertTrue(request.changedSettings.seekAcceleration.value.value, "seekAcceleration value should be uploaded")

            let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)

            expectation.fulfill()
            return (Data(), response)
        })

        task.apiTokenAcquired(token: token)

        wait(for: [expectation])
    }

    /// Tests that fork settings in the response are applied to the store
    func testResponseAppliesForkFields() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: userDefaultsSuiteName), "User Defaults suite should load")

        let store = SettingsStore(userDefaults: defaults, key: defaultsKey, value: AppSettings.defaults)

        XCTAssertFalse(store.tapToPlay, "Initial value should be false")
        XCTAssertFalse(store.seekAcceleration, "Initial value should be false")

        let expectation = XCTestExpectation(description: "Request method should be called")
        let task = SyncSettingsTask(appSettings: store, urlConnection: URLConnection { urlRequest in

            var serverResponse = Api_NamedSettingsResponse()
            serverResponse.tapToPlay.value.value = true
            serverResponse.tapToPlay.modifiedAt = Google_Protobuf_Timestamp(date: Date())
            serverResponse.seekAcceleration.value.value = true
            serverResponse.seekAcceleration.modifiedAt = Google_Protobuf_Timestamp(date: Date())
            let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)

            let data = try! XCTUnwrap(serverResponse.serializedData(), "Response should serialize to Data")

            expectation.fulfill()

            return (data, response)
        })

        task.apiTokenAcquired(token: token)

        wait(for: [expectation])

        XCTAssertTrue(store.tapToPlay, "tapToPlay should be applied from the response")
        XCTAssertTrue(store.seekAcceleration, "seekAcceleration should be applied from the response")
    }

    /// A server that strips the unknown fork fields responds with epoch modifiedAt values;
    /// the local (newer) values must survive the merge.
    func testServerStrippingForkFieldsPreservesLocalValues() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: userDefaultsSuiteName), "User Defaults suite should load")

        let store = SettingsStore(userDefaults: defaults, key: defaultsKey, value: AppSettings.defaults)
        store.tapToPlay = true
        store.seekAcceleration = true

        let expectation = XCTestExpectation(description: "Request method should be called")
        let task = SyncSettingsTask(appSettings: store, urlConnection: URLConnection { urlRequest in

            // response without the fork fields, as the production server would send
            let serverResponse = Api_NamedSettingsResponse()
            let response = HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)

            let data = try! XCTUnwrap(serverResponse.serializedData(), "Response should serialize to Data")

            expectation.fulfill()

            return (data, response)
        })

        task.apiTokenAcquired(token: token)

        wait(for: [expectation])

        XCTAssertTrue(store.tapToPlay, "Local tapToPlay should survive a server that drops the field")
        XCTAssertTrue(store.seekAcceleration, "Local seekAcceleration should survive a server that drops the field")
    }
}
