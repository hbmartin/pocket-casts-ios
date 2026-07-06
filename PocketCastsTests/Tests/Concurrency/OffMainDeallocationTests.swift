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

    func testDownloadProgressManager_deallocatesOffMain() {
        assertDeallocatesOffMain { DownloadProgressManager() }
    }

    func testThreadSafeDictionary_deallocatesOffMain() {
        assertDeallocatesOffMain { ThreadSafeDictionary<String, Int>() }
    }

    func testPodcastChapterParser_deallocatesOffMain() {
        assertDeallocatesOffMain { PodcastChapterParser() }
    }

    func testEpisodeFileSizeUpdater_deallocatesOffMain() {
        assertDeallocatesOffMain { EpisodeFileSizeUpdater() }
    }

    func testAutoplayHelper_deallocatesOffMain() {
        assertDeallocatesOffMain { AutoplayHelper() }
    }

    func testWidgetAnalytics_deallocatesOffMain() {
        assertDeallocatesOffMain { WidgetAnalytics() }
    }

    /// Stress variant for the class that produced a real use-after-free: AVFileUtil
    /// starts detached metadata-loading tasks in init, and the owner releases it
    /// while those tasks are in flight. Rapid create/release cycles across queues
    /// widen the race window that a single-shot test usually misses.
    func testAVFileUtil_rapidCreateReleaseWhileTasksInFlight() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("offmain_stress_test.m4a")
        for _ in 0..<30 {
            assertDeallocatesOffMain {
                AVFileUtil(
                    fileURL: url,
                    durationHandler: { _ in },
                    titleHandler: { _ in },
                    artworkHandler: { _ in }
                )
            }
        }
    }

    func testMediaFileHandle_rapidCreateReleaseStress() {
        for _ in 0..<30 {
            let path = (NSTemporaryDirectory() as NSString)
                .appendingPathComponent(UUID().uuidString + "_offmain_stress.media")
            defer { try? FileManager.default.removeItem(atPath: path) }
            assertDeallocatesOffMain { MediaFileHandle(filePath: path) }
        }
    }
}
