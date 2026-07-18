import Foundation
import PocketCastsUtils
import SwiftProtobuf

// Shared-list tasks (Slice 7; docs/Social.md, ADR-0011).

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SharedListCreateTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((SharedList?) -> Void)?

    private let title: String
    private let descriptionText: String
    private let visibility: SocialVisibility
    private let entries: [SharedListEntry]

    init(title: String, descriptionText: String, visibility: SocialVisibility, entries: [SharedListEntry]) {
        self.title = title
        self.descriptionText = descriptionText
        self.visibility = visibility
        self.entries = entries
    }

    override func apiTokenAcquired(token: String) {
        do {
            var request = Api_SharedListCreateRequest()
            request.title = title
            request.description_p = descriptionText
            request.visibility = visibility.apiValue
            request.entries = entries.map { entry in
                var wire = Api_SharedListEntry()
                wire.episodeUuid = entry.episodeUuid
                wire.podcastUuid = entry.podcastUuid
                wire.episodeTitle = entry.episodeTitle
                wire.podcastTitle = entry.podcastTitle
                wire.position = Int32(entry.position)
                return wire
            }
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())social/list/create", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("SharedListCreateTask failed, http status \(httpStatus)")
                completion?(nil)
                return
            }
            completion?(SharedList(try Api_SharedList(serializedBytes: responseData)))
        } catch {
            FileLog.shared.addMessage("SharedListCreateTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SharedListAckTask: ApiBaseTask, @unchecked Sendable {
    enum Kind {
        case update(listId: Int64, title: String, description: String, visibility: SocialVisibility)
        case delete(listId: Int64)
        case entryOp(listId: Int64, op: SharedListOp, entry: SharedListEntry, position: Int)
        case invite(listId: Int64, handle: String)
        case inviteRespond(listId: Int64, accept: Bool)
        case memberRemove(listId: Int64, handle: String)
        case subscribe(listId: Int64, subscribe: Bool)
    }

    var completion: ((Bool) -> Void)?

    private let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    override func apiTokenAcquired(token: String) {
        do {
            let data: Data
            let path: String
            switch kind {
            case .update(let listId, let title, let description, let visibility):
                var request = Api_SharedListUpdateRequest()
                request.listID = listId
                request.title = title
                request.description_p = description
                request.visibility = visibility.apiValue
                data = try request.serializedData()
                path = "social/list/update"
            case .delete(let listId):
                var request = Api_SharedListDeleteRequest()
                request.listID = listId
                data = try request.serializedData()
                path = "social/list/delete"
            case .entryOp(let listId, let op, let entry, let position):
                var request = Api_SharedListEntryOpRequest()
                request.listID = listId
                request.op = Api_SharedListOp(rawValue: op.rawValue) ?? .unspecified
                request.episodeUuid = entry.episodeUuid
                request.podcastUuid = entry.podcastUuid
                request.episodeTitle = entry.episodeTitle
                request.podcastTitle = entry.podcastTitle
                request.position = Int32(position)
                data = try request.serializedData()
                path = "social/list/entry"
            case .invite(let listId, let handle):
                var request = Api_SharedListInviteRequest()
                request.listID = listId
                request.handle = handle
                data = try request.serializedData()
                path = "social/list/invite"
            case .inviteRespond(let listId, let accept):
                var request = Api_SharedListInviteRespondRequest()
                request.listID = listId
                request.accept = accept
                data = try request.serializedData()
                path = "social/list/invite/respond"
            case .memberRemove(let listId, let handle):
                var request = Api_SharedListInviteRequest()
                request.listID = listId
                request.handle = handle
                data = try request.serializedData()
                path = "social/list/member/remove"
            case .subscribe(let listId, let subscribe):
                var request = Api_SharedListSubscribeRequest()
                request.listID = listId
                request.subscribe = subscribe
                data = try request.serializedData()
                path = "social/list/subscribe"
            }

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())\(path)", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("SharedListAckTask \(path) failed, http status \(httpStatus)")
                completion?(false)
                return
            }
            completion?((try? Api_SocialAck(serializedBytes: responseData))?.success ?? false)
        } catch {
            completion?(false)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SharedListEntriesTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((SharedListPage?) -> Void)?

    private let listId: Int64
    private let limit: Int32
    private let offset: Int32

    init(listId: Int64, limit: Int32, offset: Int32) {
        self.listId = listId
        self.limit = limit
        self.offset = offset
    }

    override func apiTokenAcquired(token: String) {
        do {
            var request = Api_SharedListEntriesRequest()
            request.listID = listId
            request.limit = limit
            request.offset = offset
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())social/list/entries", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(nil)
                return
            }
            let result = try Api_SharedListEntriesResponse(serializedBytes: responseData)
            completion?(SharedListPage(list: SharedList(result.list),
                                       entries: result.entries.map(SharedListEntry.init),
                                       total: Int(result.total)))
        } catch {
            FileLog.shared.addMessage("SharedListEntriesTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SharedListsTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((SharedListsOverview?) -> Void)?

    override func apiTokenAcquired(token: String) {
        do {
            let data = try Api_SharedListsRequest().serializedData()
            let (response, httpStatus) = postToServer(url: "\(ServerConstants.Urls.api())social/lists", token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(nil)
                return
            }
            let result = try Api_SharedListsResponse(serializedBytes: responseData)
            completion?(SharedListsOverview(lists: result.lists.map(SharedList.init),
                                            invites: result.invites.map(SharedList.init)))
        } catch {
            FileLog.shared.addMessage("SharedListsTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}
