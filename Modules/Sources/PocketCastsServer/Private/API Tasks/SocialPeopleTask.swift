import Foundation
import PocketCastsUtils
import SwiftProtobuf

// Find-people tasks (Slice 9; docs/Social.md).

/// One search/suggestion/match result row.
public struct SocialProfileSummary: Equatable, Sendable, Identifiable {
    public let handle: String
    public let displayName: String
    public let yourFollowState: FollowState
    public let mutualCount: Int

    public var id: String { handle }

    public init(handle: String, displayName: String, yourFollowState: FollowState = .none, mutualCount: Int = 0) {
        self.handle = handle
        self.displayName = displayName
        self.yourFollowState = yourFollowState
        self.mutualCount = mutualCount
    }

    init(_ api: Api_ProfileSummary) {
        self.init(handle: api.handle, displayName: api.displayName,
                  yourFollowState: FollowState(api.yourFollowState), mutualCount: Int(api.mutualCount))
    }
}

/// One salted contact-identifier hash (kind 1 = email, 2 = phone).
public struct SocialContactHash: Sendable {
    public let kind: Int
    public let hash: String

    public init(kind: Int, hash: String) {
        self.kind = kind
        self.hash = hash
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SocialPeopleTask: ApiBaseTask, @unchecked Sendable {
    enum Kind {
        case search(query: String)
        case suggestions
        case salt
        case match(hashes: [SocialContactHash])
    }

    var profilesCompletion: (([SocialProfileSummary]?) -> Void)?
    var saltCompletion: ((String?) -> Void)?

    private let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    override func apiTokenAcquired(token: String) {
        do {
            let data: Data
            let path: String
            switch kind {
            case .search(let query):
                var request = Api_SocialSearchRequest()
                request.query = query
                data = try request.serializedData()
                path = "social/search"
            case .suggestions:
                data = try Api_SocialSuggestionsRequest().serializedData()
                path = "social/suggestions"
            case .salt:
                data = try Api_SocialSuggestionsRequest().serializedData()
                path = "social/contacts/salt"
            case .match(let hashes):
                var request = Api_ContactsMatchRequest()
                request.hashes = hashes.map { contactHash in
                    var wire = Api_ContactHash()
                    wire.kind = Api_ContactHashKind(rawValue: contactHash.kind) ?? .unspecified
                    wire.hash = contactHash.hash
                    return wire
                }
                data = try request.serializedData()
                path = "social/contacts/match"
            }

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())\(path)", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("SocialPeopleTask \(path) failed, http status \(httpStatus)")
                profilesCompletion?(nil)
                saltCompletion?(nil)
                return
            }
            switch kind {
            case .search:
                let result = try Api_SocialSearchResponse(serializedBytes: responseData)
                profilesCompletion?(result.profiles.map(SocialProfileSummary.init))
            case .suggestions:
                let result = try Api_SocialSuggestionsResponse(serializedBytes: responseData)
                profilesCompletion?(result.profiles.map(SocialProfileSummary.init))
            case .salt:
                let result = try Api_ContactsSaltResponse(serializedBytes: responseData)
                saltCompletion?(result.salt)
            case .match:
                let result = try Api_ContactsMatchResponse(serializedBytes: responseData)
                profilesCompletion?(result.profiles.map(SocialProfileSummary.init))
            }
        } catch {
            FileLog.shared.addMessage("SocialPeopleTask serialize error \(error.localizedDescription)")
            profilesCompletion?(nil)
            saltCompletion?(nil)
        }
    }
}
