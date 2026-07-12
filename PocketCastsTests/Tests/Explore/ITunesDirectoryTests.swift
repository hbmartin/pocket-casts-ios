import XCTest

@testable import podcasts

final class ITunesDirectoryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.registry.reset()
    }

    private func stubbedDirectory() -> ITunesDirectory {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return ITunesDirectory(session: URLSession(configuration: configuration))
    }

    // MARK: - URL construction

    func testTopPodcastsURLWithoutGenreUsesMarketingToolsV2() {
        let url = ITunesDirectory.topPodcastsURL(country: "us", genre: nil, limit: 50)
        XCTAssertEqual(url.absoluteString, "https://rss.marketingtools.apple.com/api/v2/us/podcasts/top/50/podcasts.json")
    }

    func testTopPodcastsURLWithGenreUsesClassicRSS() {
        let url = ITunesDirectory.topPodcastsURL(country: "us", genre: .technology, limit: 25)
        XCTAssertEqual(url.absoluteString, "https://itunes.apple.com/us/rss/toppodcasts/limit=25/genre=1318/json")
    }

    func testTopPodcastsURLNormalizesCountry() {
        XCTAssertTrue(ITunesDirectory.topPodcastsURL(country: "FR", genre: nil).absoluteString.contains("/v2/fr/"))
        // Numeric or non-ISO regions (e.g. UN M49 "150" for Europe) fall back to the US storefront
        XCTAssertTrue(ITunesDirectory.topPodcastsURL(country: "150", genre: nil).absoluteString.contains("/v2/us/"))
        XCTAssertTrue(ITunesDirectory.topPodcastsURL(country: "", genre: nil).absoluteString.contains("/v2/us/"))
    }

    func testNormalizedCountryFallsBackToUS() {
        XCTAssertEqual(ITunesDirectory.normalizedCountry("GB"), "gb")
        XCTAssertEqual(ITunesDirectory.normalizedCountry(nil), "us")
        XCTAssertEqual(ITunesDirectory.normalizedCountry("001"), "us")
        XCTAssertEqual(ITunesDirectory.normalizedCountry("Latn"), "us")
    }

    func testLookupURL() {
        let url = ITunesDirectory.lookupURL(id: "1200361736")
        XCTAssertEqual(url.absoluteString, "https://itunes.apple.com/lookup?id=1200361736&entity=podcast")
    }

    func testSearchURLEscapesTerm() throws {
        let url = ITunesDirectory.searchURL(term: "swift over coffee & tea", country: "GB", limit: 10)

        XCTAssertEqual(url.host(), "itunes.apple.com")
        XCTAssertEqual(url.path(), "/search")
        XCTAssertFalse(url.absoluteString.contains(" "), "spaces must be percent-encoded")

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try XCTUnwrap(components.queryItems)
        XCTAssertEqual(items.first { $0.name == "media" }?.value, "podcast")
        XCTAssertEqual(items.first { $0.name == "term" }?.value, "swift over coffee & tea")
        XCTAssertEqual(items.first { $0.name == "country" }?.value, "gb")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "10")
    }

    // MARK: - Artwork upscaling

    func testUpscalesMarketingToolsArtwork() {
        XCTAssertEqual(
            ITunesDirectory.upscaledArtworkURL("https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/ab/mza_1.jpg/100x100bb.png"),
            "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/ab/mza_1.jpg/600x600bb.png"
        )
    }

    func testUpscalesClassicRSSArtwork() {
        XCTAssertEqual(
            ITunesDirectory.upscaledArtworkURL("https://is1-ssl.mzstatic.com/image/thumb/Podcasts124/v4/c7/mza_2.png/170x170bb.png"),
            "https://is1-ssl.mzstatic.com/image/thumb/Podcasts124/v4/c7/mza_2.png/600x600bb.png"
        )
    }

    func testUpscalesSearchArtworkWithJpgExtension() {
        XCTAssertEqual(
            ITunesDirectory.upscaledArtworkURL("https://example.com/image/thumb/mza_3.jpg/60x60bb.jpg"),
            "https://example.com/image/thumb/mza_3.jpg/600x600bb.jpg"
        )
    }

    func testLeavesUnrecognizedArtworkURLUntouched() {
        XCTAssertEqual(ITunesDirectory.upscaledArtworkURL("https://example.com/artwork.png"), "https://example.com/artwork.png")
        XCTAssertNil(ITunesDirectory.upscaledArtworkURL(nil))
        XCTAssertNil(ITunesDirectory.upscaledArtworkURL(""))
    }

    // MARK: - Chart decoding (marketing-tools v2 shape)

    func testTopPodcastsDecodesMarketingToolsFeed() async throws {
        StubURLProtocol.registry.stub(url: ITunesDirectory.topPodcastsURL(country: "us", genre: nil, limit: 50), data: Data(Self.marketingToolsFixture.utf8))

        let podcasts = try await stubbedDirectory().topPodcasts(country: "us", genre: nil)

        XCTAssertEqual(podcasts.count, 2)
        XCTAssertEqual(podcasts[0].id, "1200361736")
        XCTAssertEqual(podcasts[0].title, "The Daily")
        XCTAssertEqual(podcasts[0].author, "The New York Times")
        XCTAssertEqual(podcasts[0].artworkURL, "https://example.com/image/thumb/mza_1.jpg/600x600bb.png")
        XCTAssertNil(podcasts[0].feedURL, "chart entries carry no feed URL until looked up")
        XCTAssertEqual(podcasts[1].id, "1322200189")
    }

    // MARK: - Chart decoding (classic RSS genre shape)

    func testTopPodcastsDecodesClassicGenreFeed() async throws {
        StubURLProtocol.registry.stub(url: ITunesDirectory.topPodcastsURL(country: "us", genre: .technology, limit: 50), data: Data(Self.classicRSSFixture.utf8))

        let podcasts = try await stubbedDirectory().topPodcasts(country: "us", genre: .technology)

        XCTAssertEqual(podcasts.count, 2)
        XCTAssertEqual(podcasts[0].id, "1502871393")
        XCTAssertEqual(podcasts[0].title, "All-In")
        XCTAssertEqual(podcasts[0].author, "All-In Podcast, LLC")
        XCTAssertEqual(podcasts[0].artworkURL, "https://example.com/image/thumb/mza_2.png/600x600bb.png", "largest listed image is taken then upscaled")
        XCTAssertNil(podcasts[0].feedURL)
    }

    func testClassicFeedWithSingleEntryObjectDecodes() async throws {
        StubURLProtocol.registry.stub(url: ITunesDirectory.topPodcastsURL(country: "us", genre: .comedy, limit: 50), data: Data(Self.classicRSSSingleEntryFixture.utf8))

        let podcasts = try await stubbedDirectory().topPodcasts(country: "us", genre: .comedy)

        XCTAssertEqual(podcasts.count, 1)
        XCTAssertEqual(podcasts[0].id, "99999")
        XCTAssertEqual(podcasts[0].title, "Lone Show")
    }

    // MARK: - Search decoding

    func testSearchDecodesResultsIncludingFeedURL() async throws {
        StubURLProtocol.registry.stub(url: ITunesDirectory.searchURL(term: "swift", country: "us", limit: 50), data: Data(Self.searchFixture.utf8))

        let podcasts = try await stubbedDirectory().search(term: "swift", country: "us")

        XCTAssertEqual(podcasts.count, 1)
        XCTAssertEqual(podcasts[0].id, "1435076502")
        XCTAssertEqual(podcasts[0].title, "Swift over Coffee")
        XCTAssertEqual(podcasts[0].author, "Paul Hudson and Mikaela Caron")
        XCTAssertEqual(podcasts[0].feedURL, "https://anchor.fm/s/572fc68/podcast/rss")
        XCTAssertEqual(podcasts[0].artworkURL, "https://example.com/image/thumb/mza_4.jpg/600x600bb.jpg", "artworkUrl600 is preferred when present")
    }

    // MARK: - Lookup decoding

    func testLookupReturnsFeedURL() async throws {
        StubURLProtocol.registry.stub(url: ITunesDirectory.lookupURL(id: "1200361736"), data: Data(Self.lookupFixture.utf8))

        let feedURL = try await stubbedDirectory().lookupFeedURL(id: "1200361736")

        XCTAssertEqual(feedURL, "https://feeds.simplecast.com/Sl5CSM3S")
    }

    func testLookupWithNoResultsReturnsNil() async throws {
        StubURLProtocol.registry.stub(url: ITunesDirectory.lookupURL(id: "0"), data: Data(#"{"resultCount":0,"results":[]}"#.utf8))

        let feedURL = try await stubbedDirectory().lookupFeedURL(id: "0")

        XCTAssertNil(feedURL)
    }

    // MARK: - Chart entry → feed URL resolution flow

    func testChartEntryResolvesToFeedURL() async throws {
        StubURLProtocol.registry.stub(url: ITunesDirectory.topPodcastsURL(country: "us", genre: nil, limit: 50), data: Data(Self.marketingToolsFixture.utf8))
        StubURLProtocol.registry.stub(url: ITunesDirectory.lookupURL(id: "1200361736"), data: Data(Self.lookupFixture.utf8))

        let directory = stubbedDirectory()
        let charts = try await directory.topPodcasts(country: "us", genre: nil)
        let first = try XCTUnwrap(charts.first)
        XCTAssertNil(first.feedURL)

        let feedURL = try await directory.lookupFeedURL(id: first.id)

        XCTAssertEqual(feedURL, "https://feeds.simplecast.com/Sl5CSM3S")
    }

    // MARK: - Error handling

    func testNon200ResponseThrows() async {
        StubURLProtocol.registry.stub(url: ITunesDirectory.lookupURL(id: "42"), data: Data(), statusCode: 503)

        do {
            _ = try await stubbedDirectory().lookupFeedURL(id: "42")
            XCTFail("expected badResponse to be thrown")
        } catch {
            XCTAssertTrue(error is ITunesDirectory.DirectoryError)
        }
    }

    // MARK: - Fixtures

    /// Trimmed real response shape from `https://rss.marketingtools.apple.com/api/v2/us/podcasts/top/50/podcasts.json`
    private static let marketingToolsFixture = """
    {"feed":{"title":"Top Shows","country":"us","updated":"Sun, 12 Jul 2026 08:43:11 +0000","results":[
      {"artistName":"The New York Times","id":"1200361736","name":"The Daily","kind":"podcasts",
       "artworkUrl100":"https://example.com/image/thumb/mza_1.jpg/100x100bb.png",
       "genres":[{"genreId":"1489","name":"News","url":"https://itunes.apple.com/us/genre/id1489"}],
       "url":"https://podcasts.apple.com/us/podcast/the-daily/id1200361736"},
      {"artistName":"Audiochuck","id":"1322200189","name":"Crime Junkie","kind":"podcasts",
       "artworkUrl100":"https://example.com/image/thumb/mza_5.jpg/100x100bb.png",
       "genres":[{"genreId":"1488","name":"True Crime","url":"https://itunes.apple.com/us/genre/id1488"}],
       "url":"https://podcasts.apple.com/us/podcast/crime-junkie/id1322200189"}
    ]}}
    """

    /// Trimmed real response shape from `https://itunes.apple.com/us/rss/toppodcasts/limit=50/genre=1318/json`
    private static let classicRSSFixture = """
    {"feed":{"entry":[
      {"im:name":{"label":"All-In"},
       "im:image":[
         {"label":"https://example.com/image/thumb/mza_2.png/55x55bb.png","attributes":{"height":"55"}},
         {"label":"https://example.com/image/thumb/mza_2.png/60x60bb.png","attributes":{"height":"60"}},
         {"label":"https://example.com/image/thumb/mza_2.png/170x170bb.png","attributes":{"height":"170"}}],
       "summary":{"label":"A podcast."},
       "im:artist":{"label":"All-In Podcast, LLC"},
       "title":{"label":"All-In - All-In Podcast, LLC"},
       "id":{"label":"https://podcasts.apple.com/us/podcast/all-in/id1502871393?uo=2","attributes":{"im:id":"1502871393"}},
       "category":{"attributes":{"im:id":"1318","term":"Technology","label":"Technology"}}},
      {"im:name":{"label":"Acquired"},
       "im:image":[{"label":"https://example.com/image/thumb/mza_6.png/170x170bb.png","attributes":{"height":"170"}}],
       "im:artist":{"label":"Ben Gilbert and David Rosenthal"},
       "id":{"label":"https://podcasts.apple.com/us/podcast/acquired/id1050462261?uo=2","attributes":{"im:id":"1050462261"}}}
    ]}}
    """

    /// Apple collapses a single-entry feed to a bare object rather than an array
    private static let classicRSSSingleEntryFixture = """
    {"feed":{"entry":
      {"im:name":{"label":"Lone Show"},
       "im:image":[{"label":"https://example.com/image/thumb/mza_7.png/170x170bb.png","attributes":{"height":"170"}}],
       "im:artist":{"label":"Solo Author"},
       "id":{"label":"https://podcasts.apple.com/us/podcast/lone-show/id99999?uo=2","attributes":{"im:id":"99999"}}}
    }}
    """

    /// Trimmed real response shape from `https://itunes.apple.com/search?media=podcast&term=…`
    private static let searchFixture = """
    {"resultCount":1,"results":[
      {"wrapperType":"track","kind":"podcast","collectionId":1435076502,"trackId":1435076502,
       "artistName":"Paul Hudson and Mikaela Caron","collectionName":"Swift over Coffee","trackName":"Swift over Coffee",
       "feedUrl":"https://anchor.fm/s/572fc68/podcast/rss",
       "artworkUrl100":"https://example.com/image/thumb/mza_4.jpg/100x100bb.jpg",
       "artworkUrl600":"https://example.com/image/thumb/mza_4.jpg/600x600bb.jpg"}
    ]}
    """

    /// Trimmed real response shape from `https://itunes.apple.com/lookup?id=1200361736&entity=podcast`
    private static let lookupFixture = """
    {"resultCount":1,"results":[
      {"wrapperType":"track","kind":"podcast","collectionId":1200361736,"trackId":1200361736,
       "artistName":"The New York Times","collectionName":"The Daily","trackName":"The Daily",
       "feedUrl":"https://feeds.simplecast.com/Sl5CSM3S",
       "artworkUrl600":"https://example.com/image/thumb/mza_1.jpg/600x600bb.jpg"}
    ]}
    """
}

// MARK: - URLProtocol stub

/// Serves canned responses keyed by absolute URL so `ITunesDirectory` can be
/// exercised end-to-end (request building through decoding) without a network.
private final class StubURLProtocol: URLProtocol {
    // @unchecked Sendable: all mutable state is guarded by the NSLock below.
    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var responses = [String: (statusCode: Int, data: Data)]()

        func stub(url: URL, data: Data, statusCode: Int = 200) {
            lock.lock()
            defer { lock.unlock() }
            responses[url.absoluteString] = (statusCode, data)
        }

        func response(for url: URL?) -> (statusCode: Int, data: Data)? {
            lock.lock()
            defer { lock.unlock() }
            guard let url else { return nil }
            return responses[url.absoluteString]
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            responses.removeAll()
        }
    }

    static let registry = Registry()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let stub = Self.registry.response(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
