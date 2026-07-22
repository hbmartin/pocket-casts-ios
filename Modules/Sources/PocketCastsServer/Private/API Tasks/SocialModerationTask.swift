import Foundation
import PocketCastsUtils
import SwiftProtobuf

// Fork-owned social moderation + safety tasks (docs/SocialModeration.md,
// ADR-0007). block = mutual invisibility; mute = one-way hide; report = a flag
// into the triage queue; erase = GDPR erasure (clears PII, tombstones the
// handle). Each returns success via the shared Api_SocialAck. Ships dark behind
// FeatureFlag.socialProfiles.

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SocialBlockTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((Bool) -> Void)?

    private let targetUserId: String
    private let block: Bool

    init(targetUserId: String, block: Bool) {
        self.targetUserId = targetUserId
        self.block = block
    }

    override func apiTokenAcquired(token: String) {
        let path = block ? "social/block" : "social/unblock"
        let urlString = "\(ServerConstants.Urls.api())\(path)"
        do {
            var request = Api_BlockRequest()
            request.targetUserID = targetUserId
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            completion?(Self.succeeded(response: response, httpStatus: httpStatus, label: path))
        } catch {
            FileLog.shared.addMessage("SocialBlockTask serialize error \(error.localizedDescription)")
            completion?(false)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SocialMuteTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((Bool) -> Void)?

    private let targetUserId: String
    private let mute: Bool

    init(targetUserId: String, mute: Bool) {
        self.targetUserId = targetUserId
        self.mute = mute
    }

    override func apiTokenAcquired(token: String) {
        let path = mute ? "social/mute" : "social/unmute"
        let urlString = "\(ServerConstants.Urls.api())\(path)"
        do {
            var request = Api_MuteRequest()
            request.targetUserID = targetUserId
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            completion?(Self.succeeded(response: response, httpStatus: httpStatus, label: path))
        } catch {
            FileLog.shared.addMessage("SocialMuteTask serialize error \(error.localizedDescription)")
            completion?(false)
        }
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SocialReportTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((Bool) -> Void)?

    private let targetUserId: String
    private let reason: SocialReportReason
    private let context: String
    private let targetType: String
    private let contentRef: String

    init(targetUserId: String,
         reason: SocialReportReason,
         context: String,
         targetType: String,
         contentRef: String) {
        self.targetUserId = targetUserId
        self.reason = reason
        self.context = context
        self.targetType = targetType
        self.contentRef = contentRef
    }

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())social/report"
        do {
            let request = Self.makeRequest(targetUserId: targetUserId,
                                           reason: reason,
                                           context: context,
                                           targetType: targetType,
                                           contentRef: contentRef)
            let data = try request.serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            completion?(Self.succeeded(response: response, httpStatus: httpStatus, label: "social/report"))
        } catch {
            FileLog.shared.addMessage("SocialReportTask serialize error \(error.localizedDescription)")
            completion?(false)
        }
    }

    static func makeRequest(targetUserId: String,
                            reason: SocialReportReason,
                            context: String,
                            targetType: String,
                            contentRef: String) -> Api_ReportRequest {
        var request = Api_ReportRequest()
        request.targetUserID = targetUserId
        request.reason = reason.apiValue
        request.context = context
        request.targetType = targetType
        request.contentRef = contentRef
        return request
    }
}

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SocialEraseTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((Bool) -> Void)?

    override func apiTokenAcquired(token: String) {
        let urlString = "\(ServerConstants.Urls.api())social/erase"
        do {
            let data = try Api_EraseRequest().serializedData()

            let (response, httpStatus) = postToServer(url: urlString, token: token, data: data)
            completion?(Self.succeeded(response: response, httpStatus: httpStatus, label: "social/erase"))
        } catch {
            FileLog.shared.addMessage("SocialEraseTask serialize error \(error.localizedDescription)")
            completion?(false)
        }
    }
}

private extension ApiBaseTask {
    /// Shared success decode for the moderation acks: HTTP 200 with an
    /// `Api_SocialAck.success == true` (an empty/garbled body counts as failure).
    static func succeeded(response: Data?, httpStatus: Int, label: String) -> Bool {
        guard let response, httpStatus == ServerConstants.HttpConstants.ok else {
            FileLog.shared.addMessage("\(label) failed, http status \(httpStatus)")
            return false
        }
        let ack = try? Api_SocialAck(serializedBytes: response)
        return ack?.success ?? false
    }
}
