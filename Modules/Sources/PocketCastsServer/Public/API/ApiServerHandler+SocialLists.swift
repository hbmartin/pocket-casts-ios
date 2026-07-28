import Foundation

/// Async entry points for shared lists (Slice 7; docs/Social.md, ADR-0011).
/// Ships behind FeatureFlag.socialProfiles.
public extension ApiServerHandler {
    /// Creates a shared list; entries form the initial snapshot
    /// (materialize-to-share sends a whole playlist's worth).
    func createSharedList(title: String, description: String = "",
                          visibility: SocialVisibility = .private,
                          entries: [SharedListEntry] = []) async -> SharedList? {
        guard entries.allSatisfy({ $0.position >= 0 && Int32(exactly: $0.position) != nil }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let operation = SharedListCreateTask(title: title, descriptionText: description,
                                                 visibility: visibility, entries: entries)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    func updateSharedList(id: Int64, title: String, description: String, visibility: SocialVisibility) async -> Bool {
        await ack(.update(listId: id, title: title, description: description, visibility: visibility))
    }

    func deleteSharedList(id: Int64) async -> Bool {
        await ack(.delete(listId: id))
    }

    /// The list header + an entries page. Non-200 (hidden, blocked, missing)
    /// reads as nil — the no-leak contract.
    func fetchSharedList(id: Int64, limit: Int = 100, offset: Int = 0) async -> SharedListPage? {
        guard limit >= 0, offset >= 0,
              let validatedLimit = Int32(exactly: limit),
              let validatedOffset = Int32(exactly: offset) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let operation = SharedListEntriesTask(listId: id, limit: validatedLimit, offset: validatedOffset)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Add/remove/move an entry (owner or collaborator; server LWW).
    func sharedListEntryOp(listId: Int64, op: SharedListOp, entry: SharedListEntry, position: Int = -1) async -> Bool {
        guard let validatedPosition = Int32(exactly: position), op != .move || position >= 0 else {
            return false
        }
        return await ack(.entryOp(listId: listId, op: op, entry: entry, position: validatedPosition))
    }

    func inviteToSharedList(id: Int64, handle: String) async -> Bool {
        await ack(.invite(listId: id, handle: handle))
    }

    func respondToSharedListInvite(id: Int64, accept: Bool) async -> Bool {
        await ack(.inviteRespond(listId: id, accept: accept))
    }

    /// Owner-only: kicks a collaborator, revokes an invite, drops a subscriber.
    func removeSharedListMember(id: Int64, handle: String) async -> Bool {
        await ack(.memberRemove(listId: id, handle: handle))
    }

    func subscribeToSharedList(id: Int64, subscribe: Bool) async -> Bool {
        await ack(.subscribe(listId: id, subscribe: subscribe))
    }

    /// Everything the caller owns / collaborates on / subscribes to + invites.
    func fetchSharedLists() async -> SharedListsOverview? {
        await withCheckedContinuation { continuation in
            let operation = SharedListsTask()
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    private func ack(_ kind: SharedListAckTask.Kind) async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = SharedListAckTask(kind: kind)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }
}
