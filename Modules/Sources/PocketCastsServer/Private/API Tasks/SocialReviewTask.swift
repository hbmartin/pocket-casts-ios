import Foundation
import PocketCastsUtils
import SwiftProtobuf

// Written reviews + episode reactions tasks (Slice 3; docs/Social.md).

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class ReviewSubmitTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((PodcastReview?) -> Void)?

    private let podcastUuid: String
    private let text: String

    init(podcastUuid: String, text: String) {
        self.podcastUuid = podcastUuid
        self.text = text
    }

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())social/review/submit"
        do {
            var request = Api_PodcastReviewSubmitRequest()
            request.podcastUuid = podcastUuid
            request.text = text
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("ReviewSubmitTask failed for \(podcastUuid), http status \(httpStatus)")
                completion?(nil)
                return
            }
            let result = try Api_PodcastReview(serializedBytes: responseData)
            completion?(PodcastReview(result))
        } catch {
            FileLog.shared.addMessage("ReviewSubmitTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class ReviewDeleteTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((Bool) -> Void)?

    private let podcastUuid: String

    init(podcastUuid: String) {
        self.podcastUuid = podcastUuid
    }

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())social/review/delete"
        do {
            var request = Api_PodcastReviewDeleteRequest()
            request.podcastUuid = podcastUuid
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(false)
                return
            }
            let ack = try? Api_SocialAck(serializedBytes: responseData)
            completion?(ack?.success ?? false)
        } catch {
            FileLog.shared.addMessage("ReviewDeleteTask serialize error \(error.localizedDescription)")
            completion?(false)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class ReviewListTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((PodcastReviewPage?) -> Void)?

    private let podcastUuid: String
    private let limit: Int32
    private let offset: Int32

    init(podcastUuid: String, limit: Int32, offset: Int32) {
        self.podcastUuid = podcastUuid
        self.limit = limit
        self.offset = offset
    }

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())podcast/reviews"
        do {
            var request = Api_PodcastReviewsRequest()
            request.podcastUuid = podcastUuid
            request.limit = limit
            request.offset = offset
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("ReviewListTask failed for \(podcastUuid), http status \(httpStatus)")
                completion?(nil)
                return
            }
            let result = try Api_PodcastReviewsResponse(serializedBytes: responseData)
            completion?(PodcastReviewPage(reviews: result.reviews.map(PodcastReview.init),
                                          total: Int(result.total),
                                          yourReview: result.hasYourReview ? PodcastReview(result.yourReview) : nil))
        } catch {
            FileLog.shared.addMessage("ReviewListTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class ReactionSetTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((Bool) -> Void)?

    private let episodeUuid: String
    private let kind: ReactionKind?

    /// kind nil = clear the caller's reaction.
    init(episodeUuid: String, kind: ReactionKind?) {
        self.episodeUuid = episodeUuid
        self.kind = kind
    }

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())social/reaction/set"
        do {
            var request = Api_EpisodeReactionSetRequest()
            request.episodeUuid = episodeUuid
            request.kind = Api_ReactionKind(rawValue: kind?.rawValue ?? 0) ?? .unspecified
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(false)
                return
            }
            let ack = try? Api_SocialAck(serializedBytes: responseData)
            completion?(ack?.success ?? false)
        } catch {
            FileLog.shared.addMessage("ReactionSetTask serialize error \(error.localizedDescription)")
            completion?(false)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class ReactionListTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((EpisodeReactions?) -> Void)?

    private let episodeUuid: String

    init(episodeUuid: String) {
        self.episodeUuid = episodeUuid
    }

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())episode/reactions"
        do {
            var request = Api_EpisodeReactionsRequest()
            request.episodeUuid = episodeUuid
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(nil)
                return
            }
            let result = try Api_EpisodeReactionsResponse(serializedBytes: responseData)
            completion?(EpisodeReactions(result))
        } catch {
            FileLog.shared.addMessage("ReactionListTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}
