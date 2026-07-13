import PocketCastsTranscription
import XCTest

@testable import podcasts

/// Exercises the consent bookkeeping of `TranscriptionConsentGate` (the
/// UserDefaults flags and the needs-consent decision); presenting the prompt
/// itself is UI and stays untested here.
@MainActor
final class TranscriptionConsentGateTests: XCTestCase {
    private var previousEngineMode: Int32 = 0
    private var previousProviderId: String!
    private var touchedProviderIds: Set<String> = []

    override func setUp() {
        super.setUp()
        previousEngineMode = Settings.transcriptionEngineMode()
        previousProviderId = Settings.transcriptionRemoteProvider()
        touchedProviderIds = []
    }

    override func tearDown() {
        Settings.setTranscriptionEngineMode(previousEngineMode)
        Settings.setTranscriptionRemoteProvider(previousProviderId)
        for providerId in touchedProviderIds {
            UserDefaults.standard.removeObject(forKey: TranscriptionConsentGate.consentDefaultsKey(providerId: providerId))
        }
        super.tearDown()
    }

    /// Registers a provider consent flag for cleanup and returns its id.
    private func trackedProvider(_ providerId: String) -> String {
        touchedProviderIds.insert(providerId)
        return providerId
    }

    func testConsentIsPersistedPerProvider() {
        let assemblyai = trackedProvider("assemblyai")
        let openai = trackedProvider("openai")

        XCTAssertFalse(TranscriptionConsentGate.hasConsent(providerId: assemblyai))
        TranscriptionConsentGate.recordConsent(providerId: assemblyai)

        XCTAssertTrue(TranscriptionConsentGate.hasConsent(providerId: assemblyai))
        XCTAssertFalse(TranscriptionConsentGate.hasConsent(providerId: openai), "Consent must not leak across providers")
    }

    func testLocalModesNeverNeedConsent() {
        Settings.setTranscriptionEngineMode(TranscriptionEngineMode.appleBuiltIn.rawValue)
        Settings.setTranscriptionRemoteProvider(trackedProvider("assemblyai"))

        XCTAssertFalse(TranscriptionConsentGate.needsConsent())
    }

    func testRemoteModeNeedsConsentUntilGranted() {
        Settings.setTranscriptionEngineMode(TranscriptionEngineMode.remoteProvider.rawValue)
        let providerId = trackedProvider("deepgram")
        Settings.setTranscriptionRemoteProvider(providerId)

        XCTAssertTrue(TranscriptionConsentGate.needsConsent())
        TranscriptionConsentGate.recordConsent(providerId: providerId)
        XCTAssertFalse(TranscriptionConsentGate.needsConsent())
    }

    func testSwitchingProviderRequiresFreshConsent() {
        Settings.setTranscriptionEngineMode(TranscriptionEngineMode.remoteProvider.rawValue)
        let consented = trackedProvider("deepgram")
        let unconsented = trackedProvider("gemini")

        Settings.setTranscriptionRemoteProvider(consented)
        TranscriptionConsentGate.recordConsent(providerId: consented)
        XCTAssertFalse(TranscriptionConsentGate.needsConsent())

        Settings.setTranscriptionRemoteProvider(unconsented)
        XCTAssertTrue(TranscriptionConsentGate.needsConsent())
    }

    func testConsentedRemoteModeRunsEnqueueImmediately() {
        Settings.setTranscriptionEngineMode(TranscriptionEngineMode.remoteProvider.rawValue)
        let providerId = trackedProvider("assemblyai")
        Settings.setTranscriptionRemoteProvider(providerId)
        TranscriptionConsentGate.recordConsent(providerId: providerId)

        var enqueued = false
        TranscriptionConsentGate.requestConsentIfNeeded { enqueued = true }

        XCTAssertTrue(enqueued)
    }

    func testLocalModeRunsEnqueueImmediately() {
        Settings.setTranscriptionEngineMode(TranscriptionEngineMode.appleBuiltIn.rawValue)

        var enqueued = false
        TranscriptionConsentGate.requestConsentIfNeeded { enqueued = true }

        XCTAssertTrue(enqueued)
    }
}
