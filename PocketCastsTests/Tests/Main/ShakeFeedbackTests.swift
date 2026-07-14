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

    func testReportRedactsSecretBearingURLsInLogs() async {
        let logs = """
        LocalFeedFetcher: fetched https://user:secret@example.com/feed.xml
        DownloadManager: Failed download uuid-1 https://cdn.example.com/ep.mp3?token=abc123 statusCode:Optional(403)
        """
        let report = await makeBuilder(logs: logs).report(message: "hi")

        XCTAssertFalse(report.logs.contains("secret"), "Userinfo must not reach the feedback API")
        XCTAssertFalse(report.logs.contains("abc123"), "Signed query values must not reach the feedback API")
        XCTAssertTrue(report.logs.contains("https://example.com/feed.xml"), "Host and path stay diagnostic")
        XCTAssertTrue(report.logs.contains("token=REDACTED"), "Query keys stay diagnostic")
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
