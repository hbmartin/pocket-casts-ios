import Foundation

public struct DefaultDependencyContainer: DependencyContainer {
    // nonisolated(unsafe): the DI container is configured during app startup and the
    // by-design global mutability lives in each DependencyKey's currentValue.
    nonisolated(unsafe) public static var current = DefaultDependencyContainer()

    private init() { }
}
