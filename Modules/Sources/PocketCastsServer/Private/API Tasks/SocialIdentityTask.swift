import Foundation
import PocketCastsUtils
import SwiftProtobuf

// Fork-owned social identity tasks (docs/Social.md, ADR-0005/0006). Each clones
// the UserPodcastRatingTask shape: a protobuf request body POSTed to a
// `social/*` endpoint under ServerConstants.Urls.api(), with the Bearer token
// supplied by ApiBaseTask. Ships dark behind FeatureFlag.socialProfiles.

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class HandleAvailabilityTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((SocialHandleAvailability, String) -> Void)?

    private let handle: String

    init(handle: String) {
        self.handle = handle
    }

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())social/handle/availability"
        do {
            var request = Api_HandleAvailabilityRequest()
            request.handle = handle
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("HandleAvailabilityTask failed for \(handle), http status \(httpStatus)")
                completion?(.unknown, handle)
                return
            }
            let result = try Api_HandleAvailabilityResponse(serializedBytes: responseData)
            let normalized = result.normalizedHandle.isEmpty ? handle : result.normalizedHandle
            completion?(SocialHandleAvailability(result.status), normalized)
        } catch {
            FileLog.shared.addMessage("HandleAvailabilityTask serialize error \(error.localizedDescription) for \(handle)")
            completion?(.unknown, handle)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SocialJoinTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((SocialProfile?) -> Void)?

    private let handle: String
    private let displayName: String
    private let termsVersion: Int32

    init(handle: String, displayName: String, termsVersion: Int32) {
        self.handle = handle
        self.displayName = displayName
        self.termsVersion = termsVersion
    }

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())social/join"
        do {
            var request = Api_JoinRequest()
            request.handle = handle
            request.displayName = displayName
            request.acceptedTermsVersion = termsVersion
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("SocialJoinTask failed for \(handle), http status \(httpStatus)")
                completion?(nil)
                return
            }
            let result = try Api_JoinResponse(serializedBytes: responseData)
            completion?(result.hasProfile ? SocialProfile(result.profile) : nil)
        } catch {
            FileLog.shared.addMessage("SocialJoinTask serialize error \(error.localizedDescription) for \(handle)")
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SocialProfileGetTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((SocialProfile?) -> Void)?

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())social/profile/get"
        do {
            let data = try Api_ProfileGetRequest().serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("SocialProfileGetTask failed, http status \(httpStatus)")
                completion?(nil)
                return
            }
            let result = try Api_ProfileResponse(serializedBytes: responseData)
            completion?(result.hasProfile ? SocialProfile(result.profile) : nil)
        } catch {
            FileLog.shared.addMessage("SocialProfileGetTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SocialProfileUpdateTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((SocialProfile?) -> Void)?

    private let profile: SocialProfile

    init(profile: SocialProfile) {
        self.profile = profile
    }

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())social/profile/update"
        do {
            var request = Api_ProfileUpdateRequest()
            request.displayName = profile.displayName
            request.bio = profile.bio
            request.avatarVisibility = profile.avatarVisibility.apiValue
            request.bioVisibility = profile.bioVisibility.apiValue
            request.followedShowsVisibility = profile.followedShowsVisibility.apiValue
            request.topPodcastsVisibility = profile.topPodcastsVisibility.apiValue
            request.statsVisibility = profile.statsVisibility.apiValue
            request.historyVisibility = profile.historyVisibility.apiValue
            request.presenceVisibility = profile.presenceVisibility.apiValue
            request.requireFollowApproval = profile.requireFollowApproval
            request.socialPushDisabled = profile.socialPushDisabled
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("SocialProfileUpdateTask failed, http status \(httpStatus)")
                completion?(nil)
                return
            }
            let result = try Api_ProfileResponse(serializedBytes: responseData)
            completion?(result.hasProfile ? SocialProfile(result.profile) : nil)
        } catch {
            FileLog.shared.addMessage("SocialProfileUpdateTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class PublicProfileTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((SocialPublicProfile?) -> Void)?

    private let handle: String

    init(handle: String) {
        self.handle = handle
    }

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())social/profile/public"
        do {
            var request = Api_PublicProfileRequest()
            request.handle = handle
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                // A blocked viewer or a missing/tombstoned handle reads as a miss.
                FileLog.shared.addMessage("PublicProfileTask miss for \(handle), http status \(httpStatus)")
                completion?(nil)
                return
            }
            let result = try Api_PublicProfileResponse(serializedBytes: responseData)
            completion?(SocialPublicProfile(result))
        } catch {
            FileLog.shared.addMessage("PublicProfileTask serialize error \(error.localizedDescription) for \(handle)")
            completion?(nil)
        }
    }
}
