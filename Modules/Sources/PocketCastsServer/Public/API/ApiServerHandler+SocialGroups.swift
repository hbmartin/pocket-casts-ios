import Foundation

/// Async entry points for Groups (Slice 13; docs/Social.md, ADR-0012).
/// Ships behind FeatureFlag.socialProfiles.
public extension ApiServerHandler {
    func createGroup(title: String, description: String = "", visibility: SocialVisibility,
                     podcastUuid: String = "", podcastTitle: String = "") async -> SocialGroup? {
        await withCheckedContinuation { continuation in
            let operation = GroupCreateTask(title: title, description: description, visibility: visibility,
                                            podcastUuid: podcastUuid, podcastTitle: podcastTitle)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    func updateGroup(id: Int64, title: String, description: String, visibility: SocialVisibility) async -> Bool {
        await groupAck(.update(groupId: id, title: title, description: description, visibility: visibility))
    }

    func deleteGroup(id: Int64) async -> Bool { await groupAck(.delete(groupId: id)) }
    func joinGroup(id: Int64) async -> Bool { await groupAck(.join(groupId: id)) }
    func leaveGroup(id: Int64) async -> Bool { await groupAck(.leave(groupId: id)) }
    func inviteToGroup(id: Int64, handle: String) async -> Bool { await groupAck(.invite(groupId: id, handle: handle)) }
    func respondToGroupInvite(id: Int64, accept: Bool) async -> Bool { await groupAck(.inviteRespond(groupId: id, accept: accept)) }
    func kickFromGroup(id: Int64, handle: String, ban: Bool) async -> Bool { await groupAck(.kick(groupId: id, handle: handle, ban: ban)) }
    func setGroupAlert(id: Int64, enabled: Bool) async -> Bool { await groupAck(.alert(groupId: id, enabled: enabled)) }
    func editGroupPost(id: Int64, text: String) async -> Bool { await groupAck(.postEdit(postId: id, text: text)) }
    func deleteGroupPost(id: Int64) async -> Bool { await groupAck(.postDelete(postId: id)) }

    internal func groupAck(_ kind: GroupAckTask.Kind) async -> Bool {
        await withCheckedContinuation { continuation in
            let operation = GroupAckTask(kind: kind)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// The caller's groups + pending invites.
    func fetchGroups() async -> SocialGroupsOverview? {
        await withCheckedContinuation { continuation in
            let operation = GroupsFetchTask(kind: .mine)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Public groups by size (Explore's Groups row).
    func discoverGroups(limit: Int = 20) async -> [SocialGroup] {
        await withCheckedContinuation { continuation in
            let operation = GroupsFetchTask(kind: .discover(limit: limit))
            operation.completion = { continuation.resume(returning: $0?.groups ?? []) }
            apiQueue.addOperation(operation)
        }
    }

    /// The show's fandom hubs (non-exclusive anchors, member-count ordered).
    func groupsForPodcast(uuid: String) async -> [SocialGroup] {
        await withCheckedContinuation { continuation in
            let operation = GroupsFetchTask(kind: .forPodcast(uuid: uuid))
            operation.completion = { continuation.resume(returning: $0?.groups ?? []) }
            apiQueue.addOperation(operation)
        }
    }

    func submitGroupPost(groupId: Int64, parentId: Int64 = 0, text: String,
                         episodeUuid: String = "", podcastUuid: String = "",
                         episodeTitle: String = "", podcastTitle: String = "",
                         listId: Int64 = 0, listTitle: String = "") async -> GroupPost? {
        await withCheckedContinuation { continuation in
            let operation = GroupPostSubmitTask(groupId: groupId, parentId: parentId, text: text,
                                                episodeUuid: episodeUuid, podcastUuid: podcastUuid,
                                                episodeTitle: episodeTitle, podcastTitle: podcastTitle,
                                                listId: listId, listTitle: listTitle)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    /// Top-level page (parentId 0, group detail included) or one post's replies.
    func fetchGroupPosts(groupId: Int64, parentId: Int64 = 0, limit: Int = 50, offset: Int = 0) async -> GroupPostsPage? {
        await withCheckedContinuation { continuation in
            let operation = GroupPostsTask(groupId: groupId, parentId: parentId,
                                           limit: Int32(limit), offset: Int32(offset))
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }

    func fetchGroupMembers(groupId: Int64) async -> [GroupMemberInfo]? {
        await withCheckedContinuation { continuation in
            let operation = GroupMembersTask(groupId: groupId)
            operation.completion = { continuation.resume(returning: $0) }
            apiQueue.addOperation(operation)
        }
    }
}
