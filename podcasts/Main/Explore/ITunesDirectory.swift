import Foundation

/// A podcast discovered through Apple's public podcast directory.
nonisolated struct ExplorePodcast: Identifiable, Equatable, Sendable {
    /// Apple catalog identifier, used for iTunes lookups.
    let id: String
    let title: String
    let author: String
    /// Best available artwork URL, already upscaled where the URL shape allows it.
    let artworkURL: String?
    /// Present when the source response includes it (search/lookup results).
    /// Chart entries need a `lookupFeedURL(id:)` round trip to resolve this.
    let feedURL: String?
}

/// The fixed set of Apple podcast genres offered by the Explore tab.
/// Raw values are Apple's podcast genre IDs.
nonisolated enum ExploreGenre: Int, CaseIterable, Identifiable, Sendable {
    case arts = 1301
    case business = 1321
    case comedy = 1303
    case education = 1304
    case healthAndFitness = 1512
    case news = 1489
    case science = 1533
    case societyAndCulture = 1324
    case sports = 1545
    case technology = 1318
    case trueCrime = 1488
    case tvAndFilm = 1309

    var id: Int { rawValue }

    var localizedName: String {
        switch self {
        case .arts:
            L10n.discoverBrowseByCategoryArt
        case .business:
            L10n.discoverBrowseByCategoryBusiness
        case .comedy:
            L10n.discoverBrowseByCategoryComedy
        case .education:
            L10n.discoverBrowseByCategoryEducation
        case .healthAndFitness:
            L10n.discoverBrowseByCategoryHealthAndFitness
        case .news:
            L10n.discoverBrowseByCategoryNews
        case .science:
            L10n.discoverBrowseByCategoryScience
        case .societyAndCulture:
            L10n.discoverBrowseByCategorySocietyAndCulture
        case .sports:
            L10n.discoverBrowseByCategorySports
        case .technology:
            L10n.discoverBrowseByCategoryTechnology
        case .trueCrime:
            L10n.discoverBrowseByCategoryTrueCrime
        case .tvAndFilm:
            L10n.discoverBrowseByCategoryTvAndFilm
        }
    }
}

/// Serverless podcast discovery backed by Apple's keyless public endpoints:
/// the marketing-tools charts feed, the classic iTunes RSS genre charts, and
/// the iTunes Search/Lookup APIs. No Pocket Casts servers are involved.
nonisolated struct ITunesDirectory: Sendable {
    enum DirectoryError: Error {
        case badResponse
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Requests

    /// The top podcast charts for a country. With no genre this uses the modern
    /// marketing-tools v2 feed (which has no genre filtering); with a genre it
    /// uses the classic iTunes RSS chart, which does.
    func topPodcasts(country: String, genre: ExploreGenre?, limit: Int = 50) async throws -> [ExplorePodcast] {
        let data = try await fetch(Self.topPodcastsURL(country: country, genre: genre, limit: limit))

        if genre == nil {
            return try JSONDecoder().decode(MarketingToolsChart.self, from: data).feed.results.map(\.explorePodcast)
        }

        return try JSONDecoder().decode(ClassicChart.self, from: data).feed.entries.map(\.explorePodcast)
    }

    /// Resolves an Apple catalog ID (from a chart entry) to the podcast's RSS feed URL.
    func lookupFeedURL(id: String) async throws -> String? {
        let data = try await fetch(Self.lookupURL(id: id))

        return try JSONDecoder().decode(SearchResponse.self, from: data).results.first?.feedUrl
    }

    /// Full-text podcast search. Results include the feed URL directly.
    func search(term: String, country: String, limit: Int = 50) async throws -> [ExplorePodcast] {
        let data = try await fetch(Self.searchURL(term: term, country: country, limit: limit))

        return try JSONDecoder().decode(SearchResponse.self, from: data).results.compactMap(\.explorePodcast)
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw DirectoryError.badResponse
        }

        return data
    }

    // MARK: - URL construction

    /// The user's storefront country, or "us" when the region isn't a plain
    /// two-letter code Apple's endpoints understand.
    static var currentCountry: String {
        normalizedCountry(Locale.current.region?.identifier)
    }

    static func normalizedCountry(_ regionIdentifier: String?) -> String {
        guard let region = regionIdentifier?.lowercased(), region.count == 2, region.allSatisfy(\.isLetter) else {
            return "us"
        }

        return region
    }

    static func topPodcastsURL(country: String, genre: ExploreGenre?, limit: Int = 50) -> URL {
        let country = normalizedCountry(country)

        guard let genre else {
            return URL(string: "https://rss.marketingtools.apple.com/api/v2/\(country)/podcasts/top/\(limit)/podcasts.json")!
        }

        return URL(string: "https://itunes.apple.com/\(country)/rss/toppodcasts/limit=\(limit)/genre=\(genre.rawValue)/json")!
    }

    static func lookupURL(id: String) -> URL {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "entity", value: "podcast")
        ]

        return components.url!
    }

    static func searchURL(term: String, country: String, limit: Int = 50) -> URL {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: normalizedCountry(country)),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        return components.url!
    }

    // MARK: - Artwork

    /// Apple artwork URLs end in a dimension component like `.../mza_1.jpg/100x100bb.png`.
    /// Swapping the dimensions in that final component requests a larger render.
    static func upscaledArtworkURL(_ urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty else { return nil }

        guard let range = urlString.range(of: #"/\d{2,4}x\d{2,4}(bb)?(\.[A-Za-z]+)$"#, options: .regularExpression),
              let extensionIndex = urlString[range].lastIndex(of: ".") else {
            return urlString
        }

        return urlString.replacingCharacters(in: range, with: "/600x600bb\(urlString[extensionIndex...])")
    }
}

