import Foundation
import PocketCastsUtils

/// Keychain storage for the user's third-party API keys.
///
/// Credentials are scoped by both vendor and purpose. Providers such as
/// ElevenLabs let users issue least-privilege keys independently for speech to
/// text and text to speech; saving one must not overwrite or broaden the other.
///
/// Keys written by older builds used `provider.apikey.<id>` (and, before that,
/// `transcription.apikey.<id>`). Each purpose lazily imports either legacy item
/// once. A per-purpose migration marker prevents a later delete from reviving
/// the legacy value while leaving it available to older app builds and to the
/// other purpose's independent migration.
///
/// IMPORTANT: these keys are deliberately not cleared on Pocket Casts logout.
/// They are the user's own provider credentials and are unrelated to the Pocket
/// Casts account.
nonisolated enum ProviderKeyStore {
    enum Purpose: String, Sendable {
        case speechToText = "speech-to-text"
        case textToSpeech = "text-to-speech"
    }

    /// Serializes each read/promote/write/delete sequence so deletion cannot be
    /// undone by a concurrent legacy promotion.
    private static let lock = NSLock()

    /// The vendor-scoped key used by older builds. Kept as an API because tests
    /// and migration code treat the identifier as a shipped storage contract.
    static func keychainKey(providerId: String) -> String {
        "provider.apikey.\(providerId)"
    }

    static func keychainKey(providerId: String, purpose: Purpose) -> String {
        "provider.apikey.\(purpose.rawValue).\(providerId)"
    }

    /// The key used before credentials first became vendor-scoped.
    static func legacyTranscriptionKey(providerId: String) -> String {
        "transcription.apikey.\(providerId)"
    }

    static func normalizedAPIKey(_ apiKey: String?) -> String? {
        guard let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func apiKey(providerId: String, purpose: Purpose) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let key = storedKey(keychainKey(providerId: providerId, purpose: purpose)) {
            return key
        }
        guard storedKey(migrationMarkerKey(providerId: providerId, purpose: purpose)) == nil else {
            return nil
        }

        guard let legacy = storedKey(keychainKey(providerId: providerId))
            ?? storedKey(legacyTranscriptionKey(providerId: providerId)) else {
            return nil
        }

        let saved = KeychainHelper.save(
            string: legacy,
            key: keychainKey(providerId: providerId, purpose: purpose),
            accessibility: kSecAttrAccessibleAfterFirstUnlock
        )
        if saved {
            markMigration(providerId: providerId, purpose: purpose)
        }
        return legacy
    }

    @discardableResult
    static func setAPIKey(_ apiKey: String?, providerId: String, purpose: Purpose) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let key = keychainKey(providerId: providerId, purpose: purpose)
        if let normalized = normalizedAPIKey(apiKey) {
            let saved = KeychainHelper.save(
                string: normalized,
                key: key,
                accessibility: kSecAttrAccessibleAfterFirstUnlock
            )
            guard saved else { return false }
            return markMigration(providerId: providerId, purpose: purpose)
        } else {
            // Write the tombstone before deleting. If it cannot be persisted,
            // retain the current scoped value rather than claiming success and
            // letting a legacy fallback resurrect after the failed delete.
            guard markMigration(providerId: providerId, purpose: purpose) else { return false }
            return KeychainHelper.removeKey(key)
        }
    }

    @discardableResult
    static func deleteAPIKey(providerId: String, purpose: Purpose) -> Bool {
        setAPIKey(nil, providerId: providerId, purpose: purpose)
    }

    // MARK: - Compatibility

    /// Remaining call sites from the Read Aloud feature's first release use the
    /// vendor-only spelling. Keep them source-compatible while routing them to
    /// the text-to-speech slot; new code should always state its purpose.
    static func apiKey(providerId: String) -> String? {
        apiKey(providerId: providerId, purpose: .textToSpeech)
    }

    @discardableResult
    static func setAPIKey(_ apiKey: String?, providerId: String) -> Bool {
        setAPIKey(apiKey, providerId: providerId, purpose: .textToSpeech)
    }

    @discardableResult
    static func deleteAPIKey(providerId: String) -> Bool {
        deleteAPIKey(providerId: providerId, purpose: .textToSpeech)
    }

    // MARK: - Migration internals

    private static func migrationMarkerKey(providerId: String, purpose: Purpose) -> String {
        "provider.apikey.migrated.\(purpose.rawValue).\(providerId)"
    }

    private static func storedKey(_ key: String) -> String? {
        guard let value = try? KeychainHelper.string(for: key) else { return nil }
        return normalizedAPIKey(value)
    }

    @discardableResult
    private static func markMigration(providerId: String, purpose: Purpose) -> Bool {
        KeychainHelper.save(
            string: "1",
            key: migrationMarkerKey(providerId: providerId, purpose: purpose),
            accessibility: kSecAttrAccessibleAfterFirstUnlock
        )
    }
}
