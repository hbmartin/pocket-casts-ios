import Foundation

struct PredictiveSearchEnvelope: Decodable {
    public let results: [PredictiveSearchResult]
}

public struct PredictivePodcastSearchResult: Codable, Hashable {
    public let uuid: String
    let title: String
    let author: String
    public let isExplicit: Bool?

    enum CodingKeys: String, CodingKey {
        case uuid, title, author
        case isExplicit = "explicit"
    }
}

public enum PredictiveSearchResultType: Hashable {
    case unknown(String)
    case term(String)
    case podcast(PredictivePodcastSearchResult)
}

public struct PredictiveSearchResult: Decodable, Hashable {
    public let type: PredictiveSearchResultType

    enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
            case "term":
                let value = try container.decode(String.self, forKey: .value)
                self.type = .term(value)
            case "podcast":
                let podcast = try container.decode(PredictivePodcastSearchResult.self, forKey: .value)
                self.type = .podcast(podcast)
            default:
                let value = try container.decode(String.self, forKey: .value)
                self.type = .unknown(value)
        }
    }
}

public final class PredictiveSearchTask: Sendable {
    private let urlConnection: URLConnection

    public init(urlConnection: URLConnection = URLConnection(handler: URLSession.shared)) {
        self.urlConnection = urlConnection
    }

    public convenience init(session: URLSession) {
        self.init(urlConnection: URLConnection(handler: session))
    }

    public func search(term: String) async throws -> [PredictiveSearchResult] {
        var components = URLComponents(string: ServerConstants.Urls.search + "autocomplete/search")
        components?.queryItems = [URLQueryItem(name: "q", value: term)]
        guard let searchURL = components?.url else {
            throw URL.URLCreationError.invalidURLString
        }
        var request = URLRequest(url: searchURL)
        request.httpMethod = "GET"
        request.addLocalizationHeaders()

        let (responseData, _) = try await urlConnection.send(request: request)
        guard let data = responseData else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let envelope = try decoder.decode(PredictiveSearchEnvelope.self, from: data)
        return envelope.results
    }
}
