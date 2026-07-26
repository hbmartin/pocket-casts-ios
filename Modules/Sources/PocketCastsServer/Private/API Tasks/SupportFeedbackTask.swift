import Foundation
import PocketCastsUtils
import SwiftProtobuf

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SupportFeedbackTask: ApiBaseTask, @unchecked Sendable {
    private let completion: (Bool) -> Void

    private let report: FeedbackReport

    init(report: FeedbackReport,
         attestService _: AppAttestService = .shared,
         urlConnection: URLConnection = URLConnection(handler: URLSession.shared),
         completion: @escaping (Bool) -> Void) {
        self.report = report
        self.completion = completion
        super.init(urlConnection: urlConnection)
    }

    override func main() {
        autoreleasepool {
            if SyncManager.isUserLoggedIn(), let token = acquiredToken() {
                startRequest(token: token, feedbackType: .authenticated)
            } else {
                startRequest(feedbackType: .anonymous)
            }
        }
    }

    func startRequest(token: String? = nil, feedbackType: FeedbackType) {
        do {
            let urlString = "\(ServerConstants.Urls.api())\(feedbackType.endpoint)"

            var request = Api_SupportFeedbackRequest()
            request.message = report.message
            request.subject = report.subject
            request.inbox = "feedback"
            request.logs = report.logs
            request.bitdriftSessionID = report.bitdriftSessionID
            request.deviceInfo = report.deviceInfo
            request.appVersion = report.appVersion

            let data = try request.serializedData()

            let (response, httpStatus) = performPostToServer(url: urlString, token: token, data: data)

            if response == nil {
                FileLog.shared.addMessage("Failed to send the feedback message because response is empty")
                completion(false)
                return
            }

            if httpStatus == ServerConstants.HttpConstants.ok {
                FileLog.shared.addMessage("Feedback message as \(feedbackType.rawValue) sent successfully")
            } else {
                FileLog.shared.addMessage("Failed to send the feedback message as \(feedbackType.rawValue), http status \(httpStatus)")
            }
            completion(httpStatus == ServerConstants.HttpConstants.ok)
        } catch {
            FileLog.shared.addMessage("Failed to serialize Api_SupportFeedbackRequest \(error.localizedDescription)")
            completion(false)
        }
    }

    enum FeedbackType: String {
        case authenticated
        case anonymous

        var endpoint: String {
            switch self {
            case .authenticated: "support/feedback"
            case .anonymous: "anonymous/feedback"
            }
        }
    }
}
