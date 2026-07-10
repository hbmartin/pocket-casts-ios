import Foundation
import GRDB
@testable import PocketCastsDataModel

/// A database and filesystem root owned by one test invocation. Unlike the
/// legacy shared DatabasePool helper, this sandbox has no process-global state,
/// so Swift Testing may run its callers in parallel.
struct ParallelTestDatabaseSandbox {
    let directoryURL: URL
    let databasePool: DatabasePool
    let databaseQueue: GRDBQueue

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PocketCastsDataModelTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var configuration = Configuration()
        configuration.busyMode = .timeout(10)
        databasePool = try DatabasePool(
            path: directoryURL.appendingPathComponent("podcasts.sqlite3").path,
            configuration: configuration
        )
        databaseQueue = GRDBQueue(dbPool: databasePool)
    }

    func cleanUp() throws {
        try databasePool.close()
        try FileManager.default.removeItem(at: directoryURL)
    }
}
