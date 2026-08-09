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
        ProviderKeyStore.setAPIKey("aai-key-1", providerId: "assemblyai", purpose: .speechToText)
        ProviderKeyStore.setAPIKey("dg-key-2", providerId: "deepgram", purpose: .speechToText)

        XCTAssertEqual(ProviderKeyStore.apiKey(providerId: "assemblyai", purpose: .speechToText), "aai-key-1")
        XCTAssertEqual(ProviderKeyStore.apiKey(providerId: "deepgram", purpose: .speechToText), "dg-key-2")
        XCTAssertNil(ProviderKeyStore.apiKey(providerId: "openai", purpose: .speechToText))
    }

    func testKeysAreNamespacedByProviderId() {
        ProviderKeyStore.setAPIKey("secret", providerId: "assemblyai", purpose: .speechToText)

        XCTAssertEqual(ProviderKeyStore.keychainKey(providerId: "assemblyai"), "provider.apikey.assemblyai")
        XCTAssertEqual(
            ProviderKeyStore.keychainKey(providerId: "assemblyai", purpose: .speechToText),
            "provider.apikey.speech-to-text.assemblyai"
        )
        XCTAssertNil(ProviderKeyStore.apiKey(providerId: "assembly", purpose: .speechToText))
    }

    func testSpeechToTextAndTextToSpeechKeysAreIndependent() {
        ProviderKeyStore.setAPIKey("stt-only", providerId: "elevenlabs", purpose: .speechToText)
        ProviderKeyStore.setAPIKey("tts-only", providerId: "elevenlabs", purpose: .textToSpeech)

        XCTAssertEqual(
            ProviderKeyStore.apiKey(providerId: "elevenlabs", purpose: .speechToText),
            "stt-only"
        )
        XCTAssertEqual(
            ProviderKeyStore.apiKey(providerId: "elevenlabs", purpose: .textToSpeech),
            "tts-only"
        )

        ProviderKeyStore.deleteAPIKey(providerId: "elevenlabs", purpose: .textToSpeech)

        XCTAssertEqual(
            ProviderKeyStore.apiKey(providerId: "elevenlabs", purpose: .speechToText),
            "stt-only"
        )
        XCTAssertNil(ProviderKeyStore.apiKey(providerId: "elevenlabs", purpose: .textToSpeech))
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
        ProviderKeyStore.setAPIKey("  padded-key \n", providerId: "openai", purpose: .speechToText)

        XCTAssertEqual(ProviderKeyStore.apiKey(providerId: "openai", purpose: .speechToText), "padded-key")
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

        XCTAssertEqual(
            ProviderKeyStore.apiKey(providerId: "elevenlabs", purpose: .textToSpeech),
            "legacy-key"
        )
        // Promoted forward, so the fallback is paid for once rather than on
        // every read.
        XCTAssertEqual(
            try? KeychainHelper.string(for: ProviderKeyStore.keychainKey(
                providerId: "elevenlabs",
                purpose: .textToSpeech
            )),
            "legacy-key"
        )
    }

    func testVendorScopedLegacyKeyMigratesIndependentlyToBothPurposes() {
        KeychainHelper.save(
            string: "shared-legacy-key",
            key: ProviderKeyStore.keychainKey(providerId: "elevenlabs"),
            accessibility: kSecAttrAccessibleAfterFirstUnlock
        )

        XCTAssertEqual(
            ProviderKeyStore.apiKey(providerId: "elevenlabs", purpose: .speechToText),
            "shared-legacy-key"
        )
        XCTAssertEqual(
            ProviderKeyStore.apiKey(providerId: "elevenlabs", purpose: .textToSpeech),
            "shared-legacy-key"
        )

        ProviderKeyStore.deleteAPIKey(providerId: "elevenlabs", purpose: .textToSpeech)

        XCTAssertNil(ProviderKeyStore.apiKey(providerId: "elevenlabs", purpose: .textToSpeech))
        XCTAssertEqual(
            ProviderKeyStore.apiKey(providerId: "elevenlabs", purpose: .speechToText),
            "shared-legacy-key"
        )
    }

    func testDeleteKeepsTheCredentialWhenMigrationTombstoneCannotBeSaved() throws {
        let failingStore = MarkerFailingKeychainStore()
        KeychainHelper.store = failingStore
        let providerId = "marker-failure"
        KeychainHelper.save(
            string: "legacy-key",
            key: ProviderKeyStore.keychainKey(providerId: providerId),
            accessibility: kSecAttrAccessibleAfterFirstUnlock
        )

        XCTAssertEqual(
            ProviderKeyStore.apiKey(providerId: providerId, purpose: .textToSpeech),
            "legacy-key"
        )
        XCTAssertFalse(ProviderKeyStore.deleteAPIKey(providerId: providerId, purpose: .textToSpeech))
        XCTAssertEqual(
            ProviderKeyStore.apiKey(providerId: providerId, purpose: .textToSpeech),
            "legacy-key",
            "A failed tombstone must retain the scoped key instead of exposing the legacy fallback"
        )
        XCTAssertEqual(
            try KeychainHelper.string(for: ProviderKeyStore.keychainKey(
                providerId: providerId,
                purpose: .textToSpeech
            )),
            "legacy-key"
        )
    }

    func testSetReportsWhenSecurePersistenceFails() {
        KeychainHelper.store = ScopedSaveFailingKeychainStore()

        XCTAssertFalse(ProviderKeyStore.setAPIKey(
            "new-key",
            providerId: "save-failure",
            purpose: .textToSpeech
        ))
        XCTAssertNil(ProviderKeyStore.apiKey(providerId: "save-failure", purpose: .textToSpeech))
    }

    func testTheVendorScopedKeyWinsOverALegacyOne() {
        KeychainHelper.save(string: "legacy-key",
                            key: ProviderKeyStore.legacyTranscriptionKey(providerId: "elevenlabs"),
                            accessibility: kSecAttrAccessibleAfterFirstUnlock)
        ProviderKeyStore.setAPIKey("current-key", providerId: "elevenlabs")

        XCTAssertEqual(ProviderKeyStore.apiKey(providerId: "elevenlabs"), "current-key")
    }

    /// Interleaves the legacy read-then-promote sequence with deletion. Without
    /// the store's internal lock, a read that has already found the legacy value
    /// can promote it back after the delete, resurrecting a key the user
    /// removed. Whichever order wins under the lock, the end state is "gone".
    func testDeletionIsNotUndoneByAConcurrentLegacyPromotion() {
        for iteration in 0 ..< 200 {
            let providerId = "elevenlabs-\(iteration)"
            KeychainHelper.save(string: "legacy-key",
                                key: ProviderKeyStore.legacyTranscriptionKey(providerId: providerId),
                                accessibility: kSecAttrAccessibleAfterFirstUnlock)

            let group = DispatchGroup()
            DispatchQueue.global().async(group: group) {
                _ = ProviderKeyStore.apiKey(providerId: providerId)
            }
            DispatchQueue.global().async(group: group) {
                ProviderKeyStore.deleteAPIKey(providerId: providerId)
            }
            group.wait()

            XCTAssertNil(ProviderKeyStore.apiKey(providerId: providerId),
                         "A deleted key must stay deleted even with a legacy promotion in flight")
        }
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

private final class MarkerFailingKeychainStore: KeychainStoring, Sendable {
    private let backing = InMemoryKeychainStore()

    func save(value: String?, key: String, accessibility: CFTypeRef) -> Bool {
        guard !key.contains("provider.apikey.migrated.") else { return false }
        return backing.save(value: value, key: key, accessibility: accessibility)
    }

    func string(for key: String) throws -> String? {
        try backing.string(for: key)
    }
}

private final class ScopedSaveFailingKeychainStore: KeychainStoring, Sendable {
    private let backing = InMemoryKeychainStore()

    func save(value: String?, key: String, accessibility: CFTypeRef) -> Bool {
        guard !key.contains("provider.apikey.text-to-speech.") else { return false }
        return backing.save(value: value, key: key, accessibility: accessibility)
    }

    func string(for key: String) throws -> String? {
        try backing.string(for: key)
    }
}
