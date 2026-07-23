# API Auth Hardening Plan

Remediation plan for the three highest-ranked findings from the API-security best-practices review
(branch `claude/api-security-best-practices-p3jw69`):

1. **Stored plaintext password as a permanent replayable credential** (`ServerSettings.swift:176`,
   `TokenHelper.swift:147-193`).
2. **Static shared secret + unkeyed SHA-1 as the only "request signature"**
   (`SharingServerHandler.swift:127`, `ApiCredentials.sharingServerSecret`).
3. **Bearer tokens with no lifetime handling and no sender constraint**, including the
   empty-refresh-token clobber bug (`TokenHelper.swift:106`).

This is a *plan*, not an implementation. Client changes land in this repo; server changes land in
`pocketcasts-api` (the protobuf source of truth — regenerate the client stubs afterwards with
`mise run generate:proto`). Each workstream states its server contract precisely so the API team
can build against it, and lists every client touch point by file/line as of this writing.

> Companion reference: `docs/ServerAPISurface.md` (surface map). Field numbers below were verified against
> `Modules/Sources/PocketCastsServer/Private/Protobuffer/api.pb.swift`.

---

## Contents

1. [Workstream overview & sequencing](#1-workstream-overview--sequencing)
2. [Workstream A — Remove the stored account password](#2-workstream-a--remove-the-stored-account-password)
3. [Workstream B — Retire the static SHA-1 sharing secret](#3-workstream-b--retire-the-static-sha-1-sharing-secret)
4. [Workstream C — Token lifetime handling & sender-constrained tokens (DPoP)](#4-workstream-c--token-lifetime-handling--sender-constrained-tokens-dpop)
5. [Testing & verification](#5-testing--verification)
6. [Guardrails (Semgrep) to add as work lands](#6-guardrails-semgrep-to-add-as-work-lands)
7. [Risks, open questions, explicit non-goals](#7-risks-open-questions-explicit-non-goals)

---

## 1. Workstream overview & sequencing

| #    | Workstream                                                   | Server dependency                                            | Client-only start possible?     | Risk if skipped                                              |
| ---- | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------- | ------------------------------------------------------------ |
| C.0  | Quick client fixes: empty-refresh-token guard, `expires_in` handling, single-flight token acquisition | None                                                         | **Yes — ship first**            | SSO users logged out by a lossy refresh; avoidable 401 round-trips |
| A    | Refresh tokens for password accounts; delete stored password | **Yes** — `user/login`/`user/register` must issue refresh tokens; new revoke endpoint | Migration scaffolding only      | Account credential sits in Keychain forever, restorable from backup |
| B    | Sharing endpoint moves to bearer auth; static secret removed from binary | **Yes** — sharing service must accept access tokens; dual-accept window | Client can ship dual-mode early | Extractable secret keeps shipping in every IPA               |
| C.1  | DPoP sender-constraining (per-install Secure Enclave key)    | **Yes** — token binding + proof validation + replay cache    | Key-generation scaffolding only | Stolen bearer/refresh tokens replayable from any machine     |

Recommended order: **C.0 → A → B → C.1**. C.0 is prerequisite plumbing for A (single-flight refresh
is required before rotation is safe). B is independent of A/C and can run in parallel with A — it
touches a different service (`sharing.pocketcasts.com`) and different client files. C.1 builds on
A's token model and should not start client-side until A's server contract is final, because the
binding happens at the same endpoints.

Milestones:

- **M0** — C.0 merged (client-only; no server coordination).
- **M1** — Server: `user/login`/`user/register` return refresh tokens on staging (`api.pocketcasts.net`); revoke endpoint live.
- **M2** — Client A merged behind `FeatureFlag.refreshTokenForPasswordAuth`; migration verified on staging; flag enabled in production release; password deletion confirmed via telemetry.
- **M3** — Sharing dual-accept live server-side; client B merged; legacy `h` signature disabled server-side after adoption threshold; secret removed from credentials pipeline and rotated dead.
- **M4** — DPoP phases 1–3 (see §4.3) rolled out endpoint-by-endpoint.

---

## 2. Workstream A — Remove the stored account password

### 2.1 Problem statement

For email/password accounts the server's `user/login` response carries only an access token
(`Api_UserLoginResponse`: `1 token, 2 uuid, 3 email` — no refresh token, no expiry). The client
therefore persists the **plaintext password** in the Keychain and replays it to `user/login`
whenever the access token dies:

- Persisted at `ServerSettings.saveSyncingPassword` (`Modules/Sources/PocketCastsServer/Public/ServerSettings.swift:176-178`)
  with `kSecAttrAccessibleAfterFirstUnlock` — **not** `ThisDeviceOnly`, so it migrates via encrypted
  device backups.
- Replayed by `TokenHelper.acquirePasswordToken()` (`Modules/Sources/PocketCastsServer/Private/TokenHelper.swift:147-193`)
  on every 401-triggered re-auth.

The stolen artifact is the account credential itself (likely reused across services), not a
short-lived token. Every downstream mitigation (short TTLs, rotation, sender-constraining) is moot
while this exists. SSO accounts already have the correct shape (`user/token`,
`grant_type="refresh_token"`, rotating refresh token) — this workstream extends that shape to
password accounts and deletes the password from disk.

### 2.2 Target design

- `user/login` and `user/register` become **token-issuing endpoints** returning
  `access_token + refresh_token + expires_in` (password still sent once, interactively, over TLS —
  never persisted).
- All subsequent re-auth for password accounts uses the **existing** refresh grant
  (`user/token`, `grant_type="refresh_token"`) — the client code path already exists
  (`ApiServerHandler+SocialAuth.swift:42-52`); it just becomes the only path.
- Sign-out revokes the refresh token **server-side** (new endpoint; today
  `SyncManager.signout()` only wipes the Keychain — `SyncManager.swift:53-59`).
- The `SJSyncingPwd` Keychain item is deleted on migration and never written again.

### 2.3 Server changes (pocketcasts-api)

#### 2.3.1 Protobuf additions (backward-compatible, additive only)

`Api_UserLoginResponse` (current fields 1–3; verified in `api.pb.swift:18055-18058`):

```proto
message UserLoginResponse {
  string token         = 1;   // existing: access token (kept for old clients)
  string uuid          = 2;   // existing
  string email         = 3;   // existing
  string refresh_token = 4;   // NEW: opaque, rotating
  int32  expires_in    = 5;   // NEW: access-token TTL, seconds
  string token_type    = 6;   // NEW: "Bearer" (future: "DPoP", see §4)
}
```

`Api_RegisterResponse` (current fields: `1 success, 2 message, 3 token, 4 uuid, 5 errors` — a
`token` field already exists; verified in `api.pb.swift:13846-13848`):

```proto
message RegisterResponse {
  google.protobuf.BoolValue success = 1;  // existing
  string message       = 2;               // existing
  string token         = 3;               // existing: access token
  string uuid          = 4;               // existing
  repeated string errors = 5;             // existing
  string refresh_token = 6;               // NEW
  int32  expires_in    = 7;               // NEW
  string token_type    = 8;               // NEW
}
```

Old clients ignore unknown fields, so both changes are wire-compatible. The iOS client detects
server capability by `!refresh_token.isEmpty` (see §2.4.3 migration).

*Alternative considered:* add a `password` grant to `user/token`
(`Api_UserTokenRequest` gains `6 email, 7 password`; response is already
`Api_TokenLoginResponse{1 email, 2 uuid, 3 is_new, 4 access_token, 5 token_type, 6 expires_in, 7 refresh_token}`).
This unifies all token issuance on one endpoint and is the better long-term shape, but it forces
new client login UI onto a new endpoint while `user/login` must be kept alive for old clients
anyway. Recommendation: **extend `user/login`/`user/register` now** (smallest coordinated change);
optionally introduce the `password` grant later and deprecate `user/login` on the API's own
schedule. Android and web consume the same endpoints — the additive change is safe for them and
gives them the same migration opportunity.

#### 2.3.2 Refresh-token issuance & storage semantics

The server presumably already stores refresh tokens for SSO/device-grant accounts; the same store
is reused. Required properties (per RFC 9700 §§2.2, 4.14 for public clients):

- **Format**: ≥256-bit CSPRNG opaque string. Store only a SHA-256 **hash** of the token; never the
  raw value. Constant-time comparison on lookup.
- **Record shape** (per token):
  `id, user_id, family_id, generation, token_hash, scope ("mobile"|"tv"|"sonos"), created_at,
  last_used_at, absolute_expires_at, idle_expires_at, status (active|rotated|revoked),
  successor_id, client_metadata (user-agent, app version), revoked_reason`.
- **Lifetimes** (initial proposal; tune with product): access token `expires_in` ≤ 24 h for scope
  `mobile`; refresh token absolute lifetime 12 months, idle timeout 90 days (refreshing extends
  idle, never absolute).
- **Rotation**: every successful `grant_type="refresh_token"` call marks the presented token
  `rotated`, issues a successor in the same `family_id` with `generation + 1`, and returns the new
  pair. The response **must always include a non-empty `refresh_token`** — the iOS client persists
  whatever comes back (`TokenHelper.swift:104-107`), and older clients in the field would clobber
  their stored token with `""` if the field were ever omitted (bug C.0-1 fixes the client side, but
  the server must hold this invariant for the installed base).
- **Idempotent rotation grace window** (critical for this client): the iOS app has no single-flight
  guard today — every `ApiBaseTask` constructs its own `TokenHelper` (`ApiBaseTask.swift:18`), so
  concurrent operations can present the same refresh token near-simultaneously, and the 401-retry
  path re-presents after network timeouts. For **60–120 s** after rotation, presenting the
  *predecessor* token again must return **the same successor pair** (not a new family, not a reuse
  alarm). Only presentation outside the grace window counts as reuse.
- **Reuse detection**: presenting a `rotated` token outside grace, or any `revoked` token, revokes
  the **entire family**, logs a security event with client metadata, and returns the same error the
  client already maps to forced sign-out (see 2.3.5).
- **Revocation triggers**: password change (`user/change_password`) and password reset
  (`user/forgot_password` completion) revoke **all** of the user's refresh-token families;
  `user/delete_account` likewise; explicit revoke endpoint (next section) revokes one family.

#### 2.3.3 New endpoint: `POST user/token/revoke`

RFC 7009-shaped, protobuf body, Bearer-authenticated (the access token authenticates the call; the
body names the refresh token to kill):

```proto
message TokenRevokeRequest {
  string refresh_token = 1;   // the token whose family should be revoked
}
// Response: Api_EmptyResponse (exists). Per RFC 7009, return 200 even for unknown tokens.
```

Client calls this from `SyncManager.signout()` best-effort (fire-and-forget with short timeout —
sign-out must not block on network). Without this, a backup-restored or exfiltrated refresh token
outlives the user's sign-out forever.

#### 2.3.4 Credential-endpoint abuse controls

`user/login`, `user/register`, `user/forgot_password`, and `user/token` are unauthenticated
bootstrap endpoints and become *more* attractive once they mint refresh tokens:

- Per-account and per-IP rate limits with exponential backoff on `user/login` failures
  (the client already maps `ACCOUNT_LOCKED` — `ErrorResponse.swift`).
- Per-account cap on **active refresh-token families** (e.g. 20) with LRU eviction, so a
  compromised password can't mint unbounded long-lived sessions.
- Structured audit log per token event: `issued | rotated | reuse_detected | revoked | expired`,
  keyed by user, family, client metadata. Alert on reuse-detection spikes.
- Telemetry to watch during rollout: rate of password-`user/login` calls per account per day. Today
  every token expiry causes one; after migration it should drop to ~interactive logins only. A
  *sustained* high per-account rate after M2 identifies stragglers or abuse.

#### 2.3.5 Error contract (unchanged, but now load-bearing)

The client maps HTTP 400/401 on token acquisition to `APIError.TOKEN_DEAUTH` and 403 to
`PERMISSION_DENIED`, and only those trigger sign-out (`ApiServerHandler.swift:195-205`,
`TokenHelper.swift:113-119`). The server must return:

- `400/401` + JSON error envelope for: invalid/expired/revoked refresh token, family reuse
  detection. (Forces clean re-login.)
- `5xx`/network errors for transient faults. (Client deliberately does **not** log out on these —
  `TokenHelper.swift:116-119`; keep that distinction reliable or a server incident logs out the
  entire install base.)

### 2.4 Client changes (this repo)

Gate everything behind a new `FeatureFlag.refreshTokenForPasswordAuth` (pattern:
`Modules/Sources/PocketCastsUtils/Feature Flags/FeatureFlag.swift`), default off until M1 is
verified on staging.

#### 2.4.1 Token acquisition (`Modules/Sources/PocketCastsServer`)

- `AuthenticationResponse` (`Public/Models/AuthenticationResponse.swift`): map the new
  `refreshToken`/`expiresIn`/`tokenType` fields from `Api_UserLoginResponse` and
  `Api_RegisterResponse` (today the `Api_UserLoginResponse` initializer hardcodes
  `refreshToken = nil` at line 14).
- `TokenHelper.asyncAcquireToken` (`Private/TokenHelper.swift:198-217`): invert the priority —
  try the **refresh grant first** whenever `ServerSettings.refreshToken()` is non-nil, regardless
  of account type. `acquirePasswordToken()` is deleted once migration completes; during the
  migration window it survives only as the one-shot upgrade path (§2.4.3).
- **Single-flight acquisition** (prerequisite, part of C.0): make token refresh go through one
  shared serializing point (e.g. `TokenHelper.shared` actor or an `NSLock`-guarded in-flight task
  that concurrent callers await) so only one refresh grant is ever in flight. Also stop
  constructing a fresh `TokenHelper` per `ApiBaseTask` (`ApiBaseTask.swift:18`).
- `tokenCleanUp()` (`TokenHelper.swift:227-256`): drop the password checks; the "can this account
  recover?" test becomes *has refresh token* only.

#### 2.4.2 Password write/read sites to change

Writes to remove (replaced by persisting the refresh token that the same response now carries):

| Site                                                   | Today                                | After                                                        |
| ------------------------------------------------------ | ------------------------------------ | ------------------------------------------------------------ |
| `podcasts/AuthenticationHelper.swift:32`               | saves password after `validateLogin` | persist `response.refreshToken` (already done at `:56` via `handleSuccessfulSignIn`) |
| `podcasts/Syncing/SyncSigninViewController.swift:326`  | saves password                       | remove; keep email save                                      |
| `podcasts/Syncing/SyncSigninView.swift:309`            | saves password                       | remove                                                       |
| `podcasts/NewEmailViewController.swift:237` (register) | saves password                       | persist token pair from `Api_RegisterResponse`               |
| `podcasts/ChangePasswordViewController.swift:215`      | saves the **new** password           | server revokes all families on change; client immediately re-authenticates via `user/login` with the new password **held in memory only**, persists the fresh token pair |

Reads to replace:

| Site                                                         | Today                                                        | After                                                        |
| ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ |
| `TokenHelper.swift:148`                                      | replay password → `user/login`                               | refresh grant (§2.4.1)                                       |
| `podcasts/AuthenticationHelper.swift:10` (`refreshLogin`)    | password-first re-auth (no in-tree callers today — verify and delete if dead) | refresh grant or delete                                      |
| `podcasts/AppDelegate+Analytics.swift:82` (`retrieveUserIdIfNeeded`) | re-login with stored password to fetch userId                | Bearer-authenticated user-id fetch (`Api_UserIdResponse` already exists in the schema — confirm path in pocketcasts-api, e.g. `user/id`); or defer to next interactive login |
| `podcasts/Syncing/SyncSigninViewController.swift:128`, `SyncSigninView.swift:227` (`loginAgain` auto-fill) | auto-signs-in with stored creds                              | prefill email only; user types password                      |
| `podcasts/AccountViewController.swift:13` (`isUsernamePasswordLogin`) | infers auth method from password presence                    | persist a non-secret auth-method marker at sign-in (e.g. `UserDefaults` `"SJAccountAuthMethod" = "password" \| "sso"`) and branch on that |

#### 2.4.3 Migration of existing installs

On first token need after update (inside the single-flight acquire), when the flag is on:

1. If `SJRefreshToken` exists → refresh grant (nothing to migrate).
2. Else if `SJSyncingPwd` exists → **one final** `user/login` with the stored credentials.
   - Response contains non-empty `refresh_token` (server ≥ M1): persist the pair, then
     **delete `SJSyncingPwd` from the Keychain**, log `FileLog` migration marker, set auth-method marker.
   - Response lacks `refresh_token` (server not yet deployed / rollback): keep current behavior;
     retry migration on a later acquire. This makes the client release safe to ship before the
     server flips, and tolerant of server rollback.
3. Else → not signed in.

Sign-out (`SyncManager.signout()` / `clearTokensFromKeyChain()`, `SyncManager.swift:53-59`): add
the best-effort `user/token/revoke` call before wiping; keep wiping `SJSyncingPwd` forever (cleans
up stragglers).

#### 2.4.4 Keychain policy hardening (rides along)

When A lands, tighten accessibility for the credential items in `ServerSettings.swift`:

- `SJRefreshToken` and `SJSyncV2Token`: `kSecAttrAccessibleAfterFirstUnlock` →
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (matching the push token, `:230`).
  Consequence (intentional): sessions no longer restore onto a different device from backup — the
  user signs in again. Rewrite items in place on first access post-update (`KeychainHelper.save`
  already updates `kSecAttrAccessible` on `SecItemUpdate`).
- Keep `AfterFirstUnlock` (not `WhenUnlocked`) because background refresh/sync legitimately runs
  while locked (`BackgroundSyncManager.swift:56` reads the token in a background session).
- Email stays as-is (needed for prefill/display; PII but not a credential).

---

## 3. Workstream B — Retire the static SHA-1 sharing secret

### 3.1 Problem statement

Creating a shared podcast list — `POST sharing.pocketcasts.com/share/list` — is "authenticated" by
`h = SHA1(datetime + secret)` where `secret` is `ApiCredentials.sharingServerSecret`, a static
value generated into every binary (`AppDelegate.swift:379` →
`ServerCredentials.configureSharing`, `ServerCredentials.swift:8-20`) and hashed in
`SharingServerHandler.legacySharingServerSignature` (`SharingServerHandler.swift:127-136`). This is
the textbook "hardcoded shared secret in the binary" anti-pattern: extractable from any IPA,
unkeyed SHA-1 rather than a MAC, and the canonical input covers only a timestamp — not method,
path, or body. It provides zero legitimacy value while being a shipping liability.

### 3.2 Target design

**Fold share-list creation under the normal per-user Bearer auth** and delete the secret from the
credential pipeline entirely. Rationale: accounts are free in this fork, list creation is a
write/abuse surface (spam lists on a first-party domain), and attributing lists to a `user_id`
gives the server a real abuse handle (rate limits, takedowns) that no embedded secret can.

Product decision required up front: **signed-out users lose "share this list of podcasts"** (or the
share sheet routes them through sign-in). If anonymous creation must remain, the honest fallback is
*no signature at all* plus aggressive server-side rate limiting by IP/device — an extractable
secret adds nothing — with App Attest gating as the eventual anonymous-abuse answer (out of scope
here; see the parent review).

### 3.3 Server changes (sharing service)

1. **Accept Bearer tokens** on `POST /share/list`. The sharing service must validate Pocket Casts
   access tokens. Two options, pick based on current token format (opaque vs JWT — confirm in
   pocketcasts-api):
   - *Opaque tokens*: add an internal introspection endpoint on the api service
     (RFC 7662-shaped: token in → `{active, user_id, scope, exp}` out), called by the sharing
     service with an internal service credential; cache positive results ≤ 60 s.
   - *JWT access tokens*: publish a JWKS; the sharing service validates signature + `exp` + `scope`
     locally. (Cleaner; also what DPoP in §4 wants. If tokens are opaque today this is a larger
     api-service change — flag as a joint decision.)
2. **Dual-accept window**: requests carrying a valid `Authorization: Bearer` are authorized by it;
   requests carrying only the legacy `datetime`/`h` pair continue to work. Instrument both paths
   with client `User-Agent`/app-version so adoption is measurable.
3. **Abuse controls on the new path**: per-user quota (e.g. 20 lists/day), body size cap, max
   podcasts per list, and `user_id` stored on each created list for takedown/attribution.
   Return 429 + `Retry-After` on quota (client-side 429 handling is a C.0 nicety — today the API
   layer has none).
4. **Sunset**: once legacy traffic is < agreed threshold and the fleet's minimum supported app
   version carries the new path, reject legacy-signature requests (400 with a JSON
   `errorMessageId` the client surfaces as a generic share failure), then **rotate the old secret
   dead** server-side. The secret must be treated as public from the moment sunset planning starts
   — every historical IPA contains it.
5. `loadList` (fetch) stays unauthenticated — public shared content — but see the parent review's
   transport findings for the related cleartext-URL fix (`AppDelegate+UrlHandling.swift:159`),
   which should ride along with this workstream's client PR.

### 3.4 Client changes (this repo)

- `SharingServerHandler.sharePodcastList` (`SharingServerHandler.swift:84-87` region): route the
  request through `TokenHelper.callSecureUrl` so it carries `Authorization: Bearer`; stop
  attaching `datetime`/`h`. Gate on `FeatureFlag.sharingListBearerAuth` until the server
  dual-accept is live; if the user is signed out, surface the sign-in prompt (product decision
  above).
- Delete `legacySharingServerSignature` (`SharingServerHandler.swift:127-136`) and its unit-test
  fixture (`semgrep/tests/swift-security-crypto.swift:27`), removing the repo's only
  `Insecure.SHA1` suppression.
- Delete `ServerCredentials` (`Modules/Sources/PocketCastsServer/Public/ServerCredentials.swift`)
  and the configure call (`podcasts/AppDelegate.swift:379`).
- Credentials pipeline: remove `sharingServerSecret` from `podcasts/Credentials/ApiCredentials.tpl`,
  `scripts/generate-placeholder-credentials.sh`, the required-keys list in
  `scripts/ci/prepare-credentials.sh:19-25` (`sharing_server_secret`), the test
  `scripts/tests/generate_credentials_test.rb`, and the encrypted blob
  `.configure-files/pocket_casts_credentials.json.enc` (regenerate without the key).
- Semgrep: retire `pocketcasts.servercredentials-use-configure-sharing`
  (`semgrep/swift-security.yml:474-489`) and its fixture; add a replacement rule forbidding
  reintroduction (§6).

---

## 4. Workstream C — Token lifetime handling & sender-constrained tokens (DPoP)

### 4.1 C.0 — Immediate client-only fixes (no server dependency)

1. **Empty-refresh-token clobber guard.** `TokenHelper.acquireToken` persists whatever the refresh
   response contained (`TokenHelper.swift:104-107`); `Api_TokenLoginResponse.refreshToken` is a
   non-optional proto string defaulting to `""`, so a server response that omits the field would
   overwrite the stored SSO refresh token with an empty string via
   `ServerSettings.setRefreshToken` (`ServerSettings.swift:308-310`) — silently bricking future
   refreshes. Fix: only persist when non-empty; keep the previous token otherwise. Same guard in
   `AuthenticationHelper.handleSuccessfulSignIn` (`podcasts/AuthenticationHelper.swift:56`), which
   also duplicates the `:43` write — collapse to one guarded write. Unit-test both.
2. **Honor `expires_in`.** `AuthenticationResponse` drops `expiresIn`/`tokenType` today
   (`AuthenticationResponse.swift:18-24`). Map them; persist a computed
   `token_expiry_date = now + expiresIn − skew` (UserDefaults, non-secret; suggested skew 5 min).
   `TokenHelper`/`ApiBaseTask` treat a past-expiry stored token as absent and refresh proactively
   instead of burning a request to get the 401 (`ApiBaseTask.swift:36-43`,
   `TokenHelper.swift:48-60`). Keep the 401 path as fallback — expiry is a hint, the server is the
   authority. Password-login responses gain `expires_in` only after Workstream A; absent field ⇒
   behave as today.
3. **Single-flight token acquisition** — specified in §2.4.1; belongs to C.0 because it is pure
   client hygiene and must precede A's rotation.
4. **(Nicety) 429 handling in the API layer**: `ApiBaseTask`/`TokenHelper` currently branch only on
   401; add `Retry-After`-aware backoff for 429 so the abuse controls added in A/B degrade
   gracefully in the client.

### 4.2 Why DPoP (decision record)

The best-practices doc offers DPoP (RFC 9449), mTLS (RFC 8705), or HTTP Message Signatures
(RFC 9421). For a consumer app with no MDM story, mTLS is out. Between DPoP and RFC 9421: the API
already speaks OAuth-shaped grants at `user/token`, tokens are the thing worth constraining, and
DPoP's per-request proof is a self-contained header that needs no canonicalization of the protobuf
bodies (proofs sign method + URI + token hash, not the body). Choose **DPoP with ES256 keys held
in the Secure Enclave**. Body-covering signatures (RFC 9421 with `Content-Digest`) remain a future
option for specific endpoints if tamper-proofing of payloads is ever required; nothing below
precludes it.

### 4.3 Phased rollout

**Phase 1 — client key material (client-only scaffolding).**
Generate a per-install P-256 signing key at first sign-in: `SecureEnclave.P256.Signing.PrivateKey`
(CryptoKit), access control `.privateKeyUsage` **without** user-presence (background refresh must
sign while locked), encrypted key blob persisted via the existing `KeychainHelper` with
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. No Secure Enclave fallback is needed for any
device that runs current iOS, but code defensively: if SE is unavailable (some Macs-as-iPad hosts,
simulators), fall back to a software CryptoKit key stored ThisDeviceOnly and report the difference
in the proof header's JWK (server can risk-score it). New module-level type suggested:
`Modules/Sources/PocketCastsServer/Private/RequestSigner.swift`. There are currently **no**
app-generated asymmetric keys anywhere in the codebase — this is new infrastructure; keep it
self-contained.

**Phase 2 — bind tokens at issuance (server + client).**
Client sends a `DPoP` header (RFC 9449 proof JWT: header `{typ:"dpop+jwt", alg:"ES256", jwk}`,
claims `{htm, htu, iat, jti}`) on `user/login`, `user/register`, and `user/token`. Server:

- Computes the JWK thumbprint `jkt` (RFC 7638, SHA-256) from the proof and stores it on the
  refresh-token **family** record (§2.3.2) and on the access-token record (opaque tokens: a
  server-side `jkt` column; JWT tokens: embed `cnf: {"jkt": ...}`).
- On `grant_type="refresh_token"`: require a proof signed by the **same** key as the family's
  `jkt`; mismatch ⇒ `401 invalid_dpop_proof` and a security log event (a stolen refresh token
  presented without the device key is exactly the theft this detects). A backup restored to a new
  device loses the SE key ⇒ refresh fails ⇒ clean re-login — this, combined with §2.4.4, closes
  the "session survives backup exfiltration" hole completely.
- Tokens issued to proof-carrying clients get `token_type = "DPoP"`; old clients keep `"Bearer"`
  and unbound tokens. Dual-accept is inherent — binding is per-token, not per-endpoint.

**Phase 3 — require proofs on high-value resource endpoints (server + client).**
Client attaches `DPoP` proofs (adding `ath` = base64url(SHA-256(access token)) per RFC 9449 §4.3)
on: `user/change_email`, `user/change_password`, `user/delete_account`, `user/token/revoke`,
`user/exchange_sonos`, and file-upload presign. Server middleware validation order:

1. Parse proof JWT; verify ES256 signature with the **embedded** JWK.
2. `typ == "dpop+jwt"`; `htm` matches the HTTP method; `htu` matches the canonical request URI
   (scheme+host+path, no query/fragment).
3. `iat` within ±300 s (start permissive; tighten with telemetry).
4. `jti` unseen — replay cache (Redis `SETNX` with TTL = 2× skew window). Key by `jti` alone;
   memory is bounded by TTL.
5. `ath` matches the presented access token.
6. Proof key thumbprint == the token's bound `jkt`.
7. On failure: `401` + JSON envelope `{"errorMessageId": "invalid_dpop_proof"}` (flows through the
   existing client error path, `ApiServerHandler.extractErrorResponse`). Support
   `use_dpop_nonce` + `DPoP-Nonce` header later only if replay telemetry justifies the extra
   round-trip; the client retry hook is cheap to add then.

Enforcement per endpoint is flag-controlled server-side: `off → log-only (shadow-validate) →
required for tokens with a bound jkt → required for all tokens newer than version X`. Unbound
tokens from old app versions keep working until the fleet threshold is met; never hard-cut.

**Explicitly deferred** (tracked in the parent review, not this plan): App Attest at key
registration (would attest the Phase-1 key), DeviceCheck abuse bits, anonymous-endpoint
(refresh/search/OPML) protection.

### 4.4 Server infrastructure summary for C

| Component       | Requirement                                                  |
| --------------- | ------------------------------------------------------------ |
| Token store     | `jkt` column on access-token + refresh-family records (§2.3.2 schema) |
| Proof validator | Shared middleware (api service + any service that later requires proofs); ES256, RFC 7638 thumbprints |
| Replay cache    | Redis/equivalent, `jti` TTL ~10 min, sized for proof-carrying request volume on Phase-3 endpoints only |
| Clock skew      | ±300 s initial; export skew-failure metrics before tightening |
| Error surface   | `invalid_dpop_proof` / (later) `use_dpop_nonce` via the JSON error envelope |
| Metrics         | % tokens issued bound; proof failure rate by cause; refresh-with-wrong-key events (theft signal); rotation-reuse events |

---

## 5. Testing & verification

- **Unit (this repo).** `PocketCastsTests/Tests/Utilities/TokenHelperTests.swift` currently seeds a
  stored password (`:34,63,98`) — rewrite around the refresh grant: 401→refresh→retry; refresh
  failure taxonomy (TOKEN_DEAUTH vs transient); empty-refresh-token guard; single-flight (N
  concurrent acquires ⇒ 1 network call); migration state machine of §2.4.3 (password→pair→password
  deleted; server-without-field ⇒ password retained); expiry math incl. skew. New DPoP proof-shape
  tests (header/claims/`ath`) against `RequestSigner` with a software key.
- **Integration (staging, `api.pocketcasts.net` / `sharing.pocketcasts.net`).** Full password
  login → refresh → rotation → reuse-detection → family revocation; password change revokes other
  device's session; sign-out revoke; share-list create via Bearer on dual-accept, then with legacy
  disabled.
- **Migration drill.** Install current release → sign in (password persisted) → upgrade to A build
  → background refresh occurs → assert `SJSyncingPwd` absent from Keychain, refresh token present,
  sync still green. Repeat with server flag off (password must survive untouched).
- **Backup-restore drill (after §2.4.4 / Phase 2).** Restore device backup to second device →
  assert app requires sign-in (ThisDeviceOnly items absent; DPoP key absent ⇒ bound refresh token
  unusable even if exfiltrated from a backup of the keychain).
- **Rollback drills.** Server rolls back after M2: client keeps working via retained refresh
  tokens; interactive re-login still works (login path unchanged). Client flag off: behavior
  byte-identical to today (password path intact until flag flips).

Acceptance criteria per workstream:

- **A**: no code path writes `SJSyncingPwd`; telemetry shows password-`user/login` volume reduced
  to interactive logins; revoke endpoint called on sign-out; Keychain items ThisDeviceOnly.
- **B**: `sharing_server_secret` absent from `.tpl`, scripts, CI required keys, and the encrypted
  credentials blob; `Insecure.SHA1` has zero call sites; legacy signature rejected server-side and
  old secret rotated dead.
- **C**: no stored-token overwrite with `""` possible; proactive refresh observable (401 rate on
  api host drops); Phase 2+: stolen-refresh-token replay from a different key fails in staging
  test.

---

## 6. Guardrails (Semgrep) to add as work lands

Per `CLAUDE.md`, encode each fixed problem class in `semgrep/swift-security.yml`:

| Rule (proposed id)                             | Fires on                                                     | Lands with                                                   |
| ---------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| `pocketcasts.no-persisted-account-password`    | `saveSyncingPassword(...)` call, or any `KeychainHelper.save` with key `SJSyncingPwd` / `syncingLoginItemName` | A (after removal)                                            |
| `pocketcasts.auth-keychain-items-device-only`  | `KeychainHelper.save(... key: <token/refresh keys> ..., accessibility:)` without `ThisDeviceOnly` | A (§2.4.4)                                                   |
| `pocketcasts.no-empty-refresh-token-persist`   | `setRefreshToken($X)` where `$X` is not guarded non-empty (pattern-based approximation; the unit test is the real guard) | C.0                                                          |
| `pocketcasts.no-sharing-shared-secret`         | reintroduction of `ServerCredentials`, `configureSharing`, `legacySharingServerSignature`, or a `sharing_server_secret` key in scripts | B (replaces `servercredentials-use-configure-sharing`, `swift-security.yml:474`) |
| `pocketcasts.dpop-key-requires-secure-enclave` | `P256.Signing.PrivateKey()` (software key) outside the sanctioned fallback path in `RequestSigner` | C.1 Phase 1                                                  |

Existing rule `pocketcasts.no-insecure-cryptokit-hashes` (`swift-security.yml:249`) stays and loses
its last suppression when B deletes the SHA-1 call.

---

## 7. Risks, open questions, explicit non-goals

**Risks**

- *Rotation vs. flaky networks*: without the §2.3.2 grace window, a retried refresh after a
  response-lost timeout triggers false reuse-detection and mass sign-outs. The grace window +
  single-flight client are jointly load-bearing; ship both before enabling reuse-revocation.
- *Server incident ⇒ fleet sign-out*: the 400/401-vs-5xx distinction in §2.3.5 is the only thing
  standing between an api outage and logging out every user. Add a server-side integration test
  that asserts 5xx (never 401) for internal token-store failures.
- *`user/forgot_password` + revocation*: revoking all families on reset is correct but means a
  password-reset user is signed out everywhere including the device in hand; the client's forced
  re-login UX (`loginAgain`, §2.4.2) must prefill email and land gently.
- *B product surface*: signed-out list sharing disappears (or gains a sign-in interstitial) —
  needs explicit product sign-off before the client PR.

**Open questions (for pocketcasts-api owners)**

1. Access-token format today: opaque or JWT? Decides introspection-vs-JWKS in §3.3 and where
   `cnf.jkt` lives in §4.3.
2. Current server-side `expires_in` values per scope, and whether refresh families already exist
   for SSO (assumed yes) — A reuses them rather than inventing a parallel store.
3. Does an authenticated user-id endpoint exist for `retrieveUserIdIfNeeded` (§2.4.2), or should
   the client derive it from the login/refresh response alone?
4. Android/web timelines for adopting the same additive fields (no coupling required, but the
   audit-log noise from password-replay logins won't fully quiet until all platforms migrate).

**Non-goals of this plan** (tracked in the parent review, not this plan): ATS tightening and the
cleartext share-list fetch (transport workstream), App Attest / DeviceCheck adoption,
anonymous-endpoint abuse controls, certificate pinning.

---

*Note (2026-07-12): `docs/ServerBackendSpec.md`, referenced above as a companion document, was
removed by program decision #59 the same day this plan was queued — the protobuf sources in
`Modules/Sources/PocketCastsServer/Private/Protobuffer/` are the wire-format reference.*
