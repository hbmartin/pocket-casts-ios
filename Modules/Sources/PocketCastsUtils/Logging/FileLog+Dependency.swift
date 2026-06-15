import PocketCastsDependencyInjection

struct FileLogKey: DependencyKey {
    // nonisolated(unsafe): assigned only by tests to inject a mock; production never mutates it.
    nonisolated(unsafe) static var currentValue: any FileLogging = FileLog.shared
}

public extension DefaultDependencyContainer {
    var fileLog: any FileLogging {
        get { Self[FileLogKey.self] }
        nonmutating set { Self[FileLogKey.self] = newValue }
    }
}
