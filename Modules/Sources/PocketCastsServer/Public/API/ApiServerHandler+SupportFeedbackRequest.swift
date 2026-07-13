import Foundation

public extension ApiServerHandler {
    func sendFeedback(message: String) async -> Bool {
        await sendFeedback(report: FeedbackReport(message: message, subject: "Feedback"))
    }

    /// Submits a full feedback report (shake-to-report): message plus the
    /// diagnostics fields the fork's backend stores.
    func sendFeedback(report: FeedbackReport) async -> Bool {
        return await withCheckedContinuation { continuation in
            let operation = SupportFeedbackTask(report: report) { success in
                continuation.resume(returning: success)
            }
            apiQueue.addOperation(operation)
        }
    }
}
