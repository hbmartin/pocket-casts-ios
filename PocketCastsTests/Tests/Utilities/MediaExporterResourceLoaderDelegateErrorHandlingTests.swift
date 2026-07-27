import XCTest
import AVFoundation
@testable import podcasts

final class MediaExporterResourceLoaderDelegateErrorHandlingTests: XCTestCase {

    var tempFilePath: String!

    override func setUp() {
        super.setUp()
        tempFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString + "_delegate_error_test.media")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tempFilePath)
        tempFilePath = nil
        super.tearDown()
    }

    // MARK: - Failure callback propagation

    func testCallback_receivesFailedStatus_whenURLSessionCompletesWithError() {
        let expectation = XCTestExpectation(description: "Callback receives .failed")
        var capturedStatus: MediaExporterResourceLoaderDelegate.FileExportStatus?

        let delegate = MediaExporterResourceLoaderDelegate(saveFilePath: tempFilePath) { status, _, _, _ in
            capturedStatus = status
            expectation.fulfill()
        }

        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        delegate.urlSession(.shared, task: makeURLSessionTask(), didCompleteWithError: error)

        wait(for: [expectation], timeout: 1.0)

        guard case .failed(let receivedError) = capturedStatus else {
            XCTFail("Expected .failed status, got \(String(describing: capturedStatus))")
            return
        }
        XCTAssertEqual((receivedError as NSError).code, NSURLErrorNotConnectedToInternet)
    }

    func testCallback_receivesFailedStatus_whenFileHandleUnableToOpenFile() {
        let expectation = XCTestExpectation(description: "Callback receives .failed on file error")
        var capturedStatus: MediaExporterResourceLoaderDelegate.FileExportStatus?

        let delegate = MediaExporterResourceLoaderDelegate(saveFilePath: tempFilePath) { status, _, _, _ in
            capturedStatus = status
            expectation.fulfill()
        }

        let fileError = MediaFileHandleError.unableToOpenFile
        delegate.urlSession(.shared, task: makeURLSessionTask(), didCompleteWithError: fileError)

        wait(for: [expectation], timeout: 1.0)

        guard case .failed(let receivedError) = capturedStatus else {
            XCTFail("Expected .failed status, got \(String(describing: capturedStatus))")
            return
        }
        XCTAssertEqual(receivedError as? MediaFileHandleError, .unableToOpenFile)
    }

    func testCallback_receivesFailedStatus_whenReadPastEndOfFile() {
        let expectation = XCTestExpectation(description: "Callback receives .failed on end-of-file read")
        var capturedStatus: MediaExporterResourceLoaderDelegate.FileExportStatus?

        let delegate = MediaExporterResourceLoaderDelegate(saveFilePath: tempFilePath) { status, _, _, _ in
            capturedStatus = status
            expectation.fulfill()
        }

        let eofError = MediaFileHandleError.readAfterEndOfFile
        delegate.urlSession(.shared, task: makeURLSessionTask(), didCompleteWithError: eofError)

        wait(for: [expectation], timeout: 1.0)

        guard case .failed(let receivedError) = capturedStatus else {
            XCTFail("Expected .failed status, got \(String(describing: capturedStatus))")
            return
        }
        XCTAssertEqual(receivedError as? MediaFileHandleError, .readAfterEndOfFile)
    }

    func testCallback_isNotCalledWithFailed_whenSessionCompletesSuccessfully() {
        // A successful completion with no buffered data and no response verification error
        // should call the callback with .completed, not .failed.
        let expectation = XCTestExpectation(description: "Callback receives .completed")
        var capturedStatus: MediaExporterResourceLoaderDelegate.FileExportStatus?

        let delegate = MediaExporterResourceLoaderDelegate(saveFilePath: tempFilePath) { status, _, _, _ in
            if case .completed = status {
                capturedStatus = status
                expectation.fulfill()
            }
        }

        let previousMinimumExpectedFileSize = MediaExporterItemConfiguration.minimumExpectedFileSize
        defer { MediaExporterItemConfiguration.minimumExpectedFileSize = previousMinimumExpectedFileSize }
        MediaExporterItemConfiguration.minimumExpectedFileSize = 0

        delegate.urlSession(.shared, task: makeURLSessionTask(), didCompleteWithError: nil)

        wait(for: [expectation], timeout: 1.0)

        guard case .completed = capturedStatus else {
            XCTFail("Expected .completed status, got \(String(describing: capturedStatus))")
            return
        }
    }

    func testResponseCompletionCanReenterDelegateWithoutDeadlock() {
        let expectation = expectation(description: "Response completion reenters delegate")
        let delegate = MediaExporterResourceLoaderDelegate(saveFilePath: tempFilePath) { _, _, _, _ in }
        let response = URLResponse(
            url: URLSessionTaskFixture.url,
            mimeType: "audio/mpeg",
            expectedContentLength: 0,
            textEncodingName: nil
        )

        delegate.urlSession(
            .shared,
            dataTask: URLSession.shared.dataTask(with: URLSessionTaskFixture.url),
            didReceive: response
        ) { disposition in
            XCTAssertEqual(disposition, .allow)
            delegate.response = response
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testTerminalCallbackUsesFirstSettlement() {
        let callback = expectation(description: "Only the first terminal callback is delivered")
        callback.assertForOverFulfill = true
        let delegate = MediaExporterResourceLoaderDelegate(saveFilePath: tempFilePath) { status, _, _, _ in
            if case .failed = status {
                callback.fulfill()
            }
        }
        let first = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let second = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)

        delegate.urlSession(.shared, task: makeURLSessionTask(), didCompleteWithError: first)
        delegate.urlSession(.shared, task: makeURLSessionTask(), didCompleteWithError: second)

        wait(for: [callback], timeout: 1)
    }

    // MARK: - Progress reporting

    func testCallback_reportsDownloadingProgress_afterAppendingReceivedData() {
        let expectation = XCTestExpectation(description: "Callback receives .downloading with the appended byte count")
        var capturedDownloaded: Int64?

        let delegate = MediaExporterResourceLoaderDelegate(saveFilePath: tempFilePath) { status, _, downloaded, _ in
            if case .downloading = status {
                capturedDownloaded = downloaded
                expectation.fulfill()
            }
        }

        let payload = Data(repeating: 0xAB, count: 1234)
        delegate.urlSession(.shared, dataTask: URLSession.shared.dataTask(with: URLSessionTaskFixture.url), didReceive: payload)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(capturedDownloaded, 1234)
    }

    // MARK: - Delivery chunk bookkeeping

    func testNextChunkRange_capsEachChunkAtReadDataLimit() {
        let range = MediaExporterResourceLoaderDelegate.nextChunkRange(
            currentOffset: 0,
            requestedOffset: 0,
            requestedLength: 100,
            bytesCached: 100,
            readDataLimit: 8
        )

        XCTAssertEqual(range, 0 ..< 8)
    }

    func testNextChunkRange_sequentialDeliveryCoversRequestOnceWithoutOverlap() {
        // Mirrors the delivery loop: the owning thread advances the offset before the
        // next compute pass, so successive chunks must be contiguous, disjoint,
        // bounded by the read limit, and stop exactly at the requested end.
        let requestedOffset = 10
        let requestedLength = 50
        var offset = requestedOffset
        var coveredBytes = 0

        while let range = MediaExporterResourceLoaderDelegate.nextChunkRange(
            currentOffset: offset,
            requestedOffset: requestedOffset,
            requestedLength: requestedLength,
            bytesCached: 100,
            readDataLimit: 12
        ) {
            XCTAssertEqual(range.lowerBound, offset, "Chunks must be contiguous with no gaps or duplicated ranges")
            XCTAssertLessThanOrEqual(range.count, 12, "Each pass must deliver at most one bounded chunk")
            coveredBytes += range.count
            offset = range.upperBound
        }

        XCTAssertEqual(offset, requestedOffset + requestedLength, "Delivery must stop exactly at the end of the requested range")
        XCTAssertEqual(coveredBytes, requestedLength)
    }

    func testNextChunkRange_stalledOffsetRecomputesIdenticalRange_soDeliveryNeedsSingleOwner() {
        // Two compute passes from the same delivered offset describe the same bytes.
        // This pins why a request is marked in flight while it is being served: if
        // two threads could compute for one request, both would deliver this
        // identical range and corrupt the stream.
        let first = MediaExporterResourceLoaderDelegate.nextChunkRange(currentOffset: 0, requestedOffset: 0, requestedLength: 64, bytesCached: 64, readDataLimit: 16)
        let second = MediaExporterResourceLoaderDelegate.nextChunkRange(currentOffset: 0, requestedOffset: 0, requestedLength: 64, bytesCached: 64, readDataLimit: 16)

        XCTAssertEqual(first, 0 ..< 16)
        XCTAssertEqual(second, first)

        let advanced = MediaExporterResourceLoaderDelegate.nextChunkRange(currentOffset: 16, requestedOffset: 0, requestedLength: 64, bytesCached: 64, readDataLimit: 16)
        XCTAssertEqual(advanced, 16 ..< 32, "Advancing the delivered offset must yield the next disjoint range")
    }

    func testNextChunkRange_waitsWhenNoCachedBytesBeyondOffset() {
        XCTAssertNil(MediaExporterResourceLoaderDelegate.nextChunkRange(currentOffset: 30, requestedOffset: 0, requestedLength: 100, bytesCached: 30, readDataLimit: 10))
    }

    func testNextChunkRange_returnsNilOnceRequestIsFulfilled() {
        XCTAssertNil(MediaExporterResourceLoaderDelegate.nextChunkRange(currentOffset: 100, requestedOffset: 0, requestedLength: 100, bytesCached: 200, readDataLimit: 10))
    }

    func testNextChunkRange_clampsFinalChunkToRequestedEnd() {
        let range = MediaExporterResourceLoaderDelegate.nextChunkRange(currentOffset: 95, requestedOffset: 0, requestedLength: 100, bytesCached: 200, readDataLimit: 50)

        XCTAssertEqual(range, 95 ..< 100)
    }
}

// MARK: - Helpers

private func makeURLSessionTask() -> URLSessionTask {
    URLSession.shared.dataTask(with: URLSessionTaskFixture.url)
}

private enum URLSessionTaskFixture {
    static var url: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "example.com"
        return components.url!
    }
}
