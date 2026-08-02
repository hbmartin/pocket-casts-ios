import Foundation

/// Async entry points for the person index + follows (Highlights S12,
/// ADR-0017). Ships behind FeatureFlag.personFollows — DARK until backend
/// milestone B2 is live in production. Follows are private account state:
/// they require a signed-in account but no joined social profile.
public extension ApiServerHandler {
    /// Resolves a display name to server person identities (folded-prefix
    /// search server-side). nil on transport failure, [] for no matches.
    func searchPersons(query: String) async -> [ServerPerson]? {
        await withCheckedContinuation { continuation in
            let operation = PersonSearchTask(query: query)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Follows a person id; the server pushes when they appear on a newly
    /// ingested episode. Idempotent.
    func followPerson(id: Int64) async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = PersonFollowTask(personId: id, unfollow: false)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Unfollows a person id. Idempotent.
    func unfollowPerson(id: Int64) async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = PersonFollowTask(personId: id, unfollow: true)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// The caller's followed persons.
    func followedPersons() async -> [ServerPerson]? {
        await withCheckedContinuation { continuation in
            let operation = PersonFollowsListTask()
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }
}
