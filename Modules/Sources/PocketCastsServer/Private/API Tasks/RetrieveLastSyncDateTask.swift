import Foundation
import PocketCastsUtils
import SwiftProtobuf

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class RetrieveLastSyncDateTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((String?) -> Void)?

    override func apiTokenAcquired(token: String) {
        let url = ServerConstants.Urls.api() + "user/last_sync_at"

        do {
            let lastSyncRequest = Api_EmptyRequest()
            let data = try lastSyncRequest.serializedData()

            let (response, httpStatus) = postToServer(url: url, token: token, data: data)

            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(nil)

                return
            }

            do {
                let lasySyncAt = try Api_UserLastSyncAtResponse(serializedBytes: responseData).lastSyncAt

                completion?(lasySyncAt)
            } catch {
                FileLog.shared.addMessage("Decoding last sync at failed \(error.localizedDescription)")
                completion?(nil)
            }
        } catch {
            FileLog.shared.addMessage("retrieve last sync at failed \(error.localizedDescription)")
            completion?(nil)
        }
    }
}