// MARK: - Response shapes

/// `https://rss.marketingtools.apple.com/api/v2/<country>/podcasts/top/<limit>/podcasts.json`
/// → `{"feed":{"results":[{"artistName":…,"id":…,"name":…,"artworkUrl100":…,"url":…}]}}`
nonisolated private struct MarketingToolsChart: Decodable {
    struct Feed: Decodable {
        let results: [Entry]
    }

    struct Entry: Decodable {
        let id: String
        let name: String
        let artistName: String?
        let artworkUrl100: String?

        var explorePodcast: ExplorePodcast {
            ExplorePodcast(id: id,
                           title: name,
                           author: artistName ?? "",
                           artworkURL: ITunesDirectory.upscaledArtworkURL(artworkUrl100),
                           feedURL: nil)
        }
    }

    let feed: Feed
}

/// `https://itunes.apple.com/<country>/rss/toppodcasts/limit=<n>/genre=<id>/json`
/// → `{"feed":{"entry":[{"im:name":{"label":…},"im:artist":{"label":…},"im:image":[…],"id":{"attributes":{"im:id":…}}}]}}`
nonisolated private struct ClassicChart: Decodable {
    struct Feed: Decodable {
        let entries: [Entry]

        private enum CodingKeys: String, CodingKey {
            case entry
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Apple collapses single-entry feeds to a bare object instead of an array
            if let list = try? container.decode([Entry].self, forKey: .entry) {
                entries = list
            } else if let single = try? container.decode(Entry.self, forKey: .entry) {
                entries = [single]
            } else {
                entries = []
            }
        }
    }

    struct Entry: Decodable {
        struct Label: Decodable {
            let label: String
        }

        struct EntryId: Decodable {
            struct Attributes: Decodable {
                let imId: String

                private enum CodingKeys: String, CodingKey {
                    case imId = "im:id"
                }
            }

            let attributes: Attributes
        }

        let name: Label
        let artist: Label?
        let images: [Label]?
        let entryId: EntryId

        private enum CodingKeys: String, CodingKey {
            case name = "im:name"
            case artist = "im:artist"
            case images = "im:image"
            case entryId = "id"
        }

        var explorePodcast: ExplorePodcast {
            ExplorePodcast(id: entryId.attributes.imId,
                           title: name.label,
                           author: artist?.label ?? "",
                           artworkURL: ITunesDirectory.upscaledArtworkURL(images?.last?.label),
                           feedURL: nil)
        }
    }

    let feed: Feed
}

/// `https://itunes.apple.com/search?media=podcast&…` and `https://itunes.apple.com/lookup?id=…`
/// → `{"resultCount":n,"results":[{"collectionId":…,"collectionName":…,"artistName":…,"feedUrl":…,"artworkUrl600":…}]}`
nonisolated private struct SearchResponse: Decodable {
    struct Result: Decodable {
        let collectionId: Int?
        let trackId: Int?
        let collectionName: String?
        let trackName: String?
        let artistName: String?
        let feedUrl: String?
        let artworkUrl600: String?
        let artworkUrl100: String?

        var explorePodcast: ExplorePodcast? {
            guard let id = collectionId ?? trackId, let title = collectionName ?? trackName else { return nil }

            return ExplorePodcast(id: String(id),
                                  title: title,
                                  author: artistName ?? "",
                                  artworkURL: artworkUrl600 ?? ITunesDirectory.upscaledArtworkURL(artworkUrl100),
                                  feedURL: feedUrl)
        }
    }

    let results: [Result]
}
