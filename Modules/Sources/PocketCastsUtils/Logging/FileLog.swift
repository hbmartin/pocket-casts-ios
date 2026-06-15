import Combine
import Foundation
import os

actor LogBuffer {
    private let bufferThreshold: UInt

    private var logBuffer: [LogEntry] = [] {
        didSet {
            if logBuffer.count >= bufferThreshold {
                writeLogBufferToDisk()
            }
        }
    }

    private let logPersistence: PersistentTextWriting
    private let logRotator: FileRotating
    private let logger: Logger?

    init(logPersistence: PersistentTextWriting,
         logRotator: FileRotating,
         bufferThreshold: UInt = 100,
         loggingTo logger: Logger? = nil) {
        self.logPersistence = logPersistence
        self.logRotator = logRotator
        self.bufferThreshold = bufferThreshold
        self.logger = logger
    }

    private let maxFileSize = 1.megabytes

    func append(_ message: String, date: Date) {
        // if it's important enough to log to file, write it to the debug console as well
        logger?.log("\(message, privacy: .public)")

        logBuffer.append(LogEntry(message, timestamp: date))
    }

    func console(_ message: String) {
        logger?.log("\(message, privacy: .public)")
    }

    private func writeLogBufferToDisk() {
        let newLogChunk = logBuffer.sorted(by: { $0.timestamp.compare($1.timestamp) == .orderedAscending }).reduce(into: "") { resultChunk, logEntry in
            resultChunk.append("\(logEntry.formattedForLog)\n")
        }

        logBuffer.removeAll(keepingCapacity: true)
        appendStringToLog(newLogChunk)
    }

    private func appendStringToLog(_ logUpdate: String) {
        logRotator.rotateFile(ifSizeExceeds: maxFileSize)
        logPersistence.write(logUpdate)
    }

    public func forceFlush() {
        guard !logBuffer.isEmpty else { return }

        logger?.debug("\(Self.self) forcibly flushing to disk.")
        writeLogBufferToDisk()
    }

    public func loadLogFileAsString() -> String {
        forceFlush()

        let mainFileContents: String
        do {
            mainFileContents = try String(contentsOfFile: LogFilePaths.mainLogFilePath)
        } catch {
            mainFileContents = "Main log is empty"
        }

        let secondaryFileContents: String
        do {
            secondaryFileContents = try String(contentsOfFile: LogFilePaths.backupLogFilePath)
        } catch {
            secondaryFileContents = ""
        }

        return "\(secondaryFileContents)\n\(mainFileContents)"
    }
}

// @unchecked Sendable: `logBuffer` is an actor and `messageSubject` is a thread-safe Combine
// subject; there is no other mutable state.
public final class FileLog: @unchecked Sendable {
    public enum LogError: Error {
        case logCanceled
        case logGenerationFailed
    }

    public static let shared: FileLog = {
        let logger = Logger()

        let logFileWriter = LogFileWriter(
            writingToFileAtPath: LogFilePaths.mainLogFilePath,
            loggingTo: logger
        )

        let fileRotator = FileRotator(
            targetFilePath: LogFilePaths.mainLogFilePath,
            backupFilePath: LogFilePaths.backupLogFilePath,
            loggingTo: logger
        )

        return FileLog(
            logPersistence: logFileWriter,
            logRotator: fileRotator,
            loggingTo: logger
        )
    }()

    private let logBuffer: LogBuffer
    private let messageSubject = PassthroughSubject<String, Never>()

    /// Read-only stream of logged messages so consumers can capture log output without being
    /// able to inject lines via `send(_:)`; only `FileLog` publishes here (see `addMessage`).
    public var publisher: AnyPublisher<String, Never> { messageSubject.eraseToAnyPublisher() }

    init(
        logPersistence: PersistentTextWriting,
        logRotator: FileRotating,
        bufferThreshold: UInt = 100,
        loggingTo logger: Logger? = nil
    ) {
        self.logBuffer = LogBuffer(logPersistence: logPersistence, logRotator: logRotator, bufferThreshold: bufferThreshold, loggingTo: logger)
    }

    public func addMessage(_ message: String, date: Date = Date()) {
        Task {
            await logBuffer.append(message, date: date)
            messageSubject.send(message)
        }
    }

    public func console(_ message: String) {
        Task {
            await logBuffer.console(message)
        }
    }

    public func forceFlush() {
        Task {
            await logBuffer.forceFlush()
        }
    }

    public func loadLogFileAsString(completion: @escaping @Sendable (String) -> Void) {
        Task {
            let log = await logBuffer.loadLogFileAsString()
            completion(log)
        }
    }

    public func logFileAsString() async -> String {
        return await logBuffer.loadLogFileAsString()
    }

    // Creates a merged file from `mainLogFilePath` and `backupLogFilePath` to be used for enquing the file upload.
    public func logFileForUpload() -> AnyPublisher<String, Error> {
        let file = LogFilePaths.debugUploadLog

        return Future { [unowned self] promise in
            // Future's promise is not @Sendable-typed, but Combine documents it as safe to
            // call from any thread; hand it to the completion via an unchecked wrapper.
            let promise = UncheckedSendable(promise)
            self.loadLogFileAsString { result in
                do {
                    try result.write(toFile: file, atomically: true, encoding: String.Encoding.utf8)
                } catch {
                    promise.value(.failure(LogError.logGenerationFailed))
                    return
                }

                promise.value(.success(file))
            }
        }
        .eraseToAnyPublisher()
    }
}
