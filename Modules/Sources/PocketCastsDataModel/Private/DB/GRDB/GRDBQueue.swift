import GRDB
import PocketCastsUtils
import Foundation

final class GRDBQueue: PCDBQueue, Sendable {
    public let dbPool: DatabasePool
    let logger: ErrorLogger?

    init(dbPool: DatabasePool, logger: ErrorLogger? = nil) {
        self.dbPool = dbPool
        self.logger = logger
    }

    func inDatabase(_ block: (any PCDatabase) -> Void) {
        #if DEBUG
        MainThreadDBReporter.reportIfNeeded()
        #endif
        do {
            try dbPool.write { db in
                let dbWrapper = GRDBDatabase(database: db)
                block(dbWrapper)
            }
        } catch {
            logger?.log(error: error, context: [:])
        }
    }

    func inTransaction(_ block: (any PCDatabase, UnsafeMutablePointer<ObjCBool>) -> Void) {
        #if DEBUG
        MainThreadDBReporter.reportIfNeeded()
        #endif
        do {
            try dbPool.writeInTransaction { db in
                let rollback = UnsafeMutablePointer<ObjCBool>.allocate(capacity: 1)
                rollback.pointee = false
                let dbWrapper = GRDBDatabase(database: db)
                block(dbWrapper, rollback)
                defer { rollback.deallocate() }
                return rollback.pointee.boolValue ? .rollback : .commit
            }
        } catch {
            logger?.log(error: error, context: [:])
        }
    }

    func read(_ block: (any PCDatabase) -> Void) {
        #if DEBUG
        MainThreadDBReporter.reportIfNeeded()
        #endif
        do {
            try dbPool.read { db in
                let dbWrapper = GRDBDatabase(database: db)
                block(dbWrapper)
            }
        } catch {
            logger?.log(error: error, context: [:])
        }
    }

    func write(_ block: (any PCDatabase) -> Void) {
        #if DEBUG
        MainThreadDBReporter.reportIfNeeded()
        #endif
        performWrite(block)
    }

    private func performWrite(_ block: (any PCDatabase) -> Void) {
        do {
            try dbPool.write { db in
                let dbWrapper = GRDBDatabase(database: db)
                block(dbWrapper)
            }
        } catch {
            logger?.log(error: error, context: [:])
        }
    }

    func read<T>(_ block: @Sendable @escaping (any PCDatabase) throws -> T) async throws -> T {
        let box = try await dbPool.read { db in
            UncheckedSendableBox(value: try block(GRDBDatabase(database: db)))
        }
        return box.value
    }

    func write<T>(_ block: @Sendable @escaping (any PCDatabase) throws -> T) async throws -> T {
        let box = try await dbPool.write { db in
            UncheckedSendableBox(value: try block(GRDBDatabase(database: db)))
        }
        return box.value
    }

    func close() {
        do {
            try dbPool.close()
        } catch {
            logger?.log(error: error, context: [:])
        }
    }
}

/// GRDB's async read/write require Sendable results; the legacy models are
/// mutable reference types, so ownership is handed to the awaiting task instead.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
}
