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

enum PersonRequest: Sendable {
    case follow(personId: Int64, unfollow: Bool)
    case search(query: String)
    case followedPersons
}

enum PersonResponse: Sendable {
    case mutation(Bool)
    case persons([ServerPerson]?)
}

/// The operation owns immutable request data and invokes its completion once.
// @unchecked Sendable: completion is configured before enqueue and touched only during serial operation work.
final class PersonTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((PersonResponse) -> Void)?

    private let request: PersonRequest

    init(request: PersonRequest) {
        self.request = request
    }

    override func apiTokenAcquired(token: String) {
        switch request {
        case let .follow(personId, unfollow):
            performFollow(personId: personId, unfollow: unfollow, token: token)
        case let .search(query):
            performSearch(query: query, token: token)
        case .followedPersons:
            performFollowedPersons(token: token)
        }
    }

    override func apiTokenAcquisitionFailed() {
        switch request {
        case .follow:
            completion?(.mutation(false))
        case .search, .followedPersons:
            completion?(.persons(nil))
        }
    }

    private func performFollow(personId: Int64, unfollow: Bool, token: String) {
        do {
            var request = Api_PersonFollowRequest()
            request.personID = personId
            let data = try request.serializedData()
            let path = unfollow ? "person/unfollow" : "person/follow"

            let (_, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())\(path)", token: token, data: data)
            let success = httpStatus == ServerConstants.HttpConstants.ok
            if !success {
                FileLog.shared.addMessage("PersonTask \(path) failed for \(personId), http status \(httpStatus)")
            }
            completion?(.mutation(success))
        } catch {
            FileLog.shared.addMessage("PersonTask serialize error \(error.localizedDescription)")
            completion?(.mutation(false))
        }
    }

    private func performSearch(query: String, token: String) {
        do {
            var request = Api_PersonSearchRequest()
            request.query = query
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())person/search", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(.persons(nil))
                return
            }
            let result = try Api_PersonListResponse(serializedBytes: responseData)
            completion?(.persons(result.persons.map { ServerPerson(id: $0.id, displayName: $0.displayName) }))
        } catch {
            FileLog.shared.addMessage("PersonTask search error \(error.localizedDescription)")
            completion?(.persons(nil))
        }
    }

    private func performFollowedPersons(token: String) {
        let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())person/follows", token: token, data: Data())
        guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok,
              let result = try? Api_PersonListResponse(serializedBytes: responseData) else {
            completion?(.persons(nil))
            return
        }
        completion?(.persons(result.persons.map { ServerPerson(id: $0.id, displayName: $0.displayName) }))
    }
}
