import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import SwiftProtobuf

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class ChangeEmailTask: ApiBaseTask, @unchecked Sendable {
    var completion: ((Bool) -> Void)?

    private let newEmail: String
    private let password: String

    init(newEmail: String, password: String) {
        self.newEmail = newEmail
        self.password = password
        super.init()
    }

    override func apiTokenAcquired(token: String) {
        let url = ServerConstants.Urls.api() + "user/change_email"

        do {
            var changeRequest = Api_UserChangeEmailRequest()
            changeRequest.email = newEmail
            changeRequest.password = password
            changeRequest.scope = ServerConstants.Values.apiScope

            let data = try changeRequest.serializedData()

            let (response, httpStatus) = postToServer(url: url, token: token, data: data)

            guard let responseData = response, httpStatus == ServerConstants.HttpConstants.ok else {
                completion?(false)

                return
            }

            do {
                let result = try Api_UserChangeResponse(serializedBytes: responseData)
                completion?(result.success.value)
                FileLog.shared.addMessage("API change email response \(result)")
            } catch {
                FileLog.shared.addMessage("Failed to change email \(error.localizedDescription)")
                completion?(false)
            }
        } catch {
            FileLog.shared.addMessage("Failed to change email \(error.localizedDescription)")
            completion?(false)
        }
    }
}
