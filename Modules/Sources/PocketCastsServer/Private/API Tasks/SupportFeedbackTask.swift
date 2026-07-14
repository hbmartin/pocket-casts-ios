import Foundation
import PocketCastsUtils
import SwiftProtobuf

// @unchecked Sendable: Operation subclass restating the inherited unchecked conformance; state is configured before enqueue and touched only during the operation's serial execution.
class SupportFeedbackTask: ApiBaseTask, @unchecked Sendable {
    private let completion: (Bool) -> Void

    private let report: FeedbackReport

    private let attestService: AppAttestService

    /// Populated just before the POST and applied by the `createRequest`
    /// override below; safe because the operation executes serially (see the
    /// unchecked-conformance note on the class declaration).
    private var attestationHeaders: [String: String] = [:]

    init(report: FeedbackReport,
         attestService: AppAttestService = .shared,
         urlConnection: URLConnection = URLConnection(handler: URLSession.shared),
         completion: @escaping (Bool) -> Void) {
        self.report = report
        self.attestService = attestService
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

            // Best-effort App Attest (docs/AppAttest.md): the assertion signs these
            // exact body bytes, so compute the headers after serializing and send the
            // data unmodified. An empty result means "send unattested" — acceptable
            // here because the feedback endpoint runs in log-only enforcement. (That
            // also makes the base task's 401 token-refresh retry safe: it re-sends the
            // same assertion, which strict counter checking would treat as a replay.)
            attestationHeaders = Self.awaitAssertionHeaders(from: attestService, forBody: data)

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

    override func createRequest(url: URL, method: String, token: String?) -> URLRequest {
        var request = super.createRequest(url: url, method: method, token: token)
        for (header, value) in attestationHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }
        return request
    }

    /// Synchronous bridge for this Operation's worker thread: waits briefly for
    /// the (possibly enrolling) attestation service, and sends unattested on
    /// timeout so attestation can never fail or materially delay the feedback
    /// send. The semaphore wait establishes the happens-before edge for the
    /// boxed value.
    private static func awaitAssertionHeaders(from service: AppAttestService, forBody body: Data, timeout: TimeInterval = 10) -> [String: String] {
        let box = UncheckedSendableBox<[String: String]>([:])
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            box.value = await service.assertionHeaders(forBody: body)
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            FileLog.shared.addMessage("SupportFeedbackTask: timed out waiting for attestation headers; sending unattested")
            return [:]
        }
        return box.value
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
