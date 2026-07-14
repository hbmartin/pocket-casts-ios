# App Attest — First-Party Request Authentication

**Status:** contract specified, pathfinder implementation in progress · **Decision:** ADR-0003

Fork-owned anonymous endpoints authenticate the *app*, not the user, via
[DeviceCheck App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity).
This document is the wire contract between the iOS client and the fork backend. It is
written so any future endpoint can adopt attestation by reference to this document alone.

Consumers in this pass: `transcripts/contribute`, `transcripts/sighting`
(see `docs/TranscriptContributions.md`), and the shake-feedback endpoint (retrofit,
dual-accept rollout).

---

## 1. Client lifecycle

1. **Key generation** (once per install): `DCAppAttestService.generateKey()` →
   opaque `keyId` (base64 SHA-256 of the public key). Stored via `KeychainHelper`
   with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — the key must NOT
   migrate via backup (a restored device re-enrolls; the old keyId simply goes
   dormant server-side).
2. **Enrollment** (once per key):
   - `GET /attest/challenge` → `{ challenge: base64 }` (single-use, 5 min TTL).
   - `attestKey(keyId, clientDataHash: SHA256(challenge))` → attestation object.
   - `POST /attest/enroll` `{ key_id, attestation: base64(CBOR), challenge }`.
   - Server verifies (§2) and persists the key record. 200 → enrolled; 4xx → the
     client discards the key and retries enrollment from scratch at the next need
     (bounded: ≤1 attempt per app session).
3. **Per-request assertion**: for each attested request the client computes
   `clientDataHash = SHA256(request body bytes)` and calls
   `generateAssertion(keyId, clientDataHash:)`. The assertion travels in headers:

   ```
   X-Attest-Key-Id:    <keyId>
   X-Attest-Assertion: <base64(CBOR assertion)>
   ```

   The body itself is the signed payload — no separate nonce round-trip. This
   means attested endpoints MUST treat the raw body bytes as immutable
   (no proxy re-encoding) and MUST reject bodies over the size caps (§4) before
   signature work.
4. **Authenticated requests**: `Authorization: Bearer <access token>` MAY
   accompany the assertion headers. Attestation and account auth are independent
   layers; both are verified when present.
5. **Failure handling**:
   - `401 {"errorMessageId":"invalid_attestation"}` is reserved for an
     unknown/revoked key or invalid signature/RP ID → client re-enrolls once (the
     key may be unknown after server data loss), then parks the owning queue with
     exponential backoff.
   - `409 {"errorMessageId":"stale_attestation"}` means a valid assertion's
     counter arrived after a newer one → client retries with a fresh assertion
     and **does not discard the healthy key**. Neither path is user-visible.

### Simulator / dev builds

`DCAppAttestService.isSupported == false` on Simulator (and attestation is
unavailable in some dev contexts). Such builds send requests **without**
assertion headers. Acceptance is a *server-environment* policy, never a client
secret: the staging backend accepts unattested requests (logged); production
rejects them once enforcement is `required` (§3). There is no bypass header —
a header would be forgeable from any client.

---

## 2. Server verification (backend team)

### 2.1 Enrollment — verifying the attestation object

Apple's documented sequence (implement exactly; libraries exist for most stacks):

