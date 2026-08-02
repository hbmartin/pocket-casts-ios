import Foundation
import PocketCastsUtils
import SwiftProtobuf

// Person index + follows (Highlights B2, ADR-0017). Follows are private
// account state: Bearer-authenticated like every first-party call, but no
// joined social profile is required.

/// A server-side person identity.
public struct ServerPerson: Sendable, Equatable {
    public let id: Int64
    public let displayName: String
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class PersonFollowTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((Bool) -> Void)?

    private let personId: Int64
    private let unfollow: Bool

    init(personId: Int64, unfollow: Bool) {
        self.personId = personId
        self.unfollow = unfollow
    }

    override func apiTokenAcquired(token: String) {
        do {
            var request = Api_PersonFollowRequest()
            request.personID = personId
            let data = try request.serializedData()
            let path = unfollow ? "person/unfollow" : "person/follow"

            let (_, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())\(path)", token: token, data: data)
            let success = httpStatus == ServerConstants.HttpConstants.ok
            if !success {
                FileLog.shared.addMessage("PersonFollowTask \(path) failed for \(personId), http status \(httpStatus)")
            }
            completion?(success)
        } catch {
            FileLog.shared.addMessage("PersonFollowTask serialize error \(error.localizedDescription)")
            completion?(false)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class PersonSearchTask: ApiBaseTask, @unchecked Sendable {
    var completion: (([ServerPerson]?) -> Void)?

    private let query: String

    init(query: String) {
        self.query = query
    }

    override func apiTokenAcquired(token: String) {
        do {
            var request = Api_PersonSearchRequest()
            request.query = query
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())person/search", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(nil)
                return
            }
            let result = try Api_PersonListResponse(serializedBytes: responseData)
            completion?(result.persons.map { ServerPerson(id: $0.id, displayName: $0.displayName) })
        } catch {
            FileLog.shared.addMessage("PersonSearchTask error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class PersonFollowsListTask: ApiBaseTask, @unchecked Sendable {
    var completion: (([ServerPerson]?) -> Void)?

    override func apiTokenAcquired(token: String) {
        let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())person/follows", token: token, data: Data())
        guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok,
              let result = try? Api_PersonListResponse(serializedBytes: responseData) else {
            completion?(nil)
            return
        }
        completion?(result.persons.map { ServerPerson(id: $0.id, displayName: $0.displayName) })
    }
}
