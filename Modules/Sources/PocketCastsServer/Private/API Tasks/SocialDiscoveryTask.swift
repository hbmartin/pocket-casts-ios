import Foundation
import PocketCastsUtils
import SwiftProtobuf

// Social discovery tasks (Slice 10; docs/Social.md).

/// One "Trending with friends" row entry.
public struct TrendingPodcast: Equatable, Sendable, Identifiable {
    public let podcastUuid: String
    public let title: String
    public let author: String
    public let listenerCount: Int

    public var id: String { podcastUuid }

    public init(podcastUuid: String, title: String, author: String, listenerCount: Int) {
        self.podcastUuid = podcastUuid
        self.title = title
        self.author = author
        self.listenerCount = listenerCount
    }
}

/// The podcast-page social proof: named-when-visible + the full count.
public struct PodcastProof: Equatable, Sendable {
    public let visibleHandles: [String]
    public let totalCount: Int

    public init(visibleHandles: [String], totalCount: Int) {
        self.visibleHandles = visibleHandles
        self.totalCount = totalCount
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SocialDiscoveryTask: ApiBaseTask, @unchecked Sendable {
    enum Kind {
        case trending
        case proof(podcastUuid: String)
    }

    var trendingCompletion: (([TrendingPodcast]?) -> Void)?
    var proofCompletion: ((PodcastProof?) -> Void)?

    private let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    override func apiTokenAcquired(token: String) {
        do {
            let data: Data
            let path: String
            switch kind {
            case .trending:
                data = try Api_SocialTrendingRequest().serializedData()
                path = "social/trending"
            case .proof(let podcastUuid):
                var request = Api_PodcastProofRequest()
                request.podcastUuid = podcastUuid
                data = try request.serializedData()
                path = "social/podcast/proof"
            }

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())\(path)", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                trendingCompletion?(nil)
                proofCompletion?(nil)
                return
            }
            switch kind {
            case .trending:
                let result = try Api_SocialTrendingResponse(serializedBytes: responseData)
                trendingCompletion?(result.podcasts.map {
                    TrendingPodcast(podcastUuid: $0.podcastUuid, title: $0.title,
                                    author: $0.author, listenerCount: Int($0.listenerCount))
                })
            case .proof:
                let result = try Api_PodcastProofResponse(serializedBytes: responseData)
                proofCompletion?(PodcastProof(visibleHandles: result.visibleHandles, totalCount: Int(result.totalCount)))
            }
        } catch {
            FileLog.shared.addMessage("SocialDiscoveryTask serialize error \(error.localizedDescription)")
            trendingCompletion?(nil)
            proofCompletion?(nil)
        }
    }
}
