import CryptoKit
import Foundation
import PocketCastsUtils

public final class SharingServerHandler: Sendable {
    private static let timeout: TimeInterval = 20

    public static let shared = SharingServerHandler()

    /// Attaches `Authorization: Bearer` on the flag-gated bearer path.
    private let tokenHelper: TokenHelper

    /// Transport for the legacy signature path; injectable so tests can capture the request.
    private let urlConnection: URLConnection

    init(tokenHelper: TokenHelper = .shared, urlConnection: URLConnection = URLConnection(handler: URLSession.shared)) {
        self.tokenHelper = tokenHelper
        self.urlConnection = urlConnection
    }

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

    public struct PodcastList: Decodable, Sendable {
        public let title: String?
        public let listDescription: String?
        public let podcasts: [ListPodcast]?

        public enum CodingKeys: String, CodingKey {
            case title, podcasts
            case listDescription = "description"
        }
    }

    public struct ListPodcast: Decodable, Sendable {
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

        // M3: delete `datetime` and `h` — they exist only for the legacy static-secret
        // signature path (plans/API Auth Hardening Plan.md §3.4). They are never set on
        // the bearer path, and JSONEncoder omits them when nil.
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

        if FeatureFlag.sharingListBearerAuth.enabled {
            // Bearer path (plans/API Auth Hardening Plan.md §3.4): the request is
            // authorized by the user's access token, attached by TokenHelper as
            // `Authorization: Bearer`. The legacy `datetime`/`h` params are not sent.
            guard SyncManager.isUserLoggedIn() else {
                // Creating a list requires an account on the bearer path. Callers
                // already surface a share-failed alert on a nil share URL
                // (SharePublishViewController.sharingDidFail); routing signed-out
                // users through a sign-in prompt is a UI-layer follow-up that needs
                // the product sign-off recorded in the plan (§3.2).
                FileLog.shared.addMessage("SharingServerHandler: share list requires sign-in when sharingListBearerAuth is enabled")
                completion(nil)

                return
            }

            guard let request = ServerHelper.createJsonRequest(url: url, params: shareRequest, timeout: SharingServerHandler.timeout, cachePolicy: .useProtocolCachePolicy) else {
                completion(nil)

                return
            }

            tokenHelper.callSecureUrl(request: request) { response, data, error in
                completion(Self.parseShareResponse(statusCode: response?.statusCode, data: data, error: error))
            }

            return
        }

        // M3: delete this whole legacy branch (timestamp + static-secret signature) once
        // the sharing server's bearer dual-accept window closes and the fleet threshold is
        // met — plans/API Auth Hardening Plan.md §3.4. Removal checklist at that milestone:
        // `datetime`/`h` fields above, `securityDateFormatter`, `legacySharingServerSignature`
        // below, `ServerCredentials`, and the sharing_server_secret credentials pipeline.
        let dateStr = securityDateFormatter.string(from: Date())
        shareRequest.datetime = dateStr
        shareRequest.h = Self.legacySharingServerSignature(for: dateStr)

        guard let request = ServerHelper.createJsonRequest(url: url, params: shareRequest, timeout: SharingServerHandler.timeout, cachePolicy: .useProtocolCachePolicy) else {
            completion(nil)

            return
        }

        urlConnection.send(request: request) { data, response, error in
            completion(Self.parseShareResponse(statusCode: (response as? HTTPURLResponse)?.statusCode, data: data, error: error))
        }
    }

    private static func parseShareResponse(statusCode: Int?, data: Data?, error: Error?) -> String? {
        guard statusCode == ServerConstants.HttpConstants.ok, let data, error == nil else {
            return nil
        }

        return try? JSONDecoder().decode(PodcastShareResponse.self, from: data).result?.shareUrl
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

    // M3: delete legacySharingServerSignature and its fixtures (SharingServerHandlerTests +
    // the CopiedSharingServerHandler block in semgrep/tests/swift-security-crypto.swift) once
    // the sharing server disables the legacy `h` signature — plans/API Auth Hardening Plan.md
    // §3.4. That removes the repo's last Insecure.SHA1 suppression.
    // nosemgrep: pocketcasts.sharing-no-static-secret-signing - Legacy sharing-server protocol site kept until the M3 dual-accept sunset; new signing code must use the bearer path.
    static func legacySharingServerSignature(for dateString: String, credential: String = ServerCredentials.sharing) -> String {
        // The legacy sharing endpoint validates SHA-1 signatures built from the
        // request timestamp and shared credential.
        // This is protocol compatibility only; do not reuse it for password hashing or local integrity checks.
        let signatureInput = "\(dateString)\(credential)"
        let hashDigest = CryptoKit.Insecure.SHA1.hash( // nosemgrep: pocketcasts.no-insecure-cryptokit-hashes, pocketcasts.sharing-no-static-secret-signing - Required by the legacy sharing server signature protocol until the M3 sunset (plans/API Auth Hardening Plan.md §3.4). NOSONAR
            data: Data(signatureInput.utf8)
        )
        return hashDigest.map { String(format: "%02hhx", $0) }.joined()
    }
}
