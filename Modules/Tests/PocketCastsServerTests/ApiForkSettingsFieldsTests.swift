import XCTest
import SwiftProtobuf

@testable import PocketCastsServer

/// Guards for the FORK hand-edits in api.pb.swift that add fork-reserved fields
/// 1001 (tap_to_play) and 1002 (seek_acceleration) to `Api_ChangeableSettings`
/// and `Api_NamedSettingsResponse`.
///
/// `jsonString()` fails loudly on any `_protobuf_nameMap` bytecode mistake (a wrong
/// byte hits a precondition at first use, a missing entry throws), so these tests are
/// the tripwire for regressions in the hand-edited generated file.
final class ApiForkSettingsFieldsTests: XCTestCase {

    // MARK: - nameMap / JSON encoding guards

    func testChangeableSettingsForkFieldsEncodeToJSON() throws {
        var settings = Api_ChangeableSettings()
        settings.tapToPlay.value.value = true
        settings.seekAcceleration.value.value = true

        let json = try settings.jsonString()

        XCTAssertTrue(json.contains("tapToPlay"), "JSON should use the camelCase name derived from tap_to_play: \(json)")
        XCTAssertTrue(json.contains("seekAcceleration"), "JSON should use the camelCase name derived from seek_acceleration: \(json)")
    }

    func testNamedSettingsResponseForkFieldsEncodeToJSON() throws {
        var settings = Api_NamedSettingsResponse()
        settings.tapToPlay.value.value = true
        settings.seekAcceleration.value.value = true

        let json = try settings.jsonString()

        XCTAssertTrue(json.contains("tapToPlay"), "JSON should use the camelCase name derived from tap_to_play: \(json)")
        XCTAssertTrue(json.contains("seekAcceleration"), "JSON should use the camelCase name derived from seek_acceleration: \(json)")
    }

    func testForkFieldsDecodeFromJSON() throws {
        // Exercises the nameMap in the JSON-name → field-number direction.
        let json = #"{"tapToPlay":{"value":true},"seekAcceleration":{"value":false}}"#

        let decoded = try Api_NamedSettingsResponse(jsonString: json)

        XCTAssertTrue(decoded.hasTapToPlay)
        XCTAssertTrue(decoded.tapToPlay.value.value)
        XCTAssertTrue(decoded.hasSeekAcceleration)
        XCTAssertFalse(decoded.seekAcceleration.value.value)
    }

    // MARK: - Binary round-trips (decodeMessage + traverse + ==)

    func testChangeableSettingsForkFieldsBinaryRoundTrip() throws {
        var settings = Api_ChangeableSettings()
        settings.tapToPlay.value.value = true
        settings.tapToPlay.modifiedAt = Google_Protobuf_Timestamp(date: Date())
        settings.seekAcceleration.value.value = true
        settings.seekAcceleration.modifiedAt = Google_Protobuf_Timestamp(date: Date())

        let decoded = try Api_ChangeableSettings(serializedBytes: settings.serializedData())

        XCTAssertTrue(decoded.hasTapToPlay)
        XCTAssertTrue(decoded.tapToPlay.value.value)
        XCTAssertTrue(decoded.hasSeekAcceleration)
        XCTAssertTrue(decoded.seekAcceleration.value.value)
        XCTAssertEqual(decoded, settings, "Equality must consider the fork fields")
    }

    func testNamedSettingsResponseForkFieldsBinaryRoundTrip() throws {
        var settings = Api_NamedSettingsResponse()
        settings.tapToPlay.value.value = true
        settings.seekAcceleration.value.value = false
        settings.seekAcceleration.changed.value = true

        let decoded = try Api_NamedSettingsResponse(serializedBytes: settings.serializedData())

        XCTAssertTrue(decoded.hasTapToPlay)
        XCTAssertTrue(decoded.tapToPlay.value.value)
        XCTAssertTrue(decoded.hasSeekAcceleration)
        XCTAssertFalse(decoded.seekAcceleration.value.value)
        XCTAssertTrue(decoded.seekAcceleration.changed.value)
        XCTAssertEqual(decoded, settings, "Equality must consider the fork fields")
    }

