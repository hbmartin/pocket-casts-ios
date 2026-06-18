import Dependencies

enum FileLogKey: DependencyKey {
    static let liveValue: any FileLogging = FileLog.shared
}

public extension DependencyValues {
    var fileLog: any FileLogging {
        get { self[FileLogKey.self] }
        set { self[FileLogKey.self] = newValue }
    }
}
