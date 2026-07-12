import PocketCastsDataModel
import XCTest

@testable import podcasts

final class DownloadErrorMessageTests: XCTestCase {
    private func message(forCode code: Int) -> String {
        DownloadManager.userFacingDownloadErrorMessage(for: NSError(domain: NSURLErrorDomain, code: code))
    }

    func testOfflineErrorsSuggestCheckingTheConnection() {
        XCTAssertEqual(message(forCode: NSURLErrorNotConnectedToInternet), L10n.downloadErrorNoInternet)
        XCTAssertEqual(message(forCode: NSURLErrorNetworkConnectionLost), L10n.downloadErrorNoInternet)
        XCTAssertEqual(message(forCode: NSURLErrorDataNotAllowed), L10n.downloadErrorNoInternet)
    }

    func testOtherNetworkErrorsSuggestTryingAgain() {
        XCTAssertEqual(message(forCode: NSURLErrorTimedOut), L10n.downloadErrorTryAgain)
        XCTAssertEqual(message(forCode: NSURLErrorCannotConnectToHost), L10n.downloadErrorTryAgain)
        XCTAssertEqual(message(forCode: NSURLErrorBadServerResponse), L10n.downloadErrorTryAgain)
    }

    func testUnrecognizedErrorsNeverLeakRawDescriptions() {
        let opaque = NSError(domain: "au.com.pocketcasts.test", code: -9999, userInfo: [NSLocalizedDescriptionKey: "unknown error"])
        XCTAssertEqual(DownloadManager.userFacingDownloadErrorMessage(for: opaque), L10n.downloadErrorTryAgain)
    }

    @MainActor
    func testRowErrorMessageFallsBackToCuratedCopyWithoutDetails() {
        var episode = Episode()
        episode.downloadErrorDetails = nil
        XCTAssertEqual(episode.readableErrorMessage(), L10n.podcastFailedDownload)

        episode.downloadErrorDetails = L10n.downloadErrorNoInternet
        XCTAssertEqual(episode.readableErrorMessage(), L10n.downloadErrorNoInternet)
    }
}
