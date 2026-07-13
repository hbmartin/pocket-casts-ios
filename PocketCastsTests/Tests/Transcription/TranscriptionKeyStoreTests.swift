import PocketCastsUtils
import XCTest

@testable import podcasts

/// Round-trips provider API keys through `TranscriptionKeyStore` against an
/// in-memory keychain, so the tests don't depend on real keychain state.
final class TranscriptionKeyStoreTests: XCTestCase {
    private var previousKeychainStore: KeychainStoring!

    override func setUp() {
        super.setUp()
        previousKeychainStore = KeychainHelper.store
        KeychainHelper.store = InMemoryKeychainStore()
    }

    override func tearDown() {
        KeychainHelper.store = previousKeychainStore
        super.tearDown()
    }

    func testKeysRoundTripPerProvider() {
        TranscriptionKeyStore.setAPIKey("aai-key-1", providerId: "assemblyai")
        TranscriptionKeyStore.setAPIKey("dg-key-2", providerId: "deepgram")

        XCTAssertEqual(TranscriptionKeyStore.apiKey(providerId: "assemblyai"), "aai-key-1")
        XCTAssertEqual(TranscriptionKeyStore.apiKey(providerId: "deepgram"), "dg-key-2")
        XCTAssertNil(TranscriptionKeyStore.apiKey(providerId: "openai"))
    }

    func testKeysAreNamespacedByProviderId() {
        TranscriptionKeyStore.setAPIKey("secret", providerId: "assemblyai")

        XCTAssertEqual(TranscriptionKeyStore.keychainKey(providerId: "assemblyai"), "transcription.apikey.assemblyai")
        XCTAssertNil(TranscriptionKeyStore.apiKey(providerId: "assembly"))
    }

    func testWhitespaceIsTrimmedOnSave() {
        TranscriptionKeyStore.setAPIKey("  padded-key \n", providerId: "openai")

        XCTAssertEqual(TranscriptionKeyStore.apiKey(providerId: "openai"), "padded-key")
    }

    func testEmptyOrNilInputDeletesTheKey() {
        TranscriptionKeyStore.setAPIKey("to-be-deleted", providerId: "gemini")
        TranscriptionKeyStore.setAPIKey("   ", providerId: "gemini")
        XCTAssertNil(TranscriptionKeyStore.apiKey(providerId: "gemini"))

        TranscriptionKeyStore.setAPIKey("to-be-deleted-again", providerId: "gemini")
        TranscriptionKeyStore.setAPIKey(nil, providerId: "gemini")
        XCTAssertNil(TranscriptionKeyStore.apiKey(providerId: "gemini"))
    }

    func testDeleteAPIKeyRemovesStoredValue() {
        TranscriptionKeyStore.setAPIKey("gone-soon", providerId: "elevenlabs")
        TranscriptionKeyStore.deleteAPIKey(providerId: "elevenlabs")

        XCTAssertNil(TranscriptionKeyStore.apiKey(providerId: "elevenlabs"))
    }
}
