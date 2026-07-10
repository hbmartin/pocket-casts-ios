import Foundation
import GRDB
@testable import PocketCastsDataModel

/// Per-test integration state. Every invocation owns a unique directory and
/// GRDB pool, avoiding DataManager.sharedManager and making Swift Testing's
/// default parallel execution safe.
struct IntegrationTestSandbox {
    let directoryURL: URL
    let databasePool: DatabasePool
    let dataManager: DataManager

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PocketCastsIntegrationTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var configuration = Configuration()
        configuration.busyMode = .timeout(10)
        databasePool = try DatabasePool(
            path: directoryURL.appendingPathComponent("podcasts.sqlite3").path,
            configuration: configuration
        )
        dataManager = DataManager(dbQueue: GRDBQueue(dbPool: databasePool))
    }

    func cleanUp() throws {
        try databasePool.close()
        try FileManager.default.removeItem(at: directoryURL)
    }
}
