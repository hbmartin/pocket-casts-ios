import CryptoKit
import Foundation

// @unchecked Sendable: stateless besides constants.
public final class SharingServerHandler: @unchecked Sendable {
    private static let timeout: TimeInterval = 20

    public static let shared = SharingServerHandler()

    public struct PodcastShareInfo: Codable {
        public let title: String
        public let description: String?
        public let podcasts: [String]

        public init(title: String, description: String, podcasts: [String]) {
            self.title = title
            self.description = description
            self.podcasts = podcasts
        }
    }

    public struct PodcastList: Decodable {
        public let title: String?
        public let listDescription: String?
        public let podcasts: [ListPodcast]?

        public enum CodingKeys: String, CodingKey {
            case title, podcasts
            case listDescription = "description"
        }
    }

    public struct ListPodcast: Decodable {
        public let title: String?
        public let uuid: String?
        public let podcastDescription: String?
        public let author: String?
        public let iTunesId: Int?

        public enum CodingKeys: String, CodingKey {
            case title, uuid, author
            case podcastDescription = "description"
            case iTunesId = "collection_id"
        }
    }

    private let securityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"

        return formatter
    }()

    private struct PodcastShareRequest: Codable {
        let title: String
        let description: String?
        let podcasts: [[String: String]]

        var datetime: String?
        var h: String?
    }

    private struct PodcastShareResponse: Decodable {
        var status: String?
        var result: PodcastShareResult?
    }

    private struct PodcastShareResult: Decodable {
        var shareUrl: String?

        enum CodingKeys: String, CodingKey {
            case shareUrl = "share_url"
        }
    }

    public func sharePodcastList(listInfo: PodcastShareInfo, completion: @escaping @Sendable (_ shareUrl: String?) -> Void) {
        let url = ServerHelper.asUrl(ServerConstants.Urls.sharing() + "share/list")

        let convertedPodcasts = listInfo.podcasts.compactMap { uuid -> [String: String] in
            ["uuid": uuid]
        }
        var shareRequest = PodcastShareRequest(title: listInfo.title, description: listInfo.description, podcasts: convertedPodcasts)

        // add security params
        let dateStr = securityDateFormatter.string(from: Date())
        shareRequest.datetime = dateStr
        shareRequest.h = legacySharingServerSignature(for: dateStr)

        guard let request = ServerHelper.createJsonRequest(url: url, params: shareRequest, timeout: SharingServerHandler.timeout, cachePolicy: .useProtocolCachePolicy) else {
            completion(nil)

            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard (response as? HTTPURLResponse)?.statusCode == ServerConstants.HttpConstants.ok, let data, error == nil else {
                completion(nil)

                return
            }

            do {
                let shareUrl = try JSONDecoder().decode(PodcastShareResponse.self, from: data).result?.shareUrl
                completion(shareUrl)
            } catch {
                completion(nil)
            }
        }.resume()
    }

    public func loadList(listUrl: URL, completion: @escaping @Sendable (_ podcastList: PodcastList?) -> Void) {
        URLSession.shared.dataTask(with: listUrl) { data, response, error in
            guard (response as? HTTPURLResponse)?.statusCode == ServerConstants.HttpConstants.ok, let data, error == nil else {
                completion(nil)

                return
            }

            do {
                let podcastList = try JSONDecoder().decode(PodcastList.self, from: data)
                completion(podcastList)
            } catch {
                completion(nil)
            }
        }.resume()
    }

    private func legacySharingServerSignature(for dateString: String) -> String {
        // The legacy sharing endpoint validates SHA-1 signatures built from the
        // request timestamp and shared credential.
        // This is protocol compatibility only; do not reuse it for password hashing or local integrity checks.
        let signatureInput = "\(dateString)\(ServerCredentials.sharing)"
        let hashDigest = CryptoKit.Insecure.SHA1.hash(data: Data(signatureInput.utf8)) // NOSONAR - Required by the legacy sharing server signature protocol.
        return hashDigest.compactMap { String(format: "%02hhx", $0) }.joined()
    }
}
