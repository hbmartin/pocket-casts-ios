import Foundation
@testable import podcasts
import XCTest

@MainActor
final class DeveloperBundleImporterTests: XCTestCase {
    func testAccessDeniedDoesNotReadImportOrStop() {
        var events = [String]()

        XCTAssertThrowsError(
            try DeveloperBundleImporter.importBundle(
                from: testURL,
                startAccessing: { _ in
                    events.append("start")
                    return false
                },
                stopAccessing: { _ in events.append("stop") },
                readFileWrapper: { _ in
                    events.append("read")
                    return self.fileWrapper
                },
                performImport: { _ in events.append("import") }
            )
        ) { error in
            XCTAssertEqual(error as? DeveloperBundleImportError, .accessDenied)
        }
        XCTAssertEqual(events, ["start"])
    }

    func testReadFailureStopsAccessAndDoesNotImport() {
        var events = [String]()

        XCTAssertThrowsError(
            try DeveloperBundleImporter.importBundle(
                from: testURL,
                startAccessing: { _ in
                    events.append("start")
                    return true
                },
                stopAccessing: { _ in events.append("stop") },
                readFileWrapper: { _ in
                    events.append("read")
                    throw TestError.failure
                },
                performImport: { _ in events.append("import") }
            )
        ) { error in
            XCTAssertEqual(error as? DeveloperBundleImportError, .fileReadFailed)
        }
        XCTAssertEqual(events, ["start", "read", "stop"])
    }

    func testImportFailureOccursAfterAccessStops() {
        var events = [String]()

        XCTAssertThrowsError(
            try DeveloperBundleImporter.importBundle(
                from: testURL,
                startAccessing: { _ in
                    events.append("start")
                    return true
                },
                stopAccessing: { _ in events.append("stop") },
                readFileWrapper: { _ in
                    events.append("read")
                    return self.fileWrapper
                },
                performImport: { _ in
                    events.append("import")
                    throw TestError.failure
                }
            )
        ) { error in
            XCTAssertEqual(error as? DeveloperBundleImportError, .importFailed)
        }
        XCTAssertEqual(events, ["start", "read", "stop", "import"])
    }

    func testSuccessfulImportStopsAccessBeforeImport() throws {
        var events = [String]()

        try DeveloperBundleImporter.importBundle(
            from: testURL,
            startAccessing: { _ in
                events.append("start")
                return true
            },
            stopAccessing: { _ in events.append("stop") },
            readFileWrapper: { _ in
                events.append("read")
                return self.fileWrapper
            },
            performImport: { _ in events.append("import") }
        )

        XCTAssertEqual(events, ["start", "read", "stop", "import"])
    }

    func testLogMessagesDoNotContainSelectedFileMetadata() {
        DeveloperBundleImportError.allCases.forEach { error in
            XCTAssertFalse(error.logMessage.contains(testURL.path))
            XCTAssertFalse(error.logMessage.contains(testURL.lastPathComponent))
        }
    }

    private var testURL: URL {
        URL(fileURLWithPath: "/private/secret/account-token.pcasts")
    }

    private var fileWrapper: FileWrapper {
        FileWrapper(regularFileWithContents: Data("bundle".utf8))
    }

    private enum TestError: Error {
        case failure
    }
}

private extension DeveloperBundleImportError {
    static let allCases: [Self] = [.accessDenied, .fileReadFailed, .importFailed]
}
