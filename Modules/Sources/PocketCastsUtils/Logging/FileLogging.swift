import Combine
import Foundation

/// Consumer-facing surface of `FileLog`, registered in the dependency container as
/// `\.fileLog` so consumers can be tested with a mock logger instead of writing to
/// the real on-disk log.
public protocol FileLogging: Sendable {
    var publisher: PassthroughSubject<String, Never> { get }

    func addMessage(_ message: String, date: Date)
    func console(_ message: String)
    func forceFlush()
    func loadLogFileAsString(completion: @escaping @Sendable (String) -> Void)
    func logFileAsString() async -> String
    func logFileForUpload() -> AnyPublisher<String, Error>
}

public extension FileLogging {
    /// Protocols cannot declare default arguments; mirrors `FileLog.addMessage(_:date:)`.
    func addMessage(_ message: String) {
        addMessage(message, date: Date())
    }
}

extension FileLog: FileLogging { }
