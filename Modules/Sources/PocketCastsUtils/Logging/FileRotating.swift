import Foundation
import OSLog

protocol FileRotating: Sendable {
    func rotateFile(ifSizeExceeds: Int)
}

public struct FileRotator: FileRotating, Sendable {

    private let targetFilePath: String
    private let backupFilePath: String
    private let logger: Logger?

    private var fileManager: FileManager { .default }

    public init(targetFilePath: String, backupFilePath: String, loggingTo logger: Logger? = nil) {
        self.targetFilePath = targetFilePath
        self.backupFilePath = backupFilePath
        self.logger = logger
    }

    public func rotateFile(ifSizeExceeds maxFileSizeInBytes: Int) {
        guard fileManager.fileExists(atPath: targetFilePath) else {
            logger?.debug("Attempted to rotate file at <\(targetFilePath)> but no such file exists. Aborting.")
            return
        }

        let fileSizeInBytes: UInt64
        do {
            let fileDict = try fileManager.attributesOfItem(atPath: targetFilePath)
            fileSizeInBytes = (fileDict[.size] as? UInt64) ?? 0
        } catch {
            logger?.debug("Failed to retrieve attributes of file at path <\(targetFilePath)>. Error: \(error)")
            return
        }

        guard fileSizeInBytes > maxFileSizeInBytes else {
            // File is small enough that it doesn't need to be rotated.
            return
        }

        do { try fileManager.removeItem(atPath: LogFilePaths.backupLogFilePath) }
        catch { /* The file doesn't exist, which is perfectly fine */ }

        do {
            try fileManager.moveItem(atPath: targetFilePath, toPath: backupFilePath)
        } catch {
            logger?.error("Failed to rotate file at path <\(targetFilePath)> by moving it to <\(backupFilePath)>. Error: \(error)")
        }
    }
}
