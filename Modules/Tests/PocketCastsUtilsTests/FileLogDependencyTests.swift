import Combine
import Foundation
import PocketCastsDependencyInjection
import XCTest
@testable import PocketCastsUtils

final class FileLogDependencyTests: XCTestCase {
    func testDefaultValueIsSharedFileLog() {
        let fileLog = DefaultDependencyContainer.current.fileLog

        XCTAssertTrue((fileLog as AnyObject) === FileLog.shared)
    }

    func testOverridingWithMockCapturesMessages() {
        let original = DefaultDependencyContainer.current.fileLog
        defer { DefaultDependencyContainer.current.fileLog = original }

        let mock = FileLogMock()
        DefaultDependencyContainer.current.fileLog = mock

        DefaultDependencyContainer.current.fileLog.addMessage("captured by mock")

        XCTAssertEqual(mock.recordedMessages, ["captured by mock"])
        XCTAssertTrue((DefaultDependencyContainer.current.fileLog as AnyObject) === mock)
    }
}

// @unchecked Sendable: `messages` is guarded by `lock`; `publisher` is a thread-safe Combine subject.
private final class FileLogMock: FileLogging, @unchecked Sendable {
    let publisher = PassthroughSubject<String, Never>()

    private let lock = NSLock()
    private var messages: [String] = []

    var recordedMessages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }

    func addMessage(_ message: String, date: Date) {
        lock.lock()
        defer { lock.unlock() }
        messages.append(message)
    }

    func console(_ message: String) { }

    func forceFlush() { }

    func loadLogFileAsString(completion: @escaping @Sendable (String) -> Void) {
        completion(recordedMessages.joined(separator: "\n"))
    }

    func logFileAsString() async -> String {
        recordedMessages.joined(separator: "\n")
    }

    func logFileForUpload() -> AnyPublisher<String, Error> {
        Empty().eraseToAnyPublisher()
    }
}
