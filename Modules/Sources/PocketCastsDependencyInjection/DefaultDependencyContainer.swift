import Foundation

public struct DefaultDependencyContainer: DependencyContainer {
    // The container itself is immutable; by-design global mutability lives in each
    // DependencyKey's currentValue.
    public static var current: DefaultDependencyContainer {
        get { DefaultDependencyContainer() }
        @available(*, unavailable, message: "DefaultDependencyContainer.current is read-only; override individual DependencyKey values instead.")
        set { }
    }

    private init() { }
}
