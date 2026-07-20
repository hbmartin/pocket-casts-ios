import Foundation

/// Async entry points for find-people (Slice 9; docs/Social.md).
public extension ApiServerHandler {
    /// Prefix search over discoverable joined profiles.
    func searchPeople(query: String) async -> [SocialProfileSummary]? {
        await profiles(.search(query: query))
    }

    /// Friends-of-followed suggestions with mutual counts (count only).
    /// The operator-designated curators directory (Slice 15, ADR-0014).
    func fetchCurators() async -> [SocialProfileSummary]? {
        await withCheckedContinuation { continuation in
            let operation = SocialPeopleTask(kind: .curators)
            operation.profilesCompletion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    func fetchPeopleSuggestions() async -> [SocialProfileSummary]? {
        await profiles(.suggestions)
    }

    /// The server salt for contact-identifier hashing.
    func fetchContactsSalt() async -> String? {
        await withCheckedContinuation { continuation in
            let operation = SocialPeopleTask(kind: .salt)
            operation.saltCompletion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Transient contact matching: typed salted hashes in, matched
    /// discoverable profiles out; nothing stored server-side.
    func matchContacts(hashes: [SocialContactHash]) async -> [SocialProfileSummary]? {
        await profiles(.match(hashes: hashes))
    }

    private func profiles(_ kind: SocialPeopleTask.Kind) async -> [SocialProfileSummary]? {
        await withCheckedContinuation { continuation in
            let operation = SocialPeopleTask(kind: kind)
            operation.profilesCompletion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }
}
