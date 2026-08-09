# API keys are stored per vendor, not per feature

The user's third-party API keys live in the keychain under `provider.apikey.<id>`,
one item per vendor, shared by every feature that talks to that vendor.
`ProviderKeyStore` owns them; `TranscriptionKeyStore`, which stored the same
credentials under `transcription.apikey.<id>`, is gone.

The forcing case is ElevenLabs. It is both a transcription provider (`v1/speech-to-text`,
shipped) and a Read Aloud provider (`v1/text-to-speech`, added alongside this),
authenticated by the same account credential in the same `xi-api-key` header. Keyed by
feature, a user who had already given the app their key would be asked for it again by a
different screen, and the two screens would disagree about whether ElevenLabs was
"configured" — which describes our module boundaries rather than the user's account. The
key is a fact about their vendor relationship; the features are our business.

Reading falls back to the legacy `transcription.apikey.<id>` item and promotes it forward on
first read, so nobody re-enters a credential they already supplied. The legacy item is
deliberately left in place — an older build running against the same keychain still expects
to find it there — but deleting a key clears both, or the fallback would resurrect a key the
user just removed.

Rejected: separate items per feature (a second entry of the same secret, and two screens
disagreeing about the same account), and a read-only fallback with feature-scoped writes
(two items that silently diverge the first time either is edited).

## Consequences

- Entering the key on the Read Aloud settings screen configures transcription too, and vice
  versa. This is intended and should be described that way in copy, not hidden.
- **A shared key does not mean shared permissions.** ElevenLabs keys are scoped, so a key
  granted only speech-to-text authenticates perfectly and then refuses text-to-speech. That
  is why `ReadAloudError` distinguishes `insufficientKeyPermissions` from `invalidAPIKey`:
  telling someone their key is invalid would send them to regenerate a credential that works
  fine for the other feature. The settings screen reports the two differently.
- Keys remain **deliberately excluded from sign-out cleanup**. They are the user's own
  provider credentials, unrelated to their Pocket Casts account; signing out must not destroy
  them. Any future sign-out sweep must continue to skip the `provider.apikey.` prefix.
- Storage stays `kSecAttrAccessibleAfterFirstUnlock`, so work resumed by a background task can
  read the key without the device being actively unlocked.
- A third feature wanting the same vendor gets it for free; a vendor whose features genuinely
  need distinct credentials would need a per-scope id (`elevenlabs.tts`), which the
  `providerId` key already accommodates without a schema change.
