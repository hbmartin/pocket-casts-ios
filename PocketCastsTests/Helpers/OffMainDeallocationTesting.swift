import XCTest

extension XCTestCase {
    /// Asserts that the object produced by `make()` deallocates **synchronously, off the main actor**.
    ///
    /// This is a safety net for the Swift 6.2 default-actor-isolation migration. Under
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, every app-target class becomes `@MainActor` unless
    /// it opts out with `nonisolated`. A utility / I-O / model class that is *deallocated off the main
    /// thread* (e.g. `MediaFileHandle` released on a URLSession callback queue) must stay `nonisolated`:
    /// if it wrongly becomes `@MainActor`, its `deinit` either fails to compile or, when made an
    /// `isolated deinit` to compile, the deallocation is forced to hop to the main actor — which crashes
    /// or is silently deferred. The compiler does **not** catch this; only a test like this does.
    ///
    /// The check: release the object's last strong reference on a background queue. A `nonisolated`
    /// deinit runs inline there, so the `weak` reference is already `nil` immediately afterwards. A
    /// main-actor `isolated deinit` cannot run on the background queue, so the reference is still alive
    /// (or the process crashes) — and this assertion fails.
    ///
    /// Passes on the current (correctly `nonisolated`) code; designed to fail if the class is wrongly
    /// made main-actor-isolated.
    func assertDeallocatesOffMain<T: AnyObject>(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ make: @escaping @Sendable () -> T
    ) {
        let finished = expectation(description: "off-main deallocation")
        let queue = DispatchQueue(label: "com.pocketcasts.tests.offMainDealloc")
        queue.async {
            weak var weakRef: T?
            autoreleasepool {
                let object = make()
                weakRef = object
                // `object` goes out of scope at the end of this autoreleasepool, on the background
                // queue, releasing the last strong reference there.
            }
            XCTAssertNil(
                weakRef,
                "Object did not deallocate synchronously off the main actor — it may have become "
                    + "@MainActor with an isolated deinit. Utility/I-O classes released off-main must "
                    + "stay `nonisolated`.",
                file: file,
                line: line
            )
            finished.fulfill()
        }
        wait(for: [finished], timeout: timeout)
    }
}
