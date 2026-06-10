import Foundation
import PocketCastsDataModel

/// Shared machinery for the generated repository mocks: selector-keyed stubs
/// and invocation recording.
open class RepositoryMock {
    public private(set) var invocations: [String] = []
    public var stubs: [String: Any] = [:]

    public init() {}

    public func stub(_ selector: String, with value: Any) {
        stubs[selector] = value
    }

    public func callCount(of selector: String) -> Int {
        invocations.filter { $0 == selector }.count
    }

    public func record(_ selector: String) {
        invocations.append(selector)
    }
}
