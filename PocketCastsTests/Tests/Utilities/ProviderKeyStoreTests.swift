import PocketCastsUtils
import XCTest

@testable import podcasts

/// Round-trips provider API keys through `ProviderKeyStore` against an
/// in-memory keychain, so the tests don't depend on real keychain state.
final class ProviderKeyStoreTests: XCTestCase {
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
        ProviderKeyStore.setAPIKey("aai-key-1", providerId: "assemblyai")
        ProviderKeyStore.setAPIKey("dg-key-2", providerId: "deepgram")

        XCTAssertEqual(ProviderKeyStore.apiKey(providerId: "assemblyai"), "aai-key-1")
        XCTAssertEqual(ProviderKeyStore.apiKey(providerId: "deepgram"), "dg-key-2")
        XCTAssertNil(ProviderKeyStore.apiKey(providerId: "openai"))
    }

    func testKeysAreNamespacedByProviderId() {
        ProviderKeyStore.setAPIKey("secret", providerId: "assemblyai")

        XCTAssertEqual(ProviderKeyStore.keychainKey(providerId: "assemblyai"), "provider.apikey.assemblyai")
        XCTAssertNil(ProviderKeyStore.apiKey(providerId: "assembly"))
    }

    /// Both names are a storage contract with keys already in users' keychains,
    /// so neither may drift: the current one is what shipped builds read, the
    /// legacy one is what the migration below has to find.
    func testTheLegacyKeyNameIsThePreRenameOne() {
        XCTAssertEqual(
            ProviderKeyStore.legacyTranscriptionKey(providerId: "assemblyai"),
            "transcription.apikey.assemblyai"
        )
    }

    func testWhitespaceIsTrimmedOnSave() {
        ProviderKeyStore.setAPIKey("  padded-key \n", providerId: "openai")

        XCTAssertEqual(ProviderKeyStore.apiKey(providerId: "openai"), "padded-key")
    }

    func testEmptyOrNilInputDeletesTheKey() {
        ProviderKeyStore.setAPIKey("to-be-deleted", providerId: "gemini")
        ProviderKeyStore.setAPIKey("   ", providerId: "gemini")
        XCTAssertNil(ProviderKeyStore.apiKey(providerId: "gemini"))

        ProviderKeyStore.setAPIKey("to-be-deleted-again", providerId: "gemini")
        ProviderKeyStore.setAPIKey(nil, providerId: "gemini")
        XCTAssertNil(ProviderKeyStore.apiKey(providerId: "gemini"))
    }

    func testDeleteAPIKeyRemovesStoredValue() {
        ProviderKeyStore.setAPIKey("gone-soon", providerId: "elevenlabs")
        ProviderKeyStore.deleteAPIKey(providerId: "elevenlabs")

        XCTAssertNil(ProviderKeyStore.apiKey(providerId: "elevenlabs"))
    }

    // MARK: - Legacy migration (ADR-0021)

    /// A key entered before keys became vendor-scoped must keep working, or the
    /// rename would silently look like "your key vanished".
    func testALegacyTranscriptionKeyIsFoundAndPromoted() {
        KeychainHelper.save(string: "legacy-key",
                            key: ProviderKeyStore.legacyTranscriptionKey(providerId: "elevenlabs"),
                            accessibility: kSecAttrAccessibleAfterFirstUnlock)

        XCTAssertEqual(ProviderKeyStore.apiKey(providerId: "elevenlabs"), "legacy-key")
        // Promoted forward, so the fallback is paid for once rather than on
        // every read.
        XCTAssertEqual(
            try? KeychainHelper.string(for: ProviderKeyStore.keychainKey(providerId: "elevenlabs")),
            "legacy-key"
        )
    }

    func testTheVendorScopedKeyWinsOverALegacyOne() {
        KeychainHelper.save(string: "legacy-key",
                            key: ProviderKeyStore.legacyTranscriptionKey(providerId: "elevenlabs"),
                            accessibility: kSecAttrAccessibleAfterFirstUnlock)
        ProviderKeyStore.setAPIKey("current-key", providerId: "elevenlabs")

        XCTAssertEqual(ProviderKeyStore.apiKey(providerId: "elevenlabs"), "current-key")
    }

    /// Otherwise "remove my key" leaves a copy the fallback resurrects on the
    /// next read.
    func testDeletingAlsoClearsTheLegacyItem() {
        KeychainHelper.save(string: "legacy-key",
                            key: ProviderKeyStore.legacyTranscriptionKey(providerId: "elevenlabs"),
                            accessibility: kSecAttrAccessibleAfterFirstUnlock)
        ProviderKeyStore.setAPIKey("current-key", providerId: "elevenlabs")

        ProviderKeyStore.deleteAPIKey(providerId: "elevenlabs")

        XCTAssertNil(ProviderKeyStore.apiKey(providerId: "elevenlabs"))
    }
}
