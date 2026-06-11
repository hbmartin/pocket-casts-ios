import Foundation

/// Database-wide maintenance operations.
///
/// `DataManager` is the production conformer; inject `any DataMaintenance` (see
/// `Repositories+Dependency.swift`) so consumers can be tested with mocks and a
/// future persistence engine can ship as a second conformer.
public protocol DataMaintenance: AnyObject {
    func cleanUp()
    func vacuumDatabase()
    func count(query: String, values: [Any]?) -> Int
}

extension DataManager: DataMaintenance {}
