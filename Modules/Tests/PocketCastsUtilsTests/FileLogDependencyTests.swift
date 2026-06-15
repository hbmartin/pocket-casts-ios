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

// @unchecked Sendable: `messages` is guarded by `lock`; `messageSubject` is a thread-safe Combine subject.
private final class FileLogMock: FileLogging, @unchecked Sendable {
    private let messageSubject = PassthroughSubject<String, Never>()
    var publisher: AnyPublisher<String, Never> { messageSubject.eraseToAnyPublisher() }

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
