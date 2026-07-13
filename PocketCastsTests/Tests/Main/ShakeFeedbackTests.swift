import PocketCastsServer
import XCTest

@testable import podcasts

/// Shake-to-report assembly and the sheet view model's send flow (Item 67).
@MainActor
final class ShakeFeedbackTests: XCTestCase {
    private func makeBuilder(logs: String = "log tail", sessionID: String? = "session-1") -> ShakeFeedbackReportBuilder {
        ShakeFeedbackReportBuilder(logProvider: { logs }, sessionIDProvider: { sessionID })
    }

    func testReportCarriesMessageAndDiagnostics() async {
        let report = await makeBuilder().report(message: "  The player froze.  ")

        XCTAssertEqual(report.message, "The player froze.", "The message is trimmed")
        XCTAssertEqual(report.subject, "Shake report")
        XCTAssertEqual(report.logs, "log tail")
        XCTAssertEqual(report.bitdriftSessionID, "session-1")
        XCTAssertTrue(report.deviceInfo.contains("iOS") || report.deviceInfo.contains("iPadOS"),
                      "Device info names the OS: \(report.deviceInfo)")
        XCTAssertTrue(report.appVersion.contains("("), "App version includes the build number: \(report.appVersion)")
    }

    func testReportToleratesMissingSessionID() async {
        let report = await makeBuilder(sessionID: nil).report(message: "hi")
        XCTAssertEqual(report.bitdriftSessionID, "")
    }

    func testSendFlowTransitionsAndRetryKeepsMessage() async {
        let model = ShakeFeedbackViewModel(builder: makeBuilder(), send: { _ in false })
        XCTAssertFalse(model.canSend, "Empty message can't send")

        model.message = "Something broke"
        XCTAssertTrue(model.canSend)

        model.sendTapped()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(model.phase, .failed)

        model.retryTapped()
        XCTAssertEqual(model.phase, .composing)
        XCTAssertEqual(model.message, "Something broke", "A failed send must not lose the message")
    }

    func testSuccessfulSendReportsSent() async {
        let sent = SendRecorder()
        let model = ShakeFeedbackViewModel(builder: makeBuilder(), send: { report in
            await sent.record(report)
            return true
        })
        model.message = "All good"
        model.sendTapped()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(model.phase, .sent)
        let recorded = await sent.reports
        XCTAssertEqual(recorded.map(\.message), ["All good"])
    }
}

private actor SendRecorder {
    var reports: [FeedbackReport] = []
    func record(_ report: FeedbackReport) {
        reports.append(report)
    }
}
