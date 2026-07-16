# Public social identity is opt-in, keyed to the server uuid, addressed by an immutable handle

Social features need a durable, addressable public identity, but today identity on
this fork is device-local and stubbed: the account display name is a hardcoded `nil`
placeholder (`UserInfo.swift`), and the only real "profile" is the **Share Profile**
card — a display name in UserDefaults plus a JPEG on disk, never synced. We decided
that public identity is **opt-in**: an account has no handle, no public footprint and
no ability to act socially until an explicit one-time **Join** (claim a handle + accept
public-identity terms). Pre-Join, everything behaves exactly as it does today. The
addressable identity is an `@handle` that is **immutable and permanent** in the
user-facing UI, resolving to `pca.st/u/<handle>`, but the **canonical stored identity
remains the immutable server `uuid`** (`ServerSettings.userId`). This mirrors the
transcript-contribution precedent (ADR-0002/0003): fork-owned endpoints, not sync
Records, and App Attest as the first-party proof on write paths.

## Consequences

- **Join requires a logged-in synced account.** Anonymous/local users must sign in or
  register first; SSO/QR server paths exist but aren't wired into the UI yet (Slice 1
  uses the live email/password path; wiring SSO is a deferred, non-blocking decision).
- **Handles are permanent in the user UI** — no self-service rename. Charset by
  convention: lowercase alphanumeric + `_`, 3–30 chars, reserved-word blocklist. The
  server is authoritative on normalization, uniqueness and reservation.
- **The `uuid` is canonical, not the handle.** Follows, mentions and content
  attribution store the immutable `uuid` and re-render the current handle at read time,
  so identity survives any operator-level handle change and can never be silently
  hijacked by handle reuse.
- **Deleted handles are tombstoned forever.** GDPR erasure deletes the profile PII but
  keeps the handle string as a non-PII reservation, so old `@mentions`/links can't be
  reassigned to a stranger. The `handles` table uses `handle` as its primary key, so
  reissue is structurally impossible; reserved words are pre-seeded rows.
- **Operators retain carve-outs.** Trust & Safety can forcibly reclaim/reassign a
  handle (impersonation, trademark, slur, legal order) and grant a one-off safety
  rename via support. Immutable to the user, remediable by the operator.
- **Profile lives in a dedicated identity service** (REST-ish paths, protobuf bodies,
  `Bearer` + App Attest on writes), not in the settings-sync blob. New proto messages
  are top-level (numbered from 1), so protoc regeneration needs no hand-edits.
- **The device-local Share Profile becomes a one-time seed.** On Join its display name
  and photo are offered as candidate content (name moderation-checked, avatar scanned);
  afterward the server is source of truth and the local storage/editor is deprecated.
