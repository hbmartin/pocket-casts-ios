import Foundation
import PocketCastsUtils

/// Keychain storage for the user's remote-transcription API keys, one item per
/// provider (`transcription.apikey.<providerId>`).
///
/// IMPORTANT: these keys are **deliberately NOT cleared on logout**. They are the
/// user's own third-party provider credentials (AssemblyAI, Deepgram, …), entered
/// by hand and unrelated to the Pocket Casts account — signing out of Pocket Casts
/// must not destroy them. Do not add these keys to any sign-out cleanup path.
///
/// Key material must never be logged; nothing in here (or in the provider
/// adapters) writes the key anywhere except the keychain and the provider's
/// auth header.
nonisolated enum TranscriptionKeyStore {
    /// `kSecAttrAccessibleAfterFirstUnlock` so a queued job restored by the
    /// background processing task can read the key without the device being
    /// actively unlocked.
    static func keychainKey(providerId: String) -> String {
        "transcription.apikey.\(providerId)"
    }

    /// The stored key for a provider, or nil when none has been entered (or the
    /// stored value is empty).
    static func apiKey(providerId: String) -> String? {
        guard let key = try? KeychainHelper.string(for: keychainKey(providerId: providerId)),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    /// Stores (or, for nil/whitespace-only input, deletes) the provider's key.
    static func setAPIKey(_ apiKey: String?, providerId: String) {
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            KeychainHelper.save(string: trimmed,
                                key: keychainKey(providerId: providerId),
                                accessibility: kSecAttrAccessibleAfterFirstUnlock)
        } else {
            KeychainHelper.removeKey(keychainKey(providerId: providerId))
        }
    }

    static func deleteAPIKey(providerId: String) {
        KeychainHelper.removeKey(keychainKey(providerId: providerId))
    }
}
