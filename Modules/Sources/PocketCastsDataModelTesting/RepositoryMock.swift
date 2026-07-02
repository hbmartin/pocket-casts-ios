import Foundation
import PocketCastsDataModel

/// Shared machinery for the generated repository mocks: selector-keyed stubs
/// and invocation recording.
///
/// `@unchecked Sendable`: required because the repository protocols the mocks conform to are
/// `Sendable`; all mutable state is guarded by `lock`.
open class RepositoryMock: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedInvocations: [String] = []
    private var stubbedValues: [String: Any] = [:]

    /// Selector-keyed stub values, read directly by the generated mock methods.
    public var stubs: [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return stubbedValues
    }

    public var invocations: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedInvocations
    }

    public init() {}

    public func stub(_ selector: String, with value: Any) {
        lock.lock()
        defer { lock.unlock() }
        stubbedValues[selector] = value
    }

    public func callCount(of selector: String) -> Int {
        invocations.filter { $0 == selector }.count
    }

    public func record(_ selector: String) {
        lock.lock()
        defer { lock.unlock() }
        recordedInvocations.append(selector)
    }
}
