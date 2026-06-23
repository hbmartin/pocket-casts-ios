import XCTest
@testable import podcasts

/// Tests for the `String.localized` server-string mapping helpers in LocalizationHelpers.swift.
/// Pure logic (no singletons / DB / UI), so safe and fast. Assertions compare against the same `L10n`
/// values the production code returns, so they hold regardless of the active locale.
final class LocalizationHelpersTests: XCTestCase {

    // MARK: - localized

    func testLocalized_mapsKnownDiscoverTitles() {
        XCTAssertEqual("featured".localized, L10n.discoverFeatured)
        XCTAssertEqual("popular".localized, L10n.discoverPopular)
        XCTAssertEqual("trending".localized, L10n.discoverTrending)
        XCTAssertEqual("browse by category".localized, L10n.discoverBrowseByCategory)
    }

    func testLocalized_mapsKnownCategories() {
        XCTAssertEqual("comedy".localized, L10n.discoverBrowseByCategoryComedy)
        XCTAssertEqual("true crime".localized, L10n.discoverBrowseByCategoryTrueCrime)
        XCTAssertEqual("news & politics".localized, L10n.discoverBrowseByCategoryNewsAndPolitics)
        XCTAssertEqual("tv & film".localized, L10n.discoverBrowseByCategoryTvAndFilm)
    }

    func testLocalized_mapsKnownRegions() {
        XCTAssertEqual("france".localized, L10n.discoverRegionFrance)
        XCTAssertEqual("united states".localized, L10n.discoverRegionUnitedStates)
        XCTAssertEqual("worldwide".localized, L10n.discoverRegionWorldwide)
    }

    func testLocalized_isCaseInsensitive() {
        XCTAssertEqual("COMEDY".localized, L10n.discoverBrowseByCategoryComedy)
        XCTAssertEqual("Technology".localized, L10n.discoverBrowseByCategoryTechnology)
        XCTAssertEqual("FEATURED".localized, L10n.discoverFeatured)
    }

    func testLocalized_passesThroughUnknownStrings() {
        XCTAssertEqual("a string the server never sends".localized, "a string the server never sends")
        XCTAssertEqual("".localized, "")
    }

    // MARK: - localized(with:)

    func testLocalizedWithArgs_handlesPopularInRegion() {
        XCTAssertEqual("popular in [regionname]".localized(with: "France"), L10n.discoverPopularIn("France"))
        // Case-insensitive match on the template key.
        XCTAssertEqual("Popular in [regionname]".localized(with: "Japan"), L10n.discoverPopularIn("Japan"))
    }

    func testLocalizedWithArgs_passesThroughByDefault() {
        XCTAssertEqual("some other server string".localized(with: "x"), "some other server string")
    }

    // MARK: - localized(seperatingWith:)

    func testLocalizedSeparatingWith_localizesFirstComponent() {
        let result = "comedy/extra".localized(seperatingWith: { $0 == "/" })
        XCTAssertEqual(result, L10n.discoverBrowseByCategoryComedy)
    }

    func testLocalizedSeparatingWith_passesThroughUnknownFirstComponent() {
        let result = "weirdcategory/extra".localized(seperatingWith: { $0 == "/" })
        XCTAssertEqual(result, "weirdcategory")
    }

    func testLocalizedSeparatingWith_localizesWholeStringWhenNoSeparator() {
        let result = "technology".localized(seperatingWith: { $0 == "/" })
        XCTAssertEqual(result, L10n.discoverBrowseByCategoryTechnology)
    }
}
