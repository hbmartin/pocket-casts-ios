import Network
import Testing
@testable import PocketCastsUtils

@Suite("NetworkUtils metered policy")
struct NetworkUtilsTests {
    @Test("expensive Wi-Fi is not treated as unmetered")
    func expensiveSatisfiedPath() {
        #expect(!NetworkUtils.isUnexpensive(status: .satisfied, isExpensive: true))
    }

    @Test("only satisfied non-expensive paths are unmetered")
    func unmeteredRequiresConnectivity() {
        #expect(NetworkUtils.isUnexpensive(status: .satisfied, isExpensive: false))
        #expect(!NetworkUtils.isUnexpensive(status: .unsatisfied, isExpensive: false))
        #expect(!NetworkUtils.isUnexpensive(status: .requiresConnection, isExpensive: false))
    }
}
