import Foundation
import PocketCastsUtils
import SwiftProtobuf

// Send-to-friend + inbox tasks (Slice 4; docs/Social.md).

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SharedItemSendTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((Bool) -> Void)?

    private let request: Api_SharedItemSendRequest

    init(request: Api_SharedItemSendRequest) {
        self.request = request
    }

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())social/share/send"
        do {
            let data = try request.serializedData()
            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                FileLog.shared.addMessage("SharedItemSendTask failed, http status \(httpStatus)")
                completion?(false)
                return
            }
            let ack = try? Api_SocialAck(serializedBytes: responseData)
            completion?(ack?.success ?? false)
        } catch {
            FileLog.shared.addMessage("SharedItemSendTask serialize error \(error.localizedDescription)")
            completion?(false)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SocialInboxListTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((SocialInboxPage?) -> Void)?

    private let limit: Int32
    private let offset: Int32

    init(limit: Int32, offset: Int32) {
        self.limit = limit
        self.offset = offset
    }

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())social/inbox"
        do {
            var request = Api_InboxRequest()
            request.limit = limit
            request.offset = offset
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(nil)
                return
            }
            let result = try Api_InboxResponse(serializedBytes: responseData)
            completion?(SocialInboxPage(items: result.items.map(SharedItem.init),
                                        total: Int(result.total),
                                        unread: Int(result.unread)))
        } catch {
            FileLog.shared.addMessage("SocialInboxListTask serialize error \(error.localizedDescription)")
            completion?(nil)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SocialInboxReadTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((Bool) -> Void)?

    private let ids: [Int64]

    init(ids: [Int64]) {
        self.ids = ids
    }

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())social/inbox/read"
        do {
            var request = Api_InboxMarkReadRequest()
            request.ids = ids
            let data = try request.serializedData()
            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
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
class SocialInboxDeleteTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((Bool) -> Void)?

    private let id: Int64

    init(id: Int64) {
        self.id = id
    }

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())social/inbox/delete"
        do {
            var request = Api_InboxDeleteRequest()
            request.id = id
            let data = try request.serializedData()
            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(false)
                return
            }
            completion?((try? Api_SocialAck(serializedBytes: responseData))?.success ?? false)
        } catch {
            completion?(false)
        }
    }
}
