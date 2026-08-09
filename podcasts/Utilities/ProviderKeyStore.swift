import Foundation
import PocketCastsUtils

/// Keychain storage for the user's third-party API keys, one item per vendor
/// (`provider.apikey.<id>`).
///
/// Keyed by *vendor*, not by feature, because that is what the key actually is
/// (ADR-0021). ElevenLabs authenticates both transcription and Read Aloud with
/// the same account credential, so asking for it twice — and letting one screen
/// say "configured" while the other says nothing — would be describing our own
/// architecture rather than the user's account.
///
/// IMPORTANT: these keys are **deliberately NOT cleared on logout**. They are the
/// user's own provider credentials, entered by hand and unrelated to the Pocket
/// Casts account — signing out must not destroy them. Do not add these keys to
/// any sign-out cleanup path.
///
/// Key material must never be logged; nothing in here (or in the provider
/// adapters) writes the key anywhere except the keychain and the provider's
/// auth header.
nonisolated enum ProviderKeyStore {
    /// `kSecAttrAccessibleAfterFirstUnlock` so a queued job restored by a
    /// background task can read the key without the device being unlocked.
    static func keychainKey(providerId: String) -> String {
        "provider.apikey.\(providerId)"
    }

    /// The key this feature used before keys became vendor-scoped. Read as a
    /// fallback and promoted on first read, so nobody re-enters a credential
    /// they already gave the app.
    static func legacyTranscriptionKey(providerId: String) -> String {
        "transcription.apikey.\(providerId)"
    }

    /// The stored key for a vendor, or nil when none has been entered (or the
    /// stored value is empty).
    ///
    /// Falls back to the legacy transcription-scoped item and migrates it
    /// forward on the way past. The legacy item is left in place: an older build
    /// running against the same keychain still expects to find it there.
    static func apiKey(providerId: String) -> String? {
        if let key = try? KeychainHelper.string(for: keychainKey(providerId: providerId)), !key.isEmpty {
            return key
        }
        guard let legacy = try? KeychainHelper.string(for: legacyTranscriptionKey(providerId: providerId)),
              !legacy.isEmpty else {
            return nil
        }
        setAPIKey(legacy, providerId: providerId)
        return legacy
    }

    /// Stores (or, for nil/whitespace-only input, deletes) the vendor's key.
    ///
    /// A delete clears the legacy item too — otherwise "remove my key" would
    /// leave a copy that the fallback above immediately resurrects.
    static func setAPIKey(_ apiKey: String?, providerId: String) {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            KeychainHelper.save(string: trimmed,
                                key: keychainKey(providerId: providerId),
                                accessibility: kSecAttrAccessibleAfterFirstUnlock)
        } else {
            KeychainHelper.removeKey(keychainKey(providerId: providerId))
            KeychainHelper.removeKey(legacyTranscriptionKey(providerId: providerId))
        }
    }

    static func deleteAPIKey(providerId: String) {
        setAPIKey(nil, providerId: providerId)
    }
}
