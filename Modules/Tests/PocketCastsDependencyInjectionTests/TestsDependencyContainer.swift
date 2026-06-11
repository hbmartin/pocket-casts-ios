import Foundation
import PocketCastsDependencyInjection

struct TestDependencyContainer: DependencyContainer {
    // nonisolated(unsafe): test-only container; tests run single-threaded.
    nonisolated(unsafe) static var current = TestDependencyContainer()

    private init() { }
}
