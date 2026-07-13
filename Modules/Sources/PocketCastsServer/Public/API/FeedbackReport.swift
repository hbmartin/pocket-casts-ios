import Foundation

/// A user-submitted feedback report (the support flow and shake-to-report in
/// TestFlight builds): the typed message plus the diagnostics the app attaches.
/// Maps onto `Api_SupportFeedbackRequest`'s fork extension fields.
public struct FeedbackReport: Sendable {
    public let message: String
    public let subject: String
    public let logs: String
    public let bitdriftSessionID: String
    public let deviceInfo: String
    public let appVersion: String

    public init(message: String,
                subject: String,
                logs: String = "",
                bitdriftSessionID: String = "",
                deviceInfo: String = "",
                appVersion: String = "") {
        self.message = message
        self.subject = subject
        self.logs = logs
        self.bitdriftSessionID = bitdriftSessionID
        self.deviceInfo = deviceInfo
        self.appVersion = appVersion
    }
}
