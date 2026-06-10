import Foundation
import PocketCastsDataModel

/// Generated protocol mock for `DataMaintenance`. Stub return values by selector:
/// `mock.stub("findPodcast(uuid:includeUnsubscribed:)", with: podcast)`.
public final class DataMaintenanceMock: RepositoryMock, DataMaintenance {
    public func cleanUp() {
        record("cleanUp()")
    }

    public func vacuumDatabase() {
        record("vacuumDatabase()")
    }

    public func count(query: String, values: [Any]?) -> Int {
        record("count(query:values:)")
        return stubs["count(query:values:)"] as? Int ?? 0
    }
}
