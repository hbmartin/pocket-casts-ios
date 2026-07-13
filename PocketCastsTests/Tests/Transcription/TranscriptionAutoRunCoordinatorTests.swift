import PocketCastsTranscription
import XCTest

@testable import podcasts

/// Decision matrix for auto-transcribe-on-download — the pure function behind
/// `TranscriptionAutoRunCoordinator` (the coordinator itself is a thin
/// notification/queue shell around it).
final class TranscriptionAutoRunCoordinatorTests: XCTestCase {
    private func decide(featureEnabled: Bool = true,
                        podcastOptedIn: Bool = true,
                        hasExistingRecord: Bool = false,
                        engineMode: TranscriptionEngineMode = .appleBuiltIn) -> Bool {
        TranscriptionAutoRunDecision.shouldEnqueue(featureEnabled: featureEnabled,
                                                   podcastOptedIn: podcastOptedIn,
                                                   hasExistingRecord: hasExistingRecord,
                                                   engineMode: engineMode)
    }

    func testEnqueuesWhenAllConditionsHold() {
        XCTAssertTrue(decide())
    }

    func testDisabledFeatureFlagBlocks() {
        XCTAssertFalse(decide(featureEnabled: false))
    }

    func testPodcastNotOptedInBlocks() {
        XCTAssertFalse(decide(podcastOptedIn: false))
    }

    func testExistingRecordBlocks() {
        // Any record blocks — completed, failed or cancelled alike. Auto-run
        // never retries; another attempt is the user's call.
        XCTAssertFalse(decide(hasExistingRecord: true))
    }

    func testLocalModelModeQualifies() {
        XCTAssertTrue(decide(engineMode: .localModel))
    }

    func testRemoteProviderModeNeverAutoRuns() {
        // An automatic run must never spend the user's remote-provider credits.
        XCTAssertFalse(decide(engineMode: .remoteProvider))
    }

    func testRemoteProviderModeBlocksEvenWithEverythingElseInPlace() {
        XCTAssertFalse(decide(featureEnabled: true,
                              podcastOptedIn: true,
                              hasExistingRecord: false,
                              engineMode: .remoteProvider))
    }
}