1. Decode CBOR; verify the `x5c` certificate chain up to the **Apple App Attest
   root CA** (pin the root; fetch/refresh per Apple's publication).
2. Verify the nonce: `SHA256(authenticatorData ‖ clientDataHash)` must equal the
   `1.2.840.113635.100.8.2` extension value in the credential certificate, where
   `clientDataHash = SHA256(challenge)` for the challenge this server issued
   (single-use — burn it on first presentation, expire at 5 min).
3. `keyId` must equal base64(SHA-256(public key)) of the attested key.
4. `authenticatorData`: RP ID hash == SHA256(App ID `TEAMID.au.com.shiftyjelly.podcasts`
   — parameterize; this fork's personal-team App ID differs per install source),
   counter == 0, `aaguid` == `appattest` (production) or `appattestdevelop`.
   **TestFlight builds attest in the production environment** — do not gate on
   `appattestdevelop` outside true dev builds.
5. Persist the key record:
   `key_id (PK), public_key, counter (0), receipt, environment,
   created_at, last_used_at, status (active|revoked)`.
6. (Optional, later) Post the receipt to Apple's server API for fraud-metric
   refresh; not required for v1.

### 2.2 Per-request — verifying an assertion

1. Look up `key_id`; unknown/revoked → `401 invalid_attestation`.
2. Decode CBOR `{signature, authenticatorData}`. Verify
   `signature` over `authenticatorData ‖ SHA256(request body)` with the enrolled
   public key (ES256).
3. RP ID hash matches; then perform the counter check and update **atomically**.
   One acceptable SQL shape is
   `UPDATE attest_keys SET counter = :new, last_used_at = :now WHERE key_id = :id AND status = 'active' AND counter < :new`.
   Accept only when exactly one row changed. This compare-and-update must not be
   split into a read followed by a write: concurrent counters 1 and 2 arriving
   in reverse order must leave 2 stored, never roll the record back to 1.
4. When the conditional update changes no row, distinguish the cause: an
   unknown/revoked key is `401 invalid_attestation`; an otherwise valid counter
   at or below the stored value is `409 stale_attestation`. Increment the replay
   metric for the latter, but do not tell the client to replace its key merely
   because concurrent network requests arrived out of order. Revoke only under
   a separately documented abuse threshold.

Replay defense = body binding + counter monotonicity; no separate `jti` cache is
needed at contribution volumes. If an endpoint later needs idempotent retries of
an *identical* body, the client re-asserts (fresh counter) rather than resending
the old assertion.

### 2.3 Enforcement modes (per endpoint, server-flagged)

`off → log-only → required`. Rollout: enroll+assert client-side from day one;
each endpoint flips to `required` after log-only telemetry shows the assertion
success rate matches expectations. The feedback endpoint ships in `log-only`
(existing shipped clients send no assertions) and flips only when the installed
base has adopted; the transcript endpoints are new and can go `required`
immediately after staging verification.

---

## 3. Attribution rule (contributions)

Per product decision (ADR-0002/0003): each stored submission is attributed to
**the account user ID when `Authorization: Bearer` is present and valid**,
otherwise to **the App Attest `key_id`**. Exactly one of the two is stored per
row. The key_id is a stable per-install pseudonymous identity — treat it with
credential-grade access controls.

---

## 4. Backend task list

### 4.1 Mandatory input limits

Apply these limits to raw wire bytes **before** JSON/protobuf/gzip/base64/CBOR
decoding or cryptographic verification. Return `413 Payload Too Large` for body
violations and `431 Request Header Fields Too Large` for assertion-header
violations; neither response is an attestation rejection.

| Input | Maximum |
|---|---:|
| `GET /attest/challenge` response body | 4 KiB |
| `POST /attest/enroll` JSON body | 64 KiB |
| decoded enrollment attestation CBOR | 32 KiB |
| `key_id` value, in JSON or `X-Attest-Key-Id` | 256 ASCII bytes |
| `X-Attest-Assertion` base64 value | 16 KiB |
| decoded per-request assertion CBOR | 12 KiB |
| `POST transcripts/contribute` compressed body | 3 MiB |
| `POST transcripts/sighting` compressed body | 64 KiB |
| support-feedback protobuf body | 1 MiB |

Reject invalid base64 without allocating from attacker-controlled decoded-length
claims. Endpoint-specific decoded-content limits still apply after attestation
(for example, the VTT/fingerprint caps in `docs/TranscriptContributions.md` §4).

1. Challenge endpoint (`GET /attest/challenge`): CSPRNG 32-byte challenge,
   single-use store (TTL 5 min).
2. Enrollment endpoint (`POST /attest/enroll`) implementing §2.1; key store
   schema above.
3. Assertion-verification middleware implementing §2.2, mountable per endpoint
   with the §2.3 mode flag.
4. Error envelopes: `401 {"errorMessageId":"invalid_attestation"}` only for
   invalid/revoked key material; `409 {"errorMessageId":"stale_attestation"}`
   for an otherwise valid non-increasing counter. Use `5xx` for verifier-internal
   faults (never `401`, or the client will discard a healthy key).
5. Metrics: enrollments/day, assertion verify failures by cause (unknown key,
   bad signature, counter regression), unattested-request rate per endpoint
   (drives the log-only→required flip), per-key submission rate (abuse).
6. Ops: pin/refresh the Apple root CA; document key-revocation runbook
   (set `status=revoked`; client self-heals by re-enrolling).
7. Staging policy: accept unattested requests with a `dev_unattested` log tag;
   production: per-endpoint mode flag only.

Sequencing constraint: the client ships **always-on with no feature flag** —
challenge/enroll/verify (§§2.1–2.2) and the transcript endpoints must be live in
production before the client build ships. The feedback retrofit has no such
constraint (log-only dual-accept).