    func testForkFieldsAreDistinguishedByEquality() {
        var lhs = Api_ChangeableSettings()
        var rhs = Api_ChangeableSettings()
        XCTAssertEqual(lhs, rhs)

        lhs.tapToPlay.value.value = true
        XCTAssertNotEqual(lhs, rhs)

        rhs.tapToPlay.value.value = true
        XCTAssertEqual(lhs, rhs)

        lhs.seekAcceleration.value.value = true
        XCTAssertNotEqual(lhs, rhs)
    }

    // MARK: - Highlights program fields (1014-1017, ADR-0016)

    func testHighlightSettingsFieldsRoundTripBothMessages() throws {
        var changeable = Api_ChangeableSettings()
        changeable.reviewHighlightAfterCapture.value.value = true
        changeable.highlightStylePreset.value.value = "atomic"
        changeable.highlightStyleCustom.value.value = "always start with a verb"
        changeable.highlightConfirmationStyle.value.value = 2

        let decodedChangeable = try Api_ChangeableSettings(serializedBytes: changeable.serializedData())
        XCTAssertTrue(decodedChangeable.reviewHighlightAfterCapture.value.value)
        XCTAssertEqual(decodedChangeable.highlightStylePreset.value.value, "atomic")
        XCTAssertEqual(decodedChangeable.highlightStyleCustom.value.value, "always start with a verb")
        XCTAssertEqual(decodedChangeable.highlightConfirmationStyle.value.value, 2)
        XCTAssertEqual(decodedChangeable, changeable)

        let json = try changeable.jsonString()
        XCTAssertTrue(json.contains("reviewHighlightAfterCapture"), json)
        XCTAssertTrue(json.contains("highlightConfirmationStyle"), json)

        var response = Api_NamedSettingsResponse()
        response.reviewHighlightAfterCapture.value.value = true
        response.highlightStylePreset.value.value = "atomic"
        let decodedResponse = try Api_NamedSettingsResponse(serializedBytes: response.serializedData())
        XCTAssertEqual(decodedResponse, response)
    }

    func testHighlightSettingsSyncThroughAppSettings() {
        var appSettings = AppSettings.defaults
        appSettings.reviewHighlightAfterCapture = true
        appSettings.highlightConfirmationStyle = 1

        var changeable = Api_ChangeableSettings()
        changeable.update(with: appSettings)
        XCTAssertTrue(changeable.hasReviewHighlightAfterCapture)
        XCTAssertTrue(changeable.reviewHighlightAfterCapture.value.value)
        XCTAssertEqual(changeable.highlightConfirmationStyle.value.value, 1)

        var response = Api_NamedSettingsResponse()
        response.highlightStyleCustom.value.value = "question form"
        response.highlightStyleCustom.modifiedAt = Google_Protobuf_Timestamp(date: Date())
        var applied = AppSettings.defaults
        applied.update(with: response)
        XCTAssertEqual(applied.highlightStyleCustom, "question form")
    }

    // MARK: - AppSettings wiring

    func testAppSettingsUpdatePopulatesForkFields() {
        var appSettings = AppSettings.defaults
        // the ModifiedDate wrapped-value setter stamps modifiedAt on change
        appSettings.tapToPlay = true
        appSettings.seekAcceleration = true

        var changeable = Api_ChangeableSettings()
        changeable.update(with: appSettings)

        XCTAssertTrue(changeable.hasTapToPlay)
        XCTAssertTrue(changeable.tapToPlay.value.value)
        XCTAssertTrue(changeable.hasSeekAcceleration)
        XCTAssertTrue(changeable.seekAcceleration.value.value)
    }

    func testAppSettingsUpdateAppliesForkFieldsFromResponse() {
        var response = Api_NamedSettingsResponse()
        response.tapToPlay.value.value = true
        response.tapToPlay.modifiedAt = Google_Protobuf_Timestamp(date: Date())
        response.seekAcceleration.value.value = true
        response.seekAcceleration.modifiedAt = Google_Protobuf_Timestamp(date: Date())

        var appSettings = AppSettings.defaults
        appSettings.update(with: response)

        XCTAssertTrue(appSettings.tapToPlay)
        XCTAssertTrue(appSettings.seekAcceleration)
    }
}
