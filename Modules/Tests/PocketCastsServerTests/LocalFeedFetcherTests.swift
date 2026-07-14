import Foundation
import Synchronization
import Testing
@testable import PocketCastsServer

/// A `URLProtocol` serving canned responses keyed by credential-stripped absolute URL,
/// recording every request's URL and `Authorization` header. Install on an ephemeral
/// `URLSessionConfiguration` and reset routes per test (suites using it are `.serialized`
/// because the routing table is process-wide).
final class StubFeedURLProtocol: URLProtocol {
    struct StubResponse {
        var statusCode: Int = 200
        var body = Data()
    }

    struct RecordedRequest {
        var url: String
        var authorization: String?
    }

    private static let state = Mutex<(routes: [String: StubResponse], recorded: [RecordedRequest])>(([:], []))

    static func reset(routes: [String: StubResponse]) {
        state.withLock { $0 = (routes, []) }
    }

    static var recordedRequests: [RecordedRequest] {
        state.withLock { $0.recorded }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubFeedURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// Routes are keyed without userinfo, so `user:pass@host` request URLs hit the same stub.
    private static func routeKey(for url: URL) -> String {
        LocalFeedURL.removingCredentials(from: url.absoluteString)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let stub = Self.state.withLock { state -> StubResponse? in
            state.recorded.append(RecordedRequest(url: Self.routeKey(for: url), authorization: authorization))
            return state.routes[Self.routeKey(for: url)]
        }

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }

        let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Builds a minimal parseable RSS page with identity-bearing items and an optional
/// RFC 5005 `rel="next"` link.
func feedPageXML(title: String = "Paged Show", itemGuids: [String], nextHref: String? = nil) -> Data {
    let nextLink = nextHref.map { #"<atom:link rel="next" href="\#($0)"/>"# } ?? ""
    let items = itemGuids.map { guid in
        """
        <item>
          <title>\(guid)</title>
          <guid isPermaLink="false">\(guid)</guid>
          <enclosure url="https://example.com/\(guid).mp3" length="1" type="audio/mpeg"/>
        </item>
        """
    }.joined(separator: "\n")

    return Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
      <channel>
        <title>\(title)</title>
        \(nextLink)
        \(items)
      </channel>
    </rss>
    """.utf8)
}

extension GlobalSeamSerializedTests {
@Suite("LocalFeedFetcher pagination auth", .serialized)
struct LocalFeedFetcherTests {
    private static let basicUserPass = "Basic \(Data("user:pass".utf8).base64EncodedString())"

    @Test("passed-in credentials carry to same-origin next pages, resolving relative hrefs")
    func credentialsCarryToRelativeNextPages() async throws {
        StubFeedURLProtocol.reset(routes: [
            "https://example.com/feeds/feed.xml": .init(body: feedPageXML(itemGuids: ["ep-1"], nextHref: "page2.xml")),
            "https://example.com/feeds/page2.xml": .init(body: feedPageXML(itemGuids: ["ep-2"]))
        ])

        let fetcher = LocalFeedFetcher(session: StubFeedURLProtocol.session())
        let feed = try await fetcher.fetchFeed(url: "https://example.com/feeds/feed.xml", followingPages: true, credentials: ("user", "pass"))

        #expect(feed.items.map(\.guid) == ["ep-1", "ep-2"])
        let requests = StubFeedURLProtocol.recordedRequests
        #expect(requests.map(\.url) == ["https://example.com/feeds/feed.xml", "https://example.com/feeds/page2.xml"],
                "the relative next href must resolve against the page that linked it")
        #expect(requests.map(\.authorization) == [Self.basicUserPass, Self.basicUserPass],
                "page two must be fetched with the same credentials as page one")
    }

    @Test("userinfo credentials from page one carry to next pages")
    func userinfoCredentialsCarryToNextPages() async throws {
        StubFeedURLProtocol.reset(routes: [
            "https://example.com/feed.xml": .init(body: feedPageXML(itemGuids: ["ep-1"], nextHref: "https://example.com/page2.xml")),
            "https://example.com/page2.xml": .init(body: feedPageXML(itemGuids: ["ep-2"]))
        ])

        let fetcher = LocalFeedFetcher(session: StubFeedURLProtocol.session())
        let feed = try await fetcher.fetchFeed(url: "https://user:pass@example.com/feed.xml", followingPages: true)

        #expect(feed.items.map(\.guid) == ["ep-1", "ep-2"])
        #expect(StubFeedURLProtocol.recordedRequests.map(\.authorization) == [Self.basicUserPass, Self.basicUserPass])
    }

    @Test("credentials never follow a next link to another origin")
    func credentialsAreNotForwardedCrossOrigin() async throws {
        StubFeedURLProtocol.reset(routes: [
            "https://example.com/feed.xml": .init(body: feedPageXML(itemGuids: ["ep-1"], nextHref: "https://other.example.org/page2.xml")),
            "https://other.example.org/page2.xml": .init(body: feedPageXML(itemGuids: ["ep-2"]))
        ])

        let fetcher = LocalFeedFetcher(session: StubFeedURLProtocol.session())
        let feed = try await fetcher.fetchFeed(url: "https://example.com/feed.xml", followingPages: true, credentials: ("user", "pass"))

        #expect(feed.items.map(\.guid) == ["ep-1", "ep-2"], "the page itself is still fetched, just without the credential")
        #expect(StubFeedURLProtocol.recordedRequests.map(\.authorization) == [Self.basicUserPass, nil])
    }

    @Test("a failing next page keeps the pages fetched so far")
    func failingPageKeepsPartialHistory() async throws {
        StubFeedURLProtocol.reset(routes: [
            "https://example.com/feed.xml": .init(body: feedPageXML(itemGuids: ["ep-1"], nextHref: "page2.xml")),
            "https://example.com/page2.xml": .init(statusCode: 500)
        ])

        let fetcher = LocalFeedFetcher(session: StubFeedURLProtocol.session())
        let feed = try await fetcher.fetchFeed(url: "https://example.com/feed.xml", followingPages: true)

        #expect(feed.items.map(\.guid) == ["ep-1"])
        #expect(feed.nextPageURL == nil)
    }
}
}

@Suite("LocalFeedURL same-origin")
struct LocalFeedURLSameOriginTests {
    @Test("matches scheme, host and port; differs otherwise")
    func sameOriginBoundaries() throws {
        func url(_ string: String) throws -> URL { try #require(URL(string: string)) }

        #expect(LocalFeedURL.isSameOrigin(try url("https://example.com/a.mp3"), try url("HTTPS://EXAMPLE.com/feed.xml")))
        #expect(!LocalFeedURL.isSameOrigin(try url("http://example.com/a.mp3"), try url("https://example.com/feed.xml")))
        #expect(!LocalFeedURL.isSameOrigin(try url("https://cdn.example.com/a.mp3"), try url("https://example.com/feed.xml")))
        #expect(!LocalFeedURL.isSameOrigin(try url("https://example.com:8443/a.mp3"), try url("https://example.com/feed.xml")))
        #expect(!LocalFeedURL.isSameOrigin(try url("file:///a.mp3"), try url("https://example.com/feed.xml")))
    }
}
