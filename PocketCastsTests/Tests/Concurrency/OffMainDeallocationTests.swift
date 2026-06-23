import AVFoundation
import XCTest
@testable import podcasts

/// Safety-harness tests for the Swift 6.2 default-actor-isolation migration.
///
/// Each test asserts that a utility / I-O class — one that is, in production, deallocated off the main
/// thread — still deallocates synchronously off the main actor. These pass on the current `nonisolated`
/// code and are designed to fail if the migration wrongly makes one of these classes `@MainActor` with
/// an `isolated deinit` (which the compiler will not flag, but which crashes or hangs at runtime). See
/// `assertDeallocatesOffMain` in `OffMainDeallocationTesting.swift`.
final class OffMainDeallocationTests: XCTestCase {

    func testStreamingCellularTracker_deallocatesOffMain() {
        // deinit calls stopTracking() → monitorQueue.sync + NotificationCenter.removeObserver.
        assertDeallocatesOffMain { StreamingCellularTracker() }
    }

    func testWidgetHelper_deallocatesOffMain() {
        // deinit removes ~10 NotificationCenter observers.
        assertDeallocatesOffMain { WidgetHelper() }
    }

    func testAVFileUtil_deallocatesOffMain() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("offmain_dealloc_test.m4a")
        assertDeallocatesOffMain {
            AVFileUtil(
                fileURL: url,
                durationHandler: { _ in
                    // Intentionally no-op: deallocation harness only.
                },
                titleHandler: { _ in
                    // Intentionally no-op: deallocation harness only.
                },
                artworkHandler: { _ in
                    // Intentionally no-op: deallocation harness only.
                }
            )
        }
    }

    func testMediaFileHandle_deallocatesOffMain() {
        // The class that exposed the migration risk: a file-handle wrapper released off-main.
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent(UUID().uuidString + "_offmain.media")
        defer { try? FileManager.default.removeItem(atPath: path) }
        assertDeallocatesOffMain { MediaFileHandle(filePath: path) }
    }

    func testImageManager_deallocatesOffMain() {
        // deinit removes a NotificationCenter observer.
        assertDeallocatesOffMain { ImageManager() }
    }
}
