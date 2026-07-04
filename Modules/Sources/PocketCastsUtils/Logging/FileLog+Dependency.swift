import Dependencies

enum FileLogKey: DependencyKey {
    static let liveValue: any FileLogging = FileLog.shared
    // Mirrors liveValue for behavior parity: production singletons (e.g. DownloadManager.shared)
    // resolve \.fileLog inside the app test host, where an unimplemented-dependency failure would
    // be a behavior change, not a safety win. Consumer tests override the key with a mock.
    static let testValue: any FileLogging = FileLog.shared
}

public extension DependencyValues {
    var fileLog: any FileLogging {
        get { self[FileLogKey.self] }
        set { self[FileLogKey.self] = newValue }
    }
}
