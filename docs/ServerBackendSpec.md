# Pocket Casts — Server Backend Re-implementation Specification

**Status:** Draft v1 · **Audience:** backend engineering team · **Source of truth:** the Pocket Casts iOS client (`Modules/Sources/PocketCastsServer/`)

This document specifies **exactly what a backend must implement** to serve the Pocket Casts iOS
client. It is derived by reverse-engineering the shipping client: every endpoint, wire format,
protobuf field number, status code, and behavioral contract described here is what the app already
sends and expects. A backend that satisfies this document is a drop-in replacement for the
production Pocket Casts services — the app needs **no changes** to talk to it.

> **Companion document:** [`ServerAPISurface.md`](./ServerAPISurface.md) is a security-oriented *map*
> of every remote interaction (including third-party SDKs, CDNs, downloads, and image hosts). This
> document is the *implementation contract* for the first-party services. Read the surface map for
> "what talks to what"; read this for "what to build."

---

## Table of Contents

1. [Scope & non-goals](#1-scope--non-goals)
2. [Service topology & hosts](#2-service-topology--hosts)
3. [Transport & wire conventions](#3-transport--wire-conventions)
4. [Authentication & token model](#4-authentication--token-model)
5. [Error model & status codes](#5-error-model--status-codes)
6. [Common headers & localization](#6-common-headers--localization)
7. [Data model glossary](#7-data-model-glossary)
8. [Authentication & Account service](#8-authentication--account-service)  *(api host)*
9. [Sync engine & named settings](#9-sync-engine--named-settings)  *(api host)*
10. [Up Next, History & playback position](#10-up-next-history--playback-position)  *(api host)*
11. [User Files (custom uploads)](#11-user-files-custom-uploads)  *(api + files hosts)*
12. [Search, Ratings, Stats, Bookmarks, Subscriptions, Sharing, Feedback](#12-search-ratings-stats-bookmarks-subscriptions-sharing-feedback)
13. [Podcasts, Refresh, Cache, Discover & Recommendations](#13-podcasts-refresh-cache-discover--recommendations)  *(refresh + cache + static hosts)*
14. [Protobuf schema conventions](#14-protobuf-schema-conventions)
15. [Implementation checklist](#15-implementation-checklist)

---

## 1. Scope & non-goals

**In scope** — the first-party Pocket Casts services the client depends on:

- Account lifecycle: register, login (email/password), SSO / identity refresh tokens, device
  authorization (TV pairing), change email/password, delete account, Sonos exchange.
- The sync engine: incremental + full sync of podcasts, episodes, playlists (filters), folders,
  bookmarks; named user settings.
- Up Next queue sync, listening history sync, per-episode playback-position/star/archive sync.
- User Files: presigned uploads of custom audio/video, artwork, metadata, playback, quota.
- Podcast/episode metadata: refresh service, cache/metadata service, show notes.
- Search (podcasts, episodes, combined, autocomplete/predictive).
- Discover feed (static JSON), recommendations, suggested folders.
- Podcast ratings, listening stats, subscriptions/entitlements, curated sharing lists, support feedback.

**Out of scope** (client-side or third-party — see the surface map):

- Podcast audio/video **download** hosts (the client streams/downloads directly from each podcast's
  own CDN using URLs returned by the cache service; the backend only needs to *return* those URLs).
- Artwork image serving is a static CDN concern (`static.pocketcasts.com`) — documented as URL
  templates, not as dynamic endpoints.
- Third-party analytics/crash SDKs (Bitdrift, TelemetryDeck, Sentry), APNs, App Store receipt
  verification with Apple (the backend *consumes* receipts; it does not replace Apple).

---

## 2. Service topology & hosts

The client selects **production** or **staging** hosts based on `ServerConfig.shared.syncDelegate.production()`.
A re-implementation must serve the production hostnames (or the app must be repointed). Source:
`Public/Sharing/Structs/ServerConstants.swift`.

| Logical service | Production base URL | Staging base URL | Protocol | Purpose |
|---|---|---|---|---|
| **api** | `https://api.pocketcasts.com/` | `https://api.pocketcasts.net/` | Protobuf over HTTPS | Auth, sync, files metadata, ratings, stats, subscriptions |
| **refresh** (aka "main") | `https://refresh.pocketcasts.com/` | `https://refresh.pocketcasts.net/` | JSON + form over HTTPS | Podcast refresh, search-by-url, OPML import/export, user/update |
| **cache** | `https://cache.pocketcasts.com/` | `https://podcast-api.pocketcasts.net/` | JSON over HTTPS | Podcast/episode metadata, show notes, combined search, suggested folders |
| **search** | `https://search.pocketcasts.com/` | `https://search.pocketcasts.net/` | JSON over HTTPS | Autocomplete / predictive search |
| **sharing** | `https://sharing.pocketcasts.com/` | `https://sharing.pocketcasts.net/` | JSON over HTTPS | Create/retrieve shared episode/podcast lists |
| **files** | `https://files.pocketcasts.com/files/` | `https://files.pocketcasts.net/files/` | Binary (presigned upload targets) | User file byte storage |
| **discover / static** | `https://static.pocketcasts.com/discover/` | `https://static.pocketcasts.net/discover/` | Static JSON | Discover feed layout & content |
| **image** | `https://static.pocketcasts.com/` | `https://static.pocketcasts.net/` | Static images | Artwork, colors, metadata JSON |
| **lists** | `https://lists.pocketcasts.com/` | `https://lists.pocketcasts.net/` | Static JSON | Bundle/curated list JSON |
| **share (short links)** | `https://pca.st/` | `https://pcast.pocketcasts.net/` | Redirects | Short share links |
| **shownotes / transcripts** | `https://shownotes.pocketcasts.com/generated_transcripts/` | `https://shownotes.pocketcasts.net/...` | Static | Generated transcripts |
| **tv pair / create** | `https://pocketcasts.com/pair`, `/create` | `.net` equivalents | Web | TV device pairing web pages |

Static support/web URLs (production only, not environment-switched): `support.pocketcasts.com`,
`pocketcasts.com`, `automattic.com`, App Store links. These are opened in a browser, not called as APIs.

---

## 3. Transport & wire conventions

Source: `Private/API Tasks/ApiBaseTask.swift`, `Public/ServerHelper.swift`.

### 3.1 Protobuf endpoints (api host)

Most `api` host endpoints exchange **binary Protocol Buffers** (proto3). The client:

- Sets `Content-Type: application/octet-stream` and `Accept: application/octet-stream`.
- Serializes a request message and sends it as the raw HTTP body (`POST`/`GET`/`DELETE`).
- Deserializes the response body as the corresponding proto message when status is `200`.

The full `.proto` schema is embedded in the generated Swift at
`Private/Protobuffer/api.pb.swift` (18,989 lines) and `Private/Protobuffer/files.pb.swift`.
**The backend MUST reproduce these messages with identical field numbers and types.** Field numbers
are documented per-endpoint in the sections below; §14 explains how to read them from the generated
Swift. The proto package prefix is `api.` (Swift symbol prefix `Api_`) and `files.` respectively.

- **API version:** the client sets `apiVersion = "2"` (see `ApiBaseTask`). Where a version appears
  in a path or header, it is `2`.
- **`scope`:** login/token requests carry `scope = "mobile"` (`ServerConstants.Values.apiScope`).
- **`deviceType`:** iOS reports `deviceType = 1` (`ServerConstants.Values.deviceTypeiOS`).

### 3.2 JSON endpoints (refresh, cache, search, sharing, discover hosts)

The refresh/cache/search/sharing/discover services use JSON. The client:

- Sends `Content-Type: application/json; charset=UTF8`, `Accept: application/json` (or form-encoded
  for some refresh endpoints — noted per endpoint).
- Decodes responses with `keyDecodingStrategy = .convertFromSnakeCase` in several paths, so **JSON
  keys are `snake_case` on the wire** and map to camelCase in the client. Field names in this doc are
  given as they appear on the wire (snake_case) unless stated otherwise.

### 3.3 HTTP methods & idempotency

- Reads and most "list" operations use `POST` with a protobuf/JSON body (not `GET`) on the api host.
- `DELETE` is used for some file/image removals (with a body).
- Plain `GET` is used for cache metadata, show notes, and static discover content.

### 3.4 Timeouts

`ServerConstants.Timeouts`: sync = 60s, general = 60s, cache = 30s. Individual requests set 15–60s.
The backend should respond well within these; long operations must stream or paginate.

---

## 4. Authentication & token model

> Detailed request/response schemas are in [§8](#8-authentication--account-service). This section is
> the behavioral contract every authenticated endpoint depends on.

Source: `Private/TokenHelper.swift`, `Public/API/ApiServerHandler+Account.swift`,
`ApiServerHandler+DeviceAuth.swift`, `ApiServerHandler+SocialAuth.swift`.

### 4.1 Bearer tokens

- All authenticated requests carry `Authorization: Bearer <accessToken>`.
- The access token is a short-lived **sync token** (stored under keychain key `SJSyncV2Token`).
- A long-lived **refresh token** (`SJRefreshToken`) is used to mint new access tokens.

### 4.2 Acquiring an access token — two flows

The client tries, in order:

1. **Email/password** (`acquirePasswordToken`): if the keychain holds an email + password, `POST
   api/user/login` with `Api_UserLoginRequest{ email, password, scope="mobile" }`. On `200`, the
   `Api_UserLoginResponse` returns the access token, refresh/identity token, email, uuid, and
   subscription info. On `401`, the client signs the user out (bad password).
2. **SSO / identity refresh** (`refreshIdentityToken` → `POST api/user/token`): if there is no
   password but there is a refresh token, exchange the refresh token for a new access token via
   `Api_UserTokenRequest`/`Api_UserTokenResponse`.

If both fail with `TOKEN_DEAUTH` or `PERMISSION_DENIED`, the client logs the user out and clears
credentials. Non-auth errors (e.g. no connectivity, backgrounded app) do **not** log the user out.

### 4.3 401 retry contract (critical)

Every authenticated call implements this exact behavior (`ApiBaseTask`, `TokenHelper`):

1. On HTTP `401`, the client discards the cached access token, calls the token endpoint to acquire a
   fresh one, and **retries the original request once**.
2. If the retry also returns `401`, the client deletes `SJSyncV2Token` and gives up (surfacing an
   auth error). The backend must therefore return `401` (not `403`/`400`) for an expired/invalid
   access token, and must accept a freshly-minted token on the immediate retry.

### 4.4 Social / third-party sign-in

`POST api/user/token` also backs Sign in with Apple / Google sign-in: the client presents a provider
token and receives Pocket Casts access + refresh tokens (`Api_UserTokenRequest`/`Response`). The
Apple user id is persisted (`SJAppleAuthUserID`).

### 4.5 Device authorization (TV / Sonos pairing)

- `POST api/device/authorize` → `Api_DeviceAuthorizeResponse` returns a device/user code + polling
  interval (RFC 8628-style device grant). The user visits `pocketcasts.com/pair` to approve.
- The client polls `POST api/user/token` until approval; `authorization_pending` / `expired_token` /
  `access_denied` / `invalid_grant` error codes govern the poll loop.
- `POST api/user/exchange_sonos` exchanges a Pocket Casts session for a Sonos-linkable token.

---

## 5. Error model & status codes

Source: `Public/API/ErrorResponse.swift`, `ApiServerHandler+Account.swift`,
`ServerConstants.HttpConstants`.

### 5.1 HTTP status codes the client distinguishes

| Code | Constant | Client behavior |
|---|---|---|
| 200 | ok | Success; parse body |
| 304 | notModified | Use cached copy (conditional GET) |
| 400 | badRequest | Treated as `TOKEN_DEAUTH` in auth flows; validation error elsewhere |
| 401 | unauthorized | Drop token, re-auth, retry once (see §4.3) |
| 403 | forbidden | `PERMISSION_DENIED`; do **not** retry |
| 404 | notFound | Resource missing (e.g. episode/podcast not found) |
| 409 | conflict | Conflict (e.g. email already taken flows) |
| 500 | serverError | Generic failure; client returns generic error |

### 5.2 Error body format

On error, endpoints that return a JSON error body use this shape (decoded by
`extractErrorResponse`):

```json
{ "errorMessageId": "login_password_incorrect", "error": "invalid_grant" }
```

The client reads `errorMessageId` first, then `error`, and maps the string to an `APIError` case.
Either field may be present. If neither decodes, the client falls back to the HTTP status (400/401 →
`TOKEN_DEAUTH`, 403 → `PERMISSION_DENIED`).

### 5.3 Error code taxonomy (string → meaning)

The backend **must** emit these exact string codes so the client can localize the right message:

**Account / auth**

| Code string | Meaning |
|---|---|
| `login_password_incorrect` | Wrong password |
| `login_permission_denied_not_admin` | Permission denied |
| `login_account_locked` | Account locked |
| `login_email_blank` | Email missing |
| `login_password_blank` | Password missing |
| `login_email_not_found` | No account for email |
| `login_thanks_signing_up` | Post-signup marker |
| `login_unable_to_create_account` | Registration failed |
| `login_password_invalid` | Password fails policy |
| `login_email_invalid` | Malformed email |
| `login_email_taken` | Email already registered |
| `login_user_register_failed` | Generic registration failure |

**User files**

| Code string | Meaning |
|---|---|
| `files_invalid_content_type` | Unsupported MIME type |
| `files_invalid_user` | File not owned by user |
| `files_file_too_large` | Exceeds per-file size limit |
| `files_storage_limit_exceeded` | Exceeds account storage quota |
| `files_title_required` | Missing title |
| `files_uuid_required` | Missing file uuid |
| `files_upload_failed_generic` | Generic upload failure |

**Promotions / device grant**

| Code string | Meaning |
|---|---|
| `promo_already_plus` | User already has Plus |
| `promo_code_expired_or_invalid` | Bad promo code |
| `promo_already_redeemed` | Promo already used |
| `authorization_pending` | Device grant: user hasn't approved yet (keep polling) |
| `expired_token` | Device grant: code expired |
| `access_denied` | Device grant: user rejected |
| `invalid_grant` | OAuth: bad grant |

**Client-only (not emitted by server)**: `no_connection`, `token_deauth`, `unknown`.

---

## 6. Common headers & localization

Source: `Public/Helpers/URLRequest+LocalizationHeaders.swift`, `LocalizationHelper.swift`,
`ServerConstants.HttpHeaders`.

**Request headers the client sends:**

| Header | Value | Notes |
|---|---|---|
| `Content-Type` | `application/octet-stream` (api) / `application/json; charset=UTF8` (json) | |
| `Accept` | matches Content-Type | |
| `Authorization` | `Bearer <token>` | Authenticated calls only |
| `User-Agent` | private app UA (e.g. `Pocket Casts/<version>`) | From `syncDelegate.privateUserAgent()` |
| `X-User-Region` | user region code | Sent **only** to allowed first-party hosts |
| `X-App-Language` | preferred language (e.g. `en-US`) | Sent only to allowed first-party hosts |

`X-User-Region` / `X-App-Language` are attached only when the request host is one of the first-party
hosts in §2 (main, api, cache, sharing, discover, image, files, share, lists, search). The backend
should treat these as advisory for regionalizing discover content, search, and ratings.

**Conditional-request headers** the client both sends and honors on cache/refresh endpoints:
`If-Modified-Since`, `If-None-Match`, and it reads `Last-Modified`, `ETag`, `Expires`,
`Cache-Control`, `Date`. See §13 for the caching contract.

---

## 7. Data model glossary

Common identifiers and enums used across services (source: `Public/ServerEnums.swift`,
`ServerConstants.Values`, `Limits`).

- **uuid** — every podcast, episode, playlist, folder, bookmark, and user file is identified by a
  server-assigned UUID string. The client generates UUIDs for user-created entities (folders,
  bookmarks, playlists) and the server must accept them.
- **Timestamps** — ISO-8601 (`ISO8601DateFormatter`) on the api host; epoch millis in some protobuf
  fields (noted per field). Sync uses a server "last modified" token echoed back to the client.
- **`SubscriptionPlatform`**: `none=0, iOS=1, android=2, web=3, gift=4`.
- **`ThemeType`** (synced as an int setting): `light=0, dark=1, extraDark=2, rosé=3, indigo=4,
  contrastDark=5, contrastLight=6, electric=7, classic=8`.
- **`AutoAddLimitReachedAction`**: `stopAdding=0, addToTopOnly=1`.
- **`PrimaryRowAction`**: `stream=0, download=1`. **`PrimaryUpNextSwipeAction`**: `playNext=0, playLast=1`.
- **`AppBadge`**: `off=0, totalUnplayed=1, newSinceLastOpened=2, filterCount=10`.
- **`HeadphoneControl`**: `addBookmark=0, skipBack=1, skipForward=2, nextChapter=3, previousChapter=4`.
- **`AutoPlaySource`**: string `"downloads" | "files" | "starred"` or a raw podcast/filter uuid.
- **Playing status** (episode): integer enum — `notPlayed`, `inProgress`, `completed` (see §10 for
  exact values used on the wire).
- **Limits**: `maxHistoryItems = 100`, `maxEpisodesToSync = 2000`. `oldEpisodeCutoff = 2 weeks`.


---

## 8. Authentication & Account service

*Host: **api**. Wire format: protobuf request/response; JSON error bodies. Base `https://api.pocketcasts.com/`.*

### Endpoint summary

| Method | Path | Auth | Request | Success response |
|---|---|---|---|---|
| POST | `user/login` | none | `Api_UserLoginRequest` | `Api_UserLoginResponse` |
| POST | `user/register` | none | `Api_RegisterRequest` | `Api_RegisterResponse` |
| POST | `user/forgot_password` | none | `Api_EmailRequest` | `Api_UserChangeResponse` |
| POST | `user/token` | none | `Api_UserTokenRequest` | `Api_TokenLoginResponse` |
| POST | `device/authorize` | none | `Api_DeviceAuthorizeRequest` | `Api_DeviceAuthorizeResponse` |
| POST | `user/change_email` | Bearer | `Api_UserChangeEmailRequest` | `Api_UserChangeResponse` |
| POST | `user/change_password` | Bearer | `Api_UserChangePasswordRequest` | `Api_UserChangeResponse` |
| POST | `user/delete_account` | Bearer | `Api_BasicRequest` | `Api_UserChangeResponse` |
| POST | `user/exchange_sonos` | Bearer | *(empty body)* | JSON `{access_token, refresh_token}` |

> **Wire-format note that applies to the whole api host:** success bodies are **protobuf**; error
> bodies are **JSON** `{ "errorMessageId": "...", "error": "..." }` (see §5). `user/exchange_sonos`
> is the one endpoint whose *success* body is JSON.

### Token model & flows

- **Two token families.** `user/login` (email/password) returns an access `token` only.
  `user/token` (OAuth-style) returns `access_token` **and** `refresh_token` + `expires_in` and backs
  SSO/Apple sign-in, refresh-token rotation, and the device (TV) grant.
- **iOS decodes `user/token` as `Api_TokenLoginResponse`** (7 fields, incl. refresh token + `is_new`),
  *not* the similarly named `Api_UserTokenResponse` that also exists in the schema. Match
  `Api_TokenLoginResponse` on the wire.
- **`scope`** values: `mobile` (app), `tv` (device grant), `sonos` (Sonos link).
- **`deviceType`/`dt`**: iOS = `1`. `Api_UserLoginRequest` also carries optional device-metadata
  fields (`device, v, m, av, f, l, c`) — tolerate present or absent.
- **Email/password re-acquisition:** the client stores email+password and silently re-POSTs
  `user/login` whenever it needs a fresh token.
- **SSO/refresh:** first Apple sign-in POSTs `user/token{ grant_type="refresh_token",
  refresh_token=<Apple identityToken>, scope="mobile" }`; later renewals resend the stored
  `refresh_token`.
- **Device (TV) grant (RFC 8628):** `device/authorize` → poll `user/token{
  grant_type="urn:ietf:params:oauth:grant-type:device_code", device_code, scope="tv" }`; return
  `authorization_pending` until approved, then `expired_token`/`access_denied`/`invalid_grant` as
  applicable. User approves at `pocketcasts.com/pair`.
- **401 retry (see §4.3):** the client does not check `expires_in`; it reacts to `401` by dropping
  the token, re-acquiring, and retrying **once**.

### Message field tables

**`Api_UserLoginRequest`** — `1 email:string, 2 password:string, 3 scope:string("mobile"),
4 dt:string, 5 device:string, 6 v:string, 7 m:string, 8 av:string, 9 f:string, 10 l:string, 11 c:string`.
Fields 4–11 are device metadata, currently sent empty.

**`Api_UserLoginResponse`** — `1 token:string, 2 uuid:string, 3 email:string`. No refresh token.

**`Api_RegisterRequest`** — `1 email:string, 2 password:string, 3 scope:string("mobile")`.

**`Api_RegisterResponse`** — `1 success:google.protobuf.BoolValue, 2 message:string, 3 token:string,
4 uuid:string, 5 errors:repeated string`. Client reads `success.value` and `uuid`.

**`Api_EmailRequest`** (forgot password) — `1 email:string`.

**`Api_UserChangeResponse`** — `1 success:google.protobuf.BoolValue, 2 message:string,
3 message_id:string`. Client reads `success.value` (and `message` for delete-account).

**`Api_UserTokenRequest`** — `1 code:string, 2 grant_type:string, 3 refresh_token:string,
4 scope:string, 5 device_code:string`.

**`Api_TokenLoginResponse`** (the `user/token` success shape) — `1 email:string, 2 uuid:string,
3 is_new:bool, 4 access_token:string, 5 token_type:string, 6 expires_in:int32, 7 refresh_token:string`.

**`Api_DeviceAuthorizeRequest`** — `1 scope:string("tv")`.

**`Api_DeviceAuthorizeResponse`** — `1 device_code:string, 2 user_code:string, 3 verification_uri:string,
4 verification_uri_complete:string, 5 expires_in:int32, 6 interval:int32`.

**`Api_UserChangeEmailRequest`** — `1 email:string, 2 password:string, 3 scope:string("mobile")`. Bearer required.

**`Api_UserChangePasswordRequest`** — `1 old_password:string, 2 new_password:string,
4 scope:string("mobile")` — **note field 3 is skipped/reserved; scope is field 4.** Bearer required.

**`Api_BasicRequest`** (delete account) — `1 v:string, 2 m:string`, serialized empty. Bearer required.

**`user/exchange_sonos`** — Bearer required, **empty** octet-stream body; success body is JSON
`{ "access_token": "...", "refresh_token": "..." }`.

### Additional auth messages in the schema (not exercised by this iOS client, implement for parity)

- **`Api_UserAuthorizeRequest`** (web OAuth authorize): `1 email, 2 password, 3 response_type,
  4 client_id, 5 redirect_uri, 6 scope, 7 state` (all string).
- **`Api_UserAuthorizeResponse`**: `1 success:bool, 2 code:string, 3 error:string, 4 state:string`.
- **`Api_UserRevokeRequest`**: `1 refresh_token:string`.
- **`Api_UserResetPasswordRequest`**: `1 reset_password_token:string, 2 password:string, 3 scope:string`.
- **`Api_UserTokenResponse`** (alt token shape): `1 access_token:string, 2 token_type:string,
  3 expires_in:int32, 4 refresh_token:google.protobuf.StringValue`.
- **`Api_UserIdResponse`**: `1 id:string`. **`Api_EmptyRequest`/`Api_EmptyResponse`**: no fields.
- **`Api_DeviceApproveRequest`** (approving-device side): `1 user_code:string, 2 deny:bool`.
- **`Api_TokenErrorResponse`** (protobuf OAuth error): `1 error:string, 2 error_description:string,
  3 error_uri:string`.

*Sources: `ApiServerHandler+Account.swift`, `+DeviceAuth.swift`, `+SocialAuth.swift`,
`TokenHelper.swift`, `ChangeEmailTask.swift`, `ChangePasswordTask.swift`, `DeleteAccountTask.swift`,
`ExchangeSonosTask.swift`, `AuthenticationResponse.swift`, `api.pb.swift`.*

---

## 9. Sync engine & named settings

*Host: **api**. All `POST` + protobuf. `Content-Type`/`Accept: application/octet-stream`, Bearer auth,
60s timeout. This is the heart of the product: it reconciles podcasts, episodes, playlists (filters),
folders, bookmarks, and per-account settings across devices.*

### Well-known UUID sentinels

- **Home-grid (no folder) sentinel:** `973df93c-e4dc-41fb-879e-0c7b532ebb70`. A podcast whose
  `folder_uuid` equals this is "top-level, not in any folder."
- **Fake podcast UUID for user-uploaded files:** `da7aba5e-f11e-f11e-f11e-da7aba5ef11e`.

### Endpoint summary

| Method | Path | Request | Response | Purpose |
|---|---|---|---|---|
| POST | `user/last_sync_at` | `Api_EmptyRequest` | `Api_UserLastSyncAtResponse` | Bootstrap watermark |
| POST | `user/sync/update` | `Api_SyncUpdateRequest` | `Api_SyncUpdateResponse` | Incremental bidirectional sync |
| POST | `user/podcast/list` | `Api_UserPodcastListRequest` | `Api_UserPodcastListResponse` | Full sync: subs + folders |
| POST | `user/podcast/episodes` | `Api_UuidRequest` | `Api_SyncEpisodesResponse` | Per-podcast episode state |
| POST | `user/playlist/list` | `Api_UserPlaylistListRequest` | `Api_UserPlaylistListResponse` | Filters / playlists |
| POST | `user/named_settings/update` | `Api_NamedSettingsRequest` | `Api_NamedSettingsResponse` | Account settings |

### 9.1 Sync model

The client persists a string watermark in UserDefaults (`PCLastModifiedServerDate`). Its
presence selects the mode:

- **Full sync (bootstrap, watermark absent):** `user/last_sync_at` → `user/podcast/list` (subs +
  folders) → `user/podcast/episodes` per podcast → `user/playlist/list` → bookmarks. Then persist the
  captured `last_sync_at` as the watermark.
- **Incremental sync (watermark present):** a single **bidirectional** `user/sync/update`. The client
  packs locally-changed entities as a repeated list of `Api_Record` (a oneof) + its last watermark; the
  server replies with records changed on *other* devices since that watermark + a **new** watermark.

**Apply ordering (referential integrity):** the client applies downstream records in the order
**folders → podcasts → episodes → playlists → bookmarks** (folders first because podcasts reference
`folder_uuid`; podcasts before episodes). The backend should assume this order on the client and keep
records internally consistent.

**Watermark format:** **int64 epoch-milliseconds**, round-tripped as a string. (The client tolerates
two legacy ISO-8601 forms on read but a re-implementation should emit int64 epoch-millis in
`SyncUpdateResponse.last_modified` and `UserLastSyncAtResponse`.)

### 9.2 Core messages

**`Api_UserLastSyncAtResponse`** — `1 last_sync_at:string, 2 last_sync_at_ms:int64` (client reads field 1).

**`Api_SyncUpdateRequest`** — `1 device_utc_time_ms:int64, 2 last_modified:int64, 3 country:string,
4 device_id:string, 5 records:repeated Api_Record, 6 device_type:Int32Value(=1)`.

**`Api_SyncUpdateResponse`** — `1 last_modified:int64 (new watermark), 2 records:repeated Api_Record`.

**`Api_Record`** — a **oneof** (exactly one set): `1 podcast:Api_SyncUserPodcast, 2 episode:Api_SyncUserEpisode,
3 playlist:Api_SyncUserPlaylist, 4 device:Api_SyncUserDevice, 5 folder:Api_SyncUserFolder,
6 bookmark:Api_SyncUserBookmark`. Same type both directions.

**`Api_UserPodcastListRequest`** — `1 v:string, 2 m:string("mobile")`.
**`Api_UserPodcastListResponse`** — `1 podcasts:repeated Api_UserPodcastResponse, 2 folders:repeated Api_PodcastFolder`.
**`Api_UuidRequest`** (episodes) — `1 v:string, 2 m:string("mobile"), 3 uuid:string (podcast), 4 include_bookmarks:bool`.
**`Api_UserPlaylistListRequest`** — `1 v:string, 2 m:string("mobile"), 3 exclude_deleted:bool`.
**`Api_UserPlaylistListResponse`** — `1 playlists:repeated Api_PlaylistSyncResponse`.

**`Api_UserPodcastResponse`** — `1 uuid, 2 episodes_sort_order:int32, 3 auto_start_from:int32, 4 title,
5 author, 6 description, 7 url, 8 last_episode_published:Timestamp, 9 unplayed:bool, 10 last_episode_uuid,
11 last_episode_playing_status:int32, 12 last_episode_archived:bool, 13 auto_skip_last:int32,
14 folder_uuid:StringValue, 15 sort_position:Int32Value, 16 date_added:Timestamp, 17 settings:Api_PodcastSettings,
18 description_html, 19 is_private:BoolValue, 20 slug, 21 explicit:BoolValue`.

**`Api_PodcastFolder`** — `1 folder_uuid, 2 name, 3 color:int32, 4 sort_position:int32,
5 podcasts_sort_type:int32, 6 date_added:Timestamp`.

### 9.3 Sync record sub-messages

**`Api_SyncUserPodcast`** — `1 uuid, 2 is_deleted:BoolValue (true=unsubscribed), 3 subscribed:BoolValue,
4 auto_start_from:Int32Value, 5 episodes_sort_order:Int32Value, 6 auto_skip_last:Int32Value,
7 folder_uuid:StringValue (home-grid sentinel = not in folder), 8 sort_position:Int32Value,
9 date_added:Timestamp, 10 settings:Api_PodcastSettings`.

**`Api_SyncUserEpisode`** (per-field LWW — value only sent with its `*_modified` when changed locally) —
`1 uuid, 2 podcast_uuid, 3 is_deleted:BoolValue (=archived), 4 is_deleted_modified:Int64Value,
5 duration:Int64Value, 6 duration_modified:Int64Value, 7 playing_status:Int32Value (1/2/3),
8 playing_status_modified:Int64Value, 9 played_up_to:Int64Value (seconds), 10 played_up_to_modified:Int64Value,
11 starred:BoolValue (keep), 12 starred_modified:Int64Value, 13 deselected_chapters:string,
14 deselected_chapters_modified:Int64Value`.

**`Api_SyncUserPlaylist`** — `1 uuid, 2 is_deleted:BoolValue, 3 title:StringValue, 4 all_podcasts:BoolValue,
5 podcast_uuids:StringValue, 6 episode_uuids:StringValue, 7 audio_video:Int32Value, 8 not_downloaded:BoolValue,
9 downloaded:BoolValue, 10 downloading:BoolValue, 11 finished:BoolValue, 12 partially_played:BoolValue,
13 unplayed:BoolValue, 14 starred:BoolValue, 15 manual:BoolValue, 16 sort_position:Int32Value,
17 sort_type:Int32Value, 18 icon_id:Int32Value, 19 filter_hours:Int32Value, 20 original_uuid:string,
21 filter_duration:BoolValue, 22 longer_than:Int32Value, 23 shorter_than:Int32Value,
24 episode_order:repeated string, 25 episodes:repeated Api_SyncPlaylistEpisode, 26 show_archived:BoolValue`.
**`original_uuid` (20) is the canonical, case-preserved id** — the client keys playlists off it. Fields
24/25 are sent only for **manual** playlists.

**`Api_SyncPlaylistEpisode`** — `1 episode, 2 podcast, 3 added:Int64Value, 4 published:Timestamp,
5 title:StringValue, 6 url:StringValue, 7 podcast_slug:StringValue, 8 episode_slug:StringValue`.

**`Api_SyncUserFolder`** — `1 folder_uuid, 2 is_deleted:bool (plain), 3 name, 4 color:int32,
5 sort_position:int32, 6 podcasts_sort_type:int32, 7 date_added:Timestamp`. Folders are **server-wins**
on full sync (local wiped and rebuilt).

**`Api_SyncUserBookmark`** — `1 bookmark_uuid, 2 podcast_uuid (fake-podcast sentinel for files),
3 episode_uuid, 4 created_at:Timestamp, 5 time:Int32Value (seconds), 6 title:StringValue,
7 title_modified:Timestamp, 8 is_deleted:BoolValue, 9 is_deleted_modified:Timestamp`. Read-side full-sync
uses `Api_BookmarkResponse` — `1 bookmark_uuid, 2 podcast_uuid, 3 episode_uuid, 5 time:int32, 6 title,
7 createdAt:Timestamp`.

**`Api_SyncUserDevice`** (cumulative stats, seconds; merged max-wise not timestamped) — `1 device_id:StringValue,
2 device_type:Int32Value(=1), 3 times_started_at:Int64Value, 4 time_silence_removal:Int64Value,
5 time_variable_speed:Int64Value, 6 time_intro_skipping:Int64Value, 7 time_skipping:Int64Value,
8 time_listened:Int64Value`. (The **read-side** stats response numbers these differently — see §12 —
respect each message's own numbering.)

### 9.4 Per-podcast settings — `Api_PodcastSettings`

Embedded in `SyncUserPodcast.settings` (#10) and `UserPodcastResponse.settings` (#17). Each field is a
typed setting wrapper (§9.6) carrying its own `value`/`changed`/`modified_at`:
`1 notification:Bool, 2 add_to_up_next:Bool, 3 add_to_up_next_position:Int32, 4 auto_archive:Bool,
5 playback_effects:Bool, 6 playback_speed:Double, 7 trim_silence:Int32, 8 volume_boost:Bool,
9 auto_start_from:Int32, 10 auto_skip_last:Int32, 11 episodes_sort_order:Int32, 12 auto_archive_played:Int32,
13 auto_archive_inactive:Int32, 14 auto_archive_episode_limit:Int32, 15 episode_grouping:Int32,
16 show_archived:Bool`.

### 9.5 Named settings — `user/named_settings/update`

Account-scoped (not per-device), bidirectional in one call.
**`Api_NamedSettingsRequest`** — `1 v:string, 2 m:string (client sends literal "iPhone"),
3 settings:Api_NamedSettings (legacy), 4 changed_settings:Api_ChangeableSettings (current path)`.
**`Api_NamedSettingsResponse`** shares the field map below (plus field 94 `developer`).

### 9.6 Setting value wrapper types

`Api_Int32Setting`, `Api_BoolSetting`, `Api_StringSetting`, `Api_DoubleSetting` all share:
`1 value:<matching wrapper>, 2 changed:BoolValue, 3 modified_at:Timestamp`.
- **Request:** client sets `value` + `modified_at` only for locally-changed settings; leaves `changed` unset.
- **Response:** server sets `changed=true` when its `value` should override the client, with the
  authoritative `modified_at`.

### 9.7 `Api_ChangeableSettings` / `Api_NamedSettings` field map (authoritative)

Field numbers **10 and 13 are unused/reserved**. Each entry's type is the wrapper from §9.6.

| # | name | type | # | name | type |
|---|---|---|---|---|---|
| 1 | grid_layout | Int32 | 51 | privacy_analytics | Bool |
| 2 | grid_order | Int32 | 52 | privacy_crash_reports | Bool |
| 3 | show_played | Int32 | 53 | privacy_link_account | Bool |
| 4 | theme | Int32 | 54 | player_shelf | String |
| 5 | skip_forward | Int32 | 55 | auto_subscribe_to_played | Bool |
| 6 | skip_back | Int32 | 56 | auto_show_played | Bool |
| 7 | web_version | Int32 | 57 | auto_play_enabled | Bool |
| 8 | language | String | 58 | auto_play_last_list_uuid | String |
| 9 | recommendations_on | Bool | 59 | trim_silence | Int32 |
| 11 | use_embedded_artwork | Bool | 60 | show_artwork_on_lock_screen | Bool |
| 12 | playback_speed | Double | 61 | headphone_controls_next_action | Int32 |
| 14 | volume_boost | Bool | 62 | headphone_controls_previous_action | Int32 |
| 15 | badges | Int32 | 63 | headphone_controls_play_bookmark_confirmation_sound | Bool |
| 16 | free_gift_acknowledgement | Bool | 64 | dark_theme_preference | Int32 |
| 17 | marketing_opt_in | Bool | 65 | light_theme_preference | Int32 |
| 18 | auto_archive_played_episodes | Bool | 66 | use_system_theme | Bool |
| 19 | auto_archive_includes_starred | Bool | 67 | episode_bookmarks_sort_type | Int32 |
| 20 | region | String | 68 | player_bookmarks_sort_type | Int32 |
| 21 | row_action | Int32 | 69 | podcast_bookmarks_sort_type | Int32 |
| 22 | up_next_swipe | Int32 | 70 | use_dark_up_next_theme | Bool |
| 23 | episode_grouping | Int32 | 71 | use_dynamic_colors_for_widget | Bool |
| 24 | show_archived | Bool | 72 | files_sort_order | Int32 |
| 25 | open_links | Bool | 73 | background_refresh | Bool |
| 26 | media_actions | Bool | 74 | auto_download_unmetered_only | Bool |
| 27 | media_actions_order | String | 75 | auto_download_only_when_charging | Bool |
| 28 | keep_screen_awake | Bool | 76 | auto_download_up_next | Bool |
| 29 | open_player | Bool | 77 | cloud_auto_upload | Bool |
| 30 | intelligent_resumption | Bool | 78 | cloud_auto_download | Bool |
| 31 | play_up_next_on_tap | Bool | 79 | cloud_download_unmetered_only | Bool |
| 32 | remote_skip_chapters | Bool | 80 | use_rss_artwork | Bool |
| 33 | playback_actions | Bool | 81 | bookmarks_sort_order | Int32 |
| 34 | legacy_bluetooth | Bool | 82 | auto_archive_played_episodes_global | Bool |
| 35 | multi_select_gesture | Bool | 83 | auto_archive_includes_starred_global | Bool |
| 36 | chapter_titles | Bool | 84 | files_auto_up_next_global | Bool |
| 37 | notifications | Bool | 85 | files_after_playing_delete_local_global | Bool |
| 38 | notification_actions | String | 86 | files_after_playing_delete_cloud_global | Bool |
| 39 | play_over_notifications | Int32 | 87 | player_shelf_global | String |
| 40 | hide_notification_on_pause | Bool | 88 | row_action_global | Int32 |
| 41 | app_badge | Int32 | 89 | use_embedded_artwork_global | Bool |
| 42 | app_badge_filter | String | 90 | recommendations_on_global | Bool |
| 43 | auto_archive_played | Int32 | 91 | grid_layout_global | Int32 |
| 44 | auto_archive_inactive | Int32 | 92 | volume_boost_global | Bool |
| 45 | auto_up_next_limit | Int32 | 93 | badges_global | Int32 |
| 46 | auto_up_next_limit_reached | Int32 | 94 | developer | *(NamedSettings/Response only)* |
| 47 | warn_data_usage | Bool | 95 | smart_folders_number_of_times_shown | Int32 |
| 48 | files_auto_up_next | Bool | 96 | smart_folders_last_date_shown | String |
| 49 | files_after_playing_delete_local | Bool | 97 | save_up_next_on_playlists_play_all | Bool |
| 50 | files_after_playing_delete_cloud | Bool | 98 | do_not_sell_or_share | Bool |
| | | | 99 | live_analytics_url | String |
| | | | 100 | listening_time_stats | Bool |

**`*_global` split (82–93):** several settings have both a per-podcast-defaultable value and a `_global`
variant; the current iOS client reads/writes the **global** variants for those. `live_analytics_url` (99)
is stored client-side as the live-analytics endpoint.

### 9.8 Conflict resolution (last-write-wins by `modified_at`)

Field-level LWW keyed on a per-field modified timestamp — no vector clocks.

- **Settings:** upload a setting only if changed locally (value + `modified_at`). Apply an incoming
  setting only if `incoming.modified_at > local.modified_at` (missing local = epoch 0). When applying a
  server value the client does **not** stamp a local `modified_at` (so it won't re-upload). Server signals
  authority with `changed=true`.
- **Episodes / bookmarks:** each mutable attribute carries its own `*_modified`; newer wins. Deletes win.
  **Actively-playing override:** the client never lets the server overwrite state for the currently-playing
  episode — it keeps local and re-flags it unsynced.
- **Podcasts/folders/playlists (structural):** no per-field timestamps. Full sync is **server-wins** for
  folders and playlists (local wiped/replaced). Incremental deletions (`is_deleted`) always win.

### 9.9 Backend checklist for sync

1. One account-level `last_modified` watermark (epoch-ms); `user/sync/update` returns records changed
   after the request watermark and echoes the new max. `user/last_sync_at` returns the current value.
2. Persist per-field `modified_at` for every episode attribute, named setting, podcast setting, and
   bookmark title/deleted — the sole conflict authority.
3. Honor the two UUID sentinels; preserve `original_uuid` case for playlists.
4. Some settings have plain + `_global` fields; mobile writes globals.
5. `device`/stats records are cumulative counters merged max-wise.
6. Bearer auth; return 401 to force client re-auth.

*Sources: `SyncTask.swift`, `SyncTask+{LocalChanges,ServerChanges,FullSync}.swift`, `SyncSettingsTask.swift`,
`ApiSetting.swift`, `ApiSetting+ModifiedDate.swift`, `AppSettings.swift`, the `Retrieve*` tasks, `api.pb.swift`.*

---

## 10. Up Next, History & playback position

*Host: **api**. All endpoints `POST` with protobuf bodies. `version` field is the string `"2"`.
Timestamps here are **epoch milliseconds (int64)** for sync cursors, and `google.protobuf.Timestamp`
for episode publish dates. Wrapper types (`Int32Value`/`BoolValue`) are presence-tracking.*

### Endpoint summary

| Method | Path | Request | Response | Notes |
|---|---|---|---|---|
| POST | `up_next/sync` | `Api_UpNextSyncRequest` | `Api_UpNextResponse` / `304` | Action-log queue merge |
| POST | `sync/update_episode` | `Api_UpdateEpisodeRequest` | `Api_UpdateEpisodeResponse` (empty) | Single-episode position/status |
| POST | `sync/update_episode_star` | `Api_UpdateEpisodeStarRequest` | `Api_UpdateEpisodeStarResponse` (empty) | Star/keep |
| POST | `starred/list` | `Api_EmptyRequest` | `Api_StarredEpisodesResponse` | Fetch starred |
| POST | `history/sync` | `Api_HistorySyncRequest` | `Api_HistoryResponse` / `304` | Listening history merge |

### 10.1 Version-cursor concurrency model (Up Next + History)

Both queues use an **action-log merge with a server version cursor**, not whole-state replacement:

1. Each collection has one `serverModified` cursor (int64 epoch ms). The client stores it as a string
   in UserDefaults (`SJUpNextServerLastModified`, `SJHistoryServerLastModified`) and echoes it in the
   next request.
2. The client sends its cursor + a list of local change actions since last sync.
3. **If nothing is newer than the client's cursor and no incoming change needs a response → return
   `304 Not Modified`** (empty body); the client does nothing.
4. Otherwise apply the incoming actions, bump `serverModified`, and return `200` with the
   **authoritative ordered list** + the new cursor.

Per-episode playback/starred state uses **last-writer-wins** via per-field `...Modified` epoch-ms
timestamps, independent of the collection cursors (see §9 and §10.6).

> **Stability requirement:** the client logs an error ("queueOverwritten") if a sync deletes >75% of
> the local Up Next queue. When no real change occurred, the server MUST return `304` (or the identical
> queue) rather than a spuriously reordered/emptied list.

### 10.2 `up_next/sync`

**`Api_UpNextSyncRequest`** — `1 deviceTime:int64, 2 version:string("2"), 3 model:string,
4 upNext:Api_UpNextChanges, 5 showPlayStatus:bool, 6 deviceID:string`. Field 4 is **omitted entirely
when the sync reason is login** (pull-and-merge instead of push).

**`Api_UpNextChanges`** — `1 serverModified:int64 (omitted if none), 2 changes:repeated Change,
3 order:repeated string (schema present; not populated by iOS)`.

**`Api_UpNextChanges.Change`** — `1 uuid:string (empty for replace), 2 action:int32,
3 modified:int64, 4 title:string, 5 url:string (real episodes only), 6 podcast:string
(fake podcast id for user files), 7 episodes:repeated Api_UpNextEpisodeRequest (replace only),
8 published:google.protobuf.Timestamp`.

**Action values:** `1 playNow` (insert at top / play now), `2 playNext` (position 1),
`3 playLast` (append), `4 remove`, `5 replace` (whole queue with ordered `episodes` list).
Actions 1–4 send a single `uuid`; action 5 sends the `episodes` list and empty top-level `uuid`.

**`Api_UpNextEpisodeRequest`** (non-contiguous numbers) — `1 uuid:string, 4 title:string, 5 url:string,
6 podcast:string, 7 published:google.protobuf.Timestamp`.

**`Api_UpNextResponse`** — `1 serverModified:int64, 4 episodes:repeated EpisodeResponse (authoritative
ordered queue, index 0 = now playing), 5 episodeSync:repeated EpisodeSyncResponse (per-episode state;
iOS currently consumes only field 4)`.
`EpisodeResponse` — `1 title, 2 url, 3 podcast, 4 uuid, 5 published(Timestamp)`.
`EpisodeSyncResponse` — `1 uuid, 6 playedUpTo:Int32Value, 7 duration:Int32Value`.

**Login / new-account special cases:** on login the client sends no changes, pulls the server queue,
merges non-destructively (keeps local-only episodes), and re-pushes a `replace`. On a brand-new
account with an already-playing episode, it ignores the empty server queue and persists its local copy.

**Related (schema present, implement for parity):** `Api_UpNextPlayRequest{1 version, 2 model,
3 episode:Api_UpNextEpisodeRequest}` (`up_next/play`); `Api_UpNextListRequest{1 limit:int32,
2 version, 3 model, 4 serverModified:int64, 5 showPlayStatus:bool}` (`up_next/list`);
`Api_UpNextRemoveRequest{1 uuids:repeated string, 2 version}` (`up_next/remove`).

### 10.3 `sync/update_episode` — single-episode playback position

**`Api_UpdateEpisodeRequest`** — `1 uuid:string, 2 podcast:string, 3 position:Int32Value (playedUpTo,
seconds), 4 status:int32 (PlayingStatus: 1=notPlayed,2=inProgress,3=completed,4=old), 5 duration:int32
(seconds), 6 stats:Api_StatsRequest (optional; not set here)`.
Response `Api_UpdateEpisodeResponse` is **empty** — client keys on HTTP 200.
`Api_StatsRequest` — `1 deviceID:string, 2 timeSilenceRemoval:int32, 3 timeSkipping:int32,
4 timeIntroSkipping:int32, 5 timeVariableSpeed:int32, 6 timeListened:int32, 7 deviceType:int32`.

### 10.4 `sync/update_episode_star` — star / keep

**`Api_UpdateEpisodeStarRequest`** — `1 uuid:string, 2 podcast:string, 3 star:bool`. Response
`Api_UpdateEpisodeStarResponse` is **empty**; 200 clears the local dirty flag.

### 10.5 `starred/list` — fetch starred

Request `Api_EmptyRequest`. **`Api_StarredEpisodesResponse`** — `1 episodes:repeated Api_StarredEpisode`.
**`Api_StarredEpisode`** — `1 uuid:string, 2 podcastUuid:string, 3 duration:int32, 4 playingStatus:int32,
5 playedUpTo:int32, 6 isDeleted:bool (archived), 7 starredModified:int64 (epoch ms; client compares to
its stored value to decide whether to re-star locally)`.

### 10.6 `history/sync`

Same cursor pattern as Up Next. Client pushes unsynced episodes (SQL `LIMIT 1000`, ordered by
`lastPlaybackInteractionDate DESC`).

**`Api_HistorySyncRequest`** — `1 deviceTime:int64, 2 serverModified:int64 (omitted if none),
3 changes:repeated Api_HistoryChange, 4 version:string("2")`.
**`Api_HistoryChange`** (request + response) — `1 action:int32 (1=add, 2=delete, 3=clearAll),
2 podcast:string, 3 episode:string, 4 modifiedAt:int64 (epoch ms), 5 title:string, 6 url:string,
7 published:google.protobuf.Timestamp`.
**`Api_HistoryResponse`** — `1 serverModified:int64, 2 lastCleared:int64 (if >0, client clears local
interaction dates before this time), 3 changes:repeated Api_HistoryChange`.

**Clear-history:** the client appends one change with `action=3` and `modifiedAt` = local clear time.
**`maxHistoryItems = 100`:** the client applies only the first 100 items of the response — return most
recent first. On `304` the client marks all local history synced.

**Year history (schema only, endpoint elsewhere):** `Api_YearHistoryRequest{2 version, 3 count:bool,
4 year:int32}` → `Api_YearHistoryResponse{oneof: 2 count:int32 | 3 history:Api_HistoryResponse}`.

### 10.7 Bulk-sync episode state (shared with §9)

The same playback state flows through the full-sync path. Incoming **`Api_EpisodeSyncResponse`** —
`1 uuid, 2 playingStatus:int32, 3 playedUpTo:int32, 4 isDeleted:bool, 5 starred:bool, 6 duration:int32,
7 bookmarks:repeated Api_BookmarkResponse, 8 deselectedChapters:string`.
**`Api_SyncEpisodesResponse`** — `1 episodes:repeated Api_EpisodeSyncResponse,
2 autoStartFrom:Int32Value, 3 episodesSortOrder:Int32Value, 4 autoSkipLast:Int32Value`.
**`Api_EpisodeWithPodcast`** — `1 uuid, 2 podcast, 3 includeBookmarks:bool`.
**`Api_UpdateEpisodesArchiveRequest`** — `1 archive:bool, 2 episodes:repeated Api_EpisodeWithPodcast`.
Client rule: never overwrites state for the currently-playing episode (marks local unsynced instead);
seeks the player when a paused now-playing episode's `playedUpTo` changes.

### 10.8 Limits

`maxEpisodesToSync = 2000` (full episode sync push only, not the single-episode endpoints);
`maxHistoryItems = 100` (history response apply); history request SQL `LIMIT 1000`.

*Sources: `UpNextSyncTask.swift`, `SyncHistoryTask.swift`, `PositionSyncTask.swift`,
`StarredSyncTask.swift`, `RetrieveStarredTask.swift`, `UpNextChanges.swift`, `Enums.swift`, `api.pb.swift`.*

---

## 11. User Files (custom uploads)

*Hosts: **api** (metadata, presigned-URL brokering) + presigned **S3** targets (byte storage) + **files**
CDN. Wire format: protobuf (`files.proto`, package `files`); JSON error bodies.*

The "Files" feature lets a user upload custom audio/video (`UserEpisode`s) and artwork. The api host
only brokers metadata and presigned URLs; the actual bytes are `PUT` to a presigned storage URL (S3),
and uploads are confirmed via an S3→SNS→backend pipeline that the client polls.

### Endpoint summary

| Method | Path | Auth | Request | Success response |
|---|---|---|---|---|
| GET | `files` | Bearer | *(empty `FileListRequest`)* | `Files_FileListResponse` |
| POST | `files` | Bearer | `Files_FileListUpdateRequest` | *(status only)* |
| POST | `files/upload/request` | Bearer | `Files_FileUploadRequest` | `Files_FileUploadResponse` (presigned PUT url) |
| POST | `files/upload/image` | Bearer | `Files_ImageUploadRequest` | `Files_ImageUploadResponse` (presigned PUT url) |
| GET | `files/upload/status/{uuid}` | Bearer | — | `Files_SuccessResponse` |
| GET | `files/play/{uuid}` | Bearer | — | `Files_FilePlayResponse` (playback url) |
| DELETE | `files/image/{uuid}` | Bearer | `Files_FileDeleteRequest` | *(empty)* |
| DELETE | `files/{uuid}` | Bearer | `Files_FileDeleteRequest` | *(empty)* |
| GET | `files/usage/` | Bearer | — | `Files_AccountUsage` |

Conditional caching: `GET files` and `GET files/usage/` send `If-Modified-Since` and honor
`Last-Modified`/`304` (separate stored values per endpoint). `DELETE` endpoints treat `404` as success
(already gone). On `401`, GET/POST re-auth+retry once; DELETE does not retry.

### Protobuf messages (`files.proto`)

**`Files_File`** (canonical record) — `1 uuid:string, 2 title:string, 3 size:int64,
4 contentType:string, 5 playedUpTo:int32, 6 playedUpToModified:int64, 7 playingStatus:int32
(1=notPlayed,2=inProgress,3=completed,4=old), 8 playingStatusModified:int64, 9 duration:int64,
10 published:google.protobuf.Timestamp, 11 colour:int32, 12 imageUrl:string,
13 hasCustomImage:bool, 14 modifiedAt:google.protobuf.Timestamp, 15 imageStatus:int32,
16 bookmarks:repeated Api_BookmarkResponse`. Read path consumes 1,2,3,4,5,7,9,11,12.

**`Files_FileUpdate`** (sparse patch — wrapper types distinguish unset from 0) — `1 uuid:string,
2 title:string, 3 playedUpTo:google.protobuf.Int32Value, 4 playingStatus:Int32Value,
5 duration:Int64Value, 6 colour:Int32Value`. Only fields whose local `*Modified` marker > 0 are sent.

**`Files_AccountUsage`** — `1 totalSize:int64` (quota → `customStorageUserLimit`),
`2 usedSize:int64` (→ `customStorageUsed`), `3 totalFiles:int64` (→ `customStorageNumFiles`).

**`Files_FileListRequest`** — empty. **`Files_FileListResponse`** — `1 files:repeated Files_File,
2 account:Files_AccountUsage`. **`Files_FileListUpdateRequest`** — `1 files:repeated Files_FileUpdate`.

**`Files_FileUploadRequest`** — `1 uuid:string, 2 title:string (client sends "No Title" if empty),
3 size:int64, 4 contentType:string (falls back to audio/mp3), 5 duration:int64,
6 colour:Int32Value, 7 hasCustomImage:bool`. **`Files_FileUploadResponse`** — `1 uuid:string,
2 url:string` (presigned S3 PUT).

**`Files_ImageUploadRequest`** — `1 uuid:string, 2 size:int64, 3 contentType:string ("image/jpeg")`.
**`Files_ImageUploadResponse`** — `1 url:string` (presigned S3 PUT).

**`Files_FilePlayRequest`** — empty. **`Files_FilePlayResponse`** — `1 url:string` (playback URL,
fetched on demand; not persisted client-side).

**`Files_FileRequest`** / **`Files_FileDeleteRequest`** — `1 uuid:string`.
**`Files_FileDeleteResponse`** — empty. **`Files_SuccessResponse`** — `1 success:bool`.

**`Files_FileUploadedStatusRequest`** — the standard **Amazon SNS HTTP-notification** envelope
(`1 Type, 2 MessageId, 3 TopicArn, 4 Subject, 5 Token, 6 Message, 7 SubscribeURL, 8 Timestamp,
9 SignatureVersion, 10 Signature, 11 SigningCertURL, 12 UnsubscribeURL` — all string). This is the
server-side hook: the storage bucket notifies the backend via SNS when a presigned upload completes,
and the backend then flips the file to "uploaded" so `files/upload/status/{uuid}` returns `success=true`.

### Upload flow (end to end)

1. **Request presigned URL** — `POST files/upload/request` with metadata → `url`. MIME detected
   locally (sniffs up to 4500 bytes; falls back to `application/octet-stream`, then `audio/mp3`).
   Validation errors (`files_title_required`, `files_uuid_required`, `files_invalid_content_type`,
   `files_file_too_large`, `files_storage_limit_exceeded`, `files_invalid_user`) are raised here.
2. **PUT bytes to the presigned S3 URL** (NOT api host) — `PUT`, `Content-Type: <fileType|audio/mp3>`,
   no Bearer token (URL is self-signed), 30s timeout, one connection/host. Background `URLSession`s:
   WiFi-only `au.com.shiftyjelly.PCUploadBackgroundSession` and cellular `...PCUploadManualSession`.
3. **Artwork (optional, only if `colour==0`)** — `POST files/upload/image` → presigned url → `PUT` the
   JPEG from `<Documents>/custom_images/<uuid>.jpg`. Then client marks image uploaded.
4. **Confirm** — ~1s after the byte-PUT completes with no error, poll `GET files/upload/status/{uuid}`;
   `success=true`→local `uploaded`, `false`/error→`uploadFailed`.
5. **Sync edits** — `POST files` pushes later metadata edits (sparse `FileUpdate`s); `GET files`
   re-syncs the authoritative list + quota, reconciling deletions.
6. **Playback** — `GET files/play/{uuid}` returns a fresh URL each time (not cached).
7. **Delete** — `DELETE files/{uuid}` (file) or `DELETE files/image/{uuid}` (artwork only).

Local upload statuses (client-side, informative): `notUploaded=1, queued=2, uploading=3,
uploadFailed=4, uploaded=5, waitingForWifi=6, missing=7, deleteFromCloudPending=8,
deleteFromCloudAndLocalPending=9`.

### `files_*` error taxonomy

JSON envelope `{ "errorMessageId": "files_...", "error": "..." }` (see §5.3 for the full table).
The client keys on `errorMessageId` regardless of HTTP status, but a re-implementation should use:
validation (`files_title_required`, `files_uuid_required`, `files_invalid_content_type`,
`files_file_too_large`) → `400`; `files_storage_limit_exceeded`/`files_invalid_user` → `403`;
`files_upload_failed_generic` → `500`. Emitted primarily on `files/upload/request` and
`files/upload/image`.

> **`colour`** is a small palette index, not RGB. `0` = "no custom colour" and signals the client may
> upload a custom image instead. There is no separate `tintColor` field on the wire.

*Sources: `files.pb.swift`, `ApiServerHandler+UserFiles.swift`, `Upload/*`, `MimetypeHelper.swift`,
the `Upload*`/`RetrieveCustomFiles`/`RetrieveFileUsage`/`RetrieveFileUploadStatus` tasks.*

---

## 12. Search, Ratings, Stats, Bookmarks, Subscriptions, Sharing, Feedback

*Mixed hosts and wire formats. `api` host = protobuf + Bearer; `cache`/`search`/`sharing` = JSON.*

### 12.1 Search (four endpoints, three hosts)

| Endpoint | Host | Method | Auth | Body / query | Response |
|---|---|---|---|---|---|
| `search/combined` | cache | POST | none | `{"term":"…"}` | flat `results[]` (podcasts+episodes) |
| `podcasts/search` | refresh | POST | none | `{"q":"…", + standard params}` | pollable `PodcastSearchResponse` |
| `autocomplete/search` | search | GET | none | `?q=…` | heterogeneous `results[]` |
| `episode/search` | cache | POST | none | `{"term":"…"}` | `{"episodes":[…]}` |

**`search/combined`** — response `{ "results": [ {type:"podcast"|"episode", uuid, title, published_date?(ISO),
duration?, podcast_uuid?, podcast_title?, author?, explicit?} ] }`. Array order = ranking; `type`
discriminates; unknown types dropped.

**`podcasts/search`** (refresh host, **pollable**) — body carries the full standard param set (§13.0) plus
`q`. Response `{status:"ok"|"poll"|"failed", message, result:{ podcast?, search_results?[], poll_uuid? }}`.
**If `status=="poll"` the client re-polls on a fixed backoff `2, 2, 5, 5, 5, 5, 10` seconds (~34s total)
then fails.** The backend must respond synchronously or honor this loop. `podcast` (a
`PodcastInfo`: `uuid, title, author, collection_id→iTunesId, description→shortDescription,
explicit→isExplicit`) is returned as the sole result when the term resolved to a direct feed; else
`search_results[]`.

**`autocomplete/search`** — `{ "results": [ {type:"term", value:"text"} | {type:"podcast",
value:{uuid,title,author,explicit}} ] }`. Polymorphic `value`; unknown types preserved as strings.

**`episode/search`** — `{ "episodes": [ {uuid, title, published_date(ISO,required), duration?,
podcast_uuid, podcast_title, state?:"normal"|"archived"|"unavailable"} ] }`. (Note: the real path is
`episode/search`, not `mobile/podcast/episode/search`; the latter is the *within-one-podcast* search in
§13.) `Api_SearchPodcastsRequest{1 term:string}` exists in the proto but the client uses the JSON forms.

### 12.2 Podcast ratings (split across two hosts)

- **`GET cache/podcast/rating/{podcastUuid}`** (no auth) → `{ "total": int, "average": double(1–5) }`. `404` = no rating.
- **`GET api/user/podcast_rating/list`** (Bearer) → `Api_PodcastRatingsResponse{1 podcast_ratings:repeated
  Api_PodcastRating}`. **`Api_PodcastRating`** — `1 podcast_uuid:string, 3 modified_at:Timestamp,
  4 podcast_rating:uint32 (1–5)` (field 2 reserved).
- **`POST api/user/podcast_rating/add`** (Bearer) → `Api_PodcastRatingAddRequest{1 podcast_uuid:string,
  2 podcast_rating:uint32}`; response body ignored, `200` = success.
- **`POST api/user/podcast_rating/show`** (Bearer) → `Api_PodcastRatingShowRequest{1 podcast_uuid:string}`
  → `Api_PodcastRating`.

### 12.3 Listening stats — `POST api/user/stats/summary` (Bearer)

Request `Api_StatsRequest` — `1 device_id:string (empty = account-wide "full" stats), 2 time_silence_removal:int32,
3 time_skipping:int32, 4 time_intro_skipping:int32, 5 time_variable_speed:int32, 6 time_listened:int32,
7 device_type:int32(=1)`.
Response `Api_StatsResponse` (cumulative seconds) — `1 time_silence_removal:int64, 2 time_skipping:int64,
3 time_intro_skipping:int64, 4 time_variable_speed:int64, 5 time_listened:int64, 6 times_started_at:Timestamp`.
The app displays local deltas + server totals.

### 12.4 Bookmarks — `POST api/user/bookmark/list` (Bearer)

Request `Api_BookmarkRequest` (sent empty) — `1 podcast_uuid:string, 2 episode_uuid:string,
3 time:Int32Value, 4 title:StringValue`.
Response `Api_BookmarksResponse{1 bookmarks:repeated Api_BookmarkResponse}`.
**`Api_BookmarkResponse`** — `1 bookmark_uuid:string, 2 podcast_uuid:string, 3 episode_uuid:string,
5 time:int32 (seconds), 6 title:string, 7 created_at:Timestamp` (field 4 unused). Write path uses
`Api_SyncUserBookmark` (see §9.3), with per-field `*_modified` timestamps for LWW.

### 12.5 Subscriptions / IAP (protobuf schema — implement for cross-platform parity)

> These messages are fully defined in the proto but **not wired to any endpoint in this iOS client** —
> the app's live entitlement path is StoreKit + account sync. Implement them to spec so Android/Web (and
> future iOS) work; suggested paths below follow Pocket Casts naming.

- **Eligibility** `POST subscription/check_eligible` — `Api_CheckEligibleRequest{oneof store_receipt:
  android|apple|web}` → `Api_CheckEligibleResponse{1 platform:int32, 2 eligible:bool}`.
  `SubscriptionPlatform`: none=0, iOS=1, android=2, web=3, gift=4.
- **Purchase validation** `POST subscription/purchase/{apple|android|web}`:
  - `Api_SubscriptionsPurchaseAppleRequest{1 receipt:string, 2 newsletter_opt_in:bool}`
  - `Api_SubscriptionsPurchaseAndroidRequest{1 purchase_token:string, 2 sku:string, 3 newsletter_opt_in:bool}`
  - `Api_SubscriptionsPurchaseWebRequest{1 transaction_id:string, 2 email:string, 3 paddle_user_id:int64,
    4 product_id:string, 5 newsletter_opt_in:bool, 6 subscription_id:int64}`
- **Status** `Api_SubscriptionsStatusResponse` — `1 paid:int32, 2 platform:int32, 3 expiry_date:Timestamp,
  4 auto_renewing:bool, 5 gift_days:int32, 6 cancel_url:string, 7 update_url:string, 8 frequency:int32,
  9 web:Api_SubscriptionsWebStatusResponse, 10 subscriptions:repeated Api_SubscriptionResponse, 11 type:int32,
  12 index:int32, 13 web_status:int32, 14 tier:string ("plus"/"patron"), 15 features:Api_Features,
  16 created_at:Timestamp, 17 installment_based:bool`.
- **`Api_SubscriptionResponse`** — `1 platform:int32, 2 type:int32, 3 frequency:int32, 4 auto_renewing:bool,
  5 expiry_date:Timestamp, 7 cancel_url:string, 8 update_url:string, 9 web:…WebStatusResponse, 10 plan:string,
  11 index:int32, 12 gift_days:int32, 13 paid:int32, 14 web_status:int32, 15 bundle_uuid:string,
  16 podcasts:repeated Api_PodcastPair, 17 eligible:bool, 18 next_payment:Api_PaymentResponse, 19 tier:string`
  (field 6 unused).
- **`Api_PodcastPair`** — `1 master_podcast_uuid:string, 2 user_podcast_uuid:string`.
  **`Api_PaymentResponse`** — `1 payment_date:string (deprecated), 2 amount:double, 3 currency:string,
  4 date:Timestamp`. **`Api_Features`** — `1 remove_banner_ads:bool, 2 remove_discover_ads:bool`.
  **`Api_SubscriptionsWebStatusResponse`** — `1 monthly:int32, 2 yearly:int32, 3 trial:int32,
  4 web_status:int32, 5 plus:Api_SubscriptionsWebProduct, 6 patron:Api_SubscriptionsWebProduct`.
  **`Api_SubscriptionsWebProduct`** — `1 monthly:int32, 2 yearly:int32, 3 trial_days:int32`.
- **Cancel** `POST subscription/cancel` — `Api_CancelUserSubscriptionRequest{1 bundle_uuid:string}`.
- **Supporter/bundle** — `Api_PodcastSubscriptionCheckRequest{1 user_uuid, 2 podcast_uuid, 3 platform:int32}`
  → `Api_PodcastSubscriptionCheckResponse{1 paid:bool, 2 user_exists:bool}`;
  `Api_BundleUserRequest{1 user_uuid, 2 bundles:repeated string}` → `Api_BundleUserResponse{1 user_exists:bool,
  2 paid:bool}`.
- **Promotions (schema only)** — `Api_PromotionCode{1 code:string}`, `Api_Promotion{1 code, 2 description,
  3 starts_at, 4 ends_at (all string)}`.

### 12.6 Sharing — `POST sharing/share/list`

**No bearer auth — legacy HMAC-style signature:** `datetime` = current time `yyyyMMddHHmmss`;
`h` = lowercase-hex **SHA-1** of `"<datetime><sharedCredential>"` (a shared secret baked into the client).
Body `{ "title", "description"?, "podcasts":[{"uuid":…}], "datetime", "h" }` →
`{ "status":"ok", "result":{ "share_url":"https://lists.pocketcasts.com/…" } }`.
**Retrieve** a shared list: `GET <listUrl>` (no auth) → `PodcastList{ title?, description?→listDescription,
podcasts:[{title?, uuid?, description?→podcastDescription, author?, collection_id→iTunesId}] }`.
Related refresh-host shapes: `ShareListResponse{status, message, result:{time?, podcast?:SharedPodcast,
shared_episode?:RefreshEpisode}}`.

### 12.7 Suggested folders — `POST cache/podcast/suggest_folders` (no auth)

Body `{ "language":"en", "uuids":[…] }` → a **flat JSON map** `{ "<folder name>": ["<podcast uuid>", …] }`
(decoded as `[String:[String]]`). Note: sent via `ApiBaseTask` so `Content-Type: application/octet-stream`
despite the JSON body — the server must accept JSON under that content type. Proto equivalents
(`Api_SuggestedFolder{1 name, 2 podcast_uuids:repeated string}`) exist but this endpoint uses JSON.
Folder sync (protobuf, related): `Api_PodcastFolderRequest{1 version, 2 model, 3 folder:Api_PodcastFolder,
4 podcasts:repeated string}`; `Api_PodcastFolderSortRequest{1 version, 2 model, 3 podcasts:repeated
Api_PodcastFolderSorting, 4 folders:repeated …}`; `Api_PodcastFolderSorting{1 uuid, 2 position:int32}`.

### 12.8 Support feedback — `POST api/{support|anonymous}/feedback`

Path is `support/feedback` when logged in (Bearer) or `anonymous/feedback` when not. Request
`Api_SupportFeedbackRequest` — `1 message:string, 2 email:string, 3 subject:string, 4 debug:string,
5 inbox:string` (`inbox` routes to a support queue, `subject` = ticket subject, `debug` = optional
diagnostics). Response ignored; `200` = success.

### Gotchas

1. `podcasts/search` is pollable (`status:"poll"`, fixed backoff ~34s).
2. Two podcast-result shapes coexist: modern `{uuid,title,author,explicit}` (cache/combined/autocomplete)
   vs legacy `PodcastInfo` (`collection_id`, `description`) (refresh host).
3. Episode text search path is `episode/search` (whole-library) vs `mobile/podcast/episode/search`
   (within one podcast, §13).
4. Ratings split hosts: aggregate stars from unauthenticated cache; per-user ratings from authenticated api.
5. Stats: response int64, request int32; `device_id=""` = account-wide.
6. Sharing uses SHA-1 signature, not bearer.

*Sources: `Search/*`, `PodcastSearchOperation.swift`, `MainServerHandler.swift`, `Ratings/*`,
`Retrieve{Ratings,Stats,Bookmarks}Task`, `UserPodcastRatingTask`, `SuggestedFolderTask`,
`SupportFeedbackTask`, `StatsManager.swift`, `Supporter Podcasts/*`, `SharingServerHandler.swift`,
`ServerStructs.swift`, `ServerEnums.swift`, `api.pb.swift`.*

---

## 13. Podcasts, Refresh, Cache, Discover & Recommendations

*Hosts: **refresh** (JSON, mostly anonymous), **cache** (JSON, mixed auth), **static/discover** (static
JSON), **api** (protobuf recommendations). This is podcast/episode metadata delivery — the read side of
the catalog.*

### 13.0 Refresh-service standard params

Every refresh-host request carries device-identification params (as JSON body fields or query items):
`device` (install UUID), `dt="1"` (iOS), `v="1.7"` (parser version), `av` (app version), `m` (OS version),
`l` (language), `c` (region). Referenced below as "standard params."

### 13.1 Refresh service (`refresh.pocketcasts.com`)

**`POST user/update`** (Bearer) — the primary polling endpoint: given subscriptions + last-known latest
episode, return newer episodes per podcast. `reloadIgnoringCacheData`. Body: standard params +
`{ podcasts:"uuid,uuid,…" (comma-joined subs), last_episodes:"epUuid,…" (positional; per-podcast
forceRefreshFrom|latestEpisodeUuid|""), push_messages_on:"101…" (one char per podcast, no separator),
push_sound:"11", push_on:"true"|"false", push_token?:"<apns>" }`.
Response (snake_case → camelCase via `.convertFromSnakeCase`):
```json
{ "status":"ok", "message":null,
  "result": { "podcast_updates": { "<podcastUuid>": [
    { "title","uuid","url","description","dd"(detailed desc),"file_type","size_in_bytes":int64,
      "duration_in_secs":double,"ep_type"("full"/"trailer"/"bonus"),"ep_season":int64,
      "ep_number":int64,"published_at":ISO } ] } } }
```
`success()` iff `status=="ok"`. Client dedups against local DB and inserts; only the first 10 new
episodes trigger metadata HEADs (§13.5).

**`POST podcasts/refresh`** (anon) — ask the server to re-poll one podcast's RSS feed. Body: standard
params + `{podcast_uuid}`. Body ignored; `200` = success.

**`POST podcasts/show`** (anon) — resolve iTunes collection id → podcast. Body: standard params +
`{"id":<iTunesId int>}`. Response `PodcastSearchResponse` (§12.1 shape); client reads `result.podcast.uuid`.

**`POST import/opml`** (anon) — resolve RSS feed URLs (and/or poll uuids) to podcast uuids.
`reloadIgnoringCacheData`. Body: standard params + `{ urls:[…], poll_uuids:[…] }`. Response
`{ status, message, result:{ uuids:[resolved], poll_uuids:[still-processing → resubmit], failed:int } }`.

**`POST import/export_feed_urls`** (anon) — podcast uuids → feed URLs. Body: standard params +
`{ uuids:[…] }` → `{ status, message, result:{ "<uuid>":"<feedUrl>", … } }`.

**`GET api/v1/update_podcast`** (anon, **long-poll**) — trigger + await a server-side single-podcast
update. Query: `podcast_uuid=…&last_episode_uuid=…`. `200` = done; **`202 Accepted`** must include
`Location` (poll URL) + `retry-after` (seconds) headers — the client sleeps `retry-after`, GETs `Location`,
repeats while `202`. Body not parsed.

### 13.2 Cache service (`cache.pocketcasts.com`)

**Shared podcast JSON envelope** (used by full/findbyepisode):
```json
{ "estimated_next_episode_at":ISO, "episode_frequency":"weekly", "refresh_allowed":bool,
  "podcast": { "uuid","title","author","url"(podcastUrl),"description","description_html","category",
    "show_type":"episodic"|"serial","paid":int(>0⇒isPaid),"licensing":int,"is_private":bool,
    "explicit":bool|int,"fundings":[{"url"}](first→fundingURL),
    "episodes":[ { "uuid","title","url"(downloadUrl),"file_type","file_size":int64(sizeInBytes),
      "duration":double,"published":ISO,"number":int64,"season":int64,"type"(episodeType),
      "has_generated_transcript":bool? } ] } }
```
Dates ISO-8601. `explicit` accepted as bool or int(>0). `show_type=="serial"` drives season grouping.
A podcast with no `episodes` array is rejected.

**`GET mobile/podcast/full/{uuid}`** (Bearer) — full podcast + all episodes. Add path uses
`useProtocolCachePolicy` and stores the `Last-Modified` header per podcast. Refresh path uses
`reloadIgnoringCacheData` + `If-Modified-Since: <stored Last-Modified>`; **`304` = unchanged**. Response =
envelope above.

**`GET mobile/podcast/findbyepisode/{podcastUuid}/{episodeUuid}`** (anon, sync, 10s) — resolve a
missing podcast/episode from an episode uuid. Response = envelope (episodes usually just the one). `304` = no data.

**`GET mobile/episode/url/{podcastUuid}/{episodeUuid}`** (Bearer) — resolve playable media URL. Response
is **plain-text UTF-8** (the URL string), not JSON. `200` + non-empty = success.

**`GET mobile/show_notes/full/{podcastUuid}`** (anon) — rich metadata for all episodes of a podcast.
Uses a dedicated 100 MB disk `URLCache` and revalidates with **both** `If-None-Match:<etag>` and
`If-Modified-Since:<lastModified>` — server must support ETag and Last-Modified and return `304` when
unchanged (client then serves cached body). Response:
```json
{ "podcast": { "uuid", "episodes": [ { "uuid",
  "show_notes":"<html>", "image":"url",
  "chapters":[{"start_time":double,"title"?,"end_time"?:double}],
  "chapters_url":"url"(external Podcast Index),
  "transcripts":[{"url","type","language"?}],
  "pocket_casts_transcripts":[{…same…}] } ] } }
```
Decoded `.convertFromSnakeCase`. Missing show notes → constant `"Unable to find show notes for this episode."`.

**`POST mobile/podcast/episode/search`** (Bearer) — search episodes **within one podcast**. Body
`{ "podcastuuid":"…", "searchterm":"…" }` (literal lowercase keys). Response `{ "episodes":[{"uuid"},…] }`
(uuids only). *(Distinct from the whole-library `episode/search` in §12.1.)*

**`POST podcast/suggest_folders`** — see §12.7.

### 13.3 Discover feed (`static.pocketcasts.com/discover/`)

**`GET ios/content_v3.json`** (or `content_v2.json` when the `recommendations` flag is off) — top-level
layout. Anonymous by default; per-item source fetches use Bearer when the item's `authenticated==true`.
Client-side `URLCache` ("discovery", 5 MB) honoring `Expires`/`Cache-Control`. Decoded with
`dateDecodingStrategy=.iso8601`.
```json
{ "layout":[DiscoverItem,…],
  "regions":{ "us":{"name","code","flag"}, … },
  "region_code_token":"[regionCode]", "region_name_token":"[regionName]", "default_region_code":"us" }
```
`region_*_token` are placeholders substituted into item `source` URLs before fetching.

**`DiscoverItem`** — `id, uuid, title, type (list discriminator), summary_style, expanded_style,
summaryItemCount (literal camelCase key), source (URL to fetch contents), authenticated:bool,
sponsored:bool, sponsored_podcasts:[{position,source}], expanded_top_item_label, curated:bool,
regions:[string], popular:[int], category_id:int, datetime:ISO, sponsored_ids:[int]`.

**Dynamic source shapes** (fetched from `DiscoverItem.source`, decoded by item `type`):
- `PodcastList` — `{ title, description, podcasts:[DiscoverPodcast], datetime }`.
- `DiscoverPodcast` — `{ title, author, description→shortDescription, uuid, website, itunes→iTunesId(string),
  explicit→isExplicit }`.
- `[PodcastNetwork]` — `[{ title, source, description, image_url→imageUrl, color }]`.
- `[DiscoverCategory]` — `[{ id:int, name, source, icon, popularity, source_onboarding→sourceOnboarding }]`.
- `DiscoverCategoryDetails` — `{ title, description, podcasts:[DiscoverPodcast],
  promotion:{promotion_uuid, podcast_uuid, title, description} }`.
- `PodcastCollection` — `{ list_id, title, subtitle, author, description, short_description,
  podcasts:[DiscoverPodcast], episodes:[DiscoverEpisode], podroll:[DiscoverPodcast], collection_image,
  collection_rectangle_image, colors:{onLightBackground,onDarkBackground}, web_title, web_url,
  collage_images:[{key,image_url}], header_image, feature_image, datetime }`.
- `DiscoverEpisode` — `{ title, duration:int, url, uuid, podcast_uuid→podcastUuid, podcast_title→podcastTitle,
  type ("trailer" flags a trailer), published:ISO, season:int, number:int }`.

### 13.4 Image, color & recommendations

- **Artwork:** `GET discover/images/{size}/{uuid}.jpg` — valid sizes `130,140,200,210,280,340,400,420,680,960`.
- **Default user-episode artwork:** `GET discover/images/artwork/{light|dark}/{size}/{color}.png`.
- **Color metadata:** `GET discover/images/metadata/{uuid}.json` → `{ "colors":{ "background":"#…",
  "tintForLightBg":"#…", "tintForDarkBg":"#…" } }` (all three required).
- **Recommend episode (protobuf, api host):** `POST discover/recommend_episodes` (Bearer) —
  `Api_BasicRequest{1 v, 2 m}` → `Api_EpisodesResponse{1 total:int32, 2 episodes:repeated Api_EpisodeResponse}`.
  Client reads `episodes.first`'s `uuid`/`podcastUuid`.
- **Related podcasts (JSON, api host):** `GET recommendations/podcast/{podcastUUID}?country=<region>`
  (anon) → a `PodcastCollection` (§13.3). `304` → no update.

### 13.5 Episode media metadata HEAD (third-party host)

Not a Pocket Casts endpoint: the client issues `HEAD <episode.downloadUrl>` (`Pocket Casts` UA, 20s) for
the first 10 new episodes after a refresh, and reads `Content-Type` (→ fileType; `video*` overrides) and
`Content-Length` (→ sizeInBytes, only if > 150 KiB and changed). The media/redirect host should return
accurate `Content-Type`/`Content-Length` on HEAD.

### 13.6 Related podcast/folder protobuf (api host, for parity)

`Api_ApiPodcastResponse{1 uuid, 2 title, 3 author, 4 description, 5 url, 6 slug}`;
`Api_ApiPodcastListResponse{1 podcasts:repeated …}`; `Api_WebFeedCreateRequest{1 url:string,
2 pollUuid:StringValue}` (add custom RSS feed) → `Api_WebFeedCreateResponse{oneof: podcast:Api_ApiPodcastResponse
| pollUuid}` (client polls when only pollUuid returns). Library sort-order enum differs client vs server:
server `dateAddedNewestToOldest=0, titleAtoZ=1, episodeDateNewestToOldest=2, custom=3, recentlyPlayed=4`.

### 13.7 Caching contract summary

| Endpoint | Conditional mechanism | On unchanged |
|---|---|---|
| `mobile/podcast/full/{uuid}` | `If-Modified-Since` ← prior `Last-Modified` (echo verbatim) | `304` |
| `mobile/show_notes/full/{uuid}` | `If-None-Match`←`ETag` **and** `If-Modified-Since`←`Last-Modified` | `304` (client serves cache) |
| discover static JSON | `Expires`/`Cache-Control` | client serves cache until expiry |
| `recommendations/podcast/{uuid}` | none sent; handles `304` | optional |
| `images/metadata/{uuid}.json` | standard `URLCache` background revalidation | honor HTTP caching |

Cache-bypassing (`reloadIgnoringCacheData`): `user/update`, `podcasts/refresh`, `import/opml`,
`import/export_feed_urls`, `api/v1/update_podcast`, `recommendations/podcast/*`, `findbyepisode/*`.
`useProtocolCachePolicy`: `podcasts/show`, `mobile/episode/url`, `mobile/podcast/episode/search`.

*Sources: `MainServerHandler.swift`, `RefreshManager.swift`, `RefreshOperation.swift`,
`ServerPodcastManager(+Update).swift`, `CacheServerHandler.swift`, `ShowInfoDataRetriever.swift`,
`DiscoverServerHandler.swift`, `RecommendationHelper.swift`, `RecommendEpisodesTask.swift`,
`MetadataTask.swift`, `EpisodeHeader.swift`, `PodcastHeader.swift`, `ServerStructs.swift`,
`ServerConverter.swift`, `Episode+Populate.swift`, `api.pb.swift`.*

---

## 14. Protobuf schema conventions

The api host and files host speak proto3. To re-derive or verify field numbers against the client,
read the generated Swift at `Modules/Sources/PocketCastsServer/Private/Protobuffer/api.pb.swift`
(package `api.`, Swift prefix `Api_`) and `files.pb.swift` (package `files.`, prefix `Files_`).

**How to read field numbers from the generated Swift.** Each message has a `decodeMessage` and a
`traverse` function containing a `switch` on the field number:

```swift
public mutating func decodeMessage<D>(decoder: inout D) throws {
  while let fieldNumber = try decoder.nextFieldNumber() {
    switch fieldNumber {
    case 1: try decoder.decodeSingularStringField(value: &self.email)
    case 3: try decoder.decodeSingularStringField(value: &self.scope)
    ...
```

The `case N:` is the wire field number; the assigned property and its `decodeSingular*/decodeRepeated*`
method give the type. Gaps in the sequence (e.g. named-settings fields 10 and 13, or field 3 in
`Api_UserChangePasswordRequest`) are **reserved** — do not reuse them.

**Type mapping.**

| Client (generated Swift) | proto3 type | Notes |
|---|---|---|
| `String` | `string` | |
| `Int32`/`UInt32` | `int32`/`uint32` | |
| `Int64` | `int64` | Many durations/positions travel as int64 though stored as seconds |
| `Bool` | `bool` | |
| `Double` | `double` | playback speed, etc. |
| `Google_Protobuf_BoolValue` | `google.protobuf.BoolValue` | **presence-tracking wrapper** — distinguishes "unset" from `false` |
| `Google_Protobuf_Int32Value`/`Int64Value`/`StringValue`/`DoubleValue` | corresponding `*Value` wrappers | used for sparse/partial updates |
| `Google_Protobuf_Timestamp` | `google.protobuf.Timestamp` | seconds+nanos since epoch; used for publish/created/modified dates |
| `oneof` | `oneof` | e.g. `Api_Record`, `Api_YearHistoryResponse` — exactly one case set |

**Wrapper-vs-scalar is semantically load-bearing.** The sync engine and file-metadata patches use
wrapper types precisely so the client can send *only the fields that changed* (a wrapper that is unset =
"don't touch this field"; a bare scalar `0`/`""`/`false` = "set to this value"). A re-implementation MUST
preserve the wrapper-vs-scalar choice per field, or partial updates and last-write-wins conflict
resolution will silently corrupt data.

**Two clock conventions coexist:** `google.protobuf.Timestamp` for calendar dates (publish/created), and
**int64 epoch-milliseconds** for sync cursors and per-field `*_modified` markers. Match each field's
convention exactly.

**Success = protobuf, error = JSON.** On the api host, a `200` body is the protobuf response message; a
non-`200` body is the JSON error envelope `{ "errorMessageId", "error" }` (§5). The one exception is
`user/exchange_sonos`, whose success body is JSON.

**Regenerating.** Per `CLAUDE.md`, protos are regenerated with
`mise run generate:proto /path/to/pocketcasts-api/api/modules/protobuf/src/main/proto`. The backend team
should own the canonical `.proto` files; the two `.pb.swift` files in this repo are the authoritative
snapshot of the contract the shipping client expects.

---

## 15. Implementation checklist

A backend is client-complete when all of the following hold. Ordered roughly by build priority.

### Phase 1 — auth & identity (unblocks everything)
- [ ] `user/register`, `user/login`, `user/forgot_password` with the exact `login_*` error codes (§5.3).
- [ ] `user/token` returning the **`Api_TokenLoginResponse`** shape (access + refresh token, `is_new`).
- [ ] `device/authorize` + `user/token` device-code grant (`authorization_pending` polling).
- [ ] Bearer-token validation on every authenticated endpoint; return **`401`** for expired/invalid
      tokens so the client's drop-token-and-retry-once flow works (§4.3). Return `403` for permission
      failures (client does not retry those).
- [ ] `user/change_email`, `user/change_password`, `user/delete_account`, `user/exchange_sonos`.

### Phase 2 — sync core (the product)
- [ ] Account-level `last_modified` watermark in **int64 epoch-ms**; `user/last_sync_at` and
      `user/sync/update` (bidirectional `Api_Record` up/down).
- [ ] Full-sync reads: `user/podcast/list` (+folders), `user/podcast/episodes`, `user/playlist/list`.
- [ ] **Per-field `modified_at`** persistence for episodes, bookmarks, named settings, podcast settings
      → last-write-wins (§9.8). Preserve wrapper-vs-scalar semantics (§14).
- [ ] `user/named_settings/update` with the full field map (§9.7), `changed`/`modified_at` protocol.
- [ ] Honor the two UUID sentinels; preserve playlist `original_uuid` case; support the `_global` settings split.

### Phase 3 — queues & playback state
- [ ] `up_next/sync` action-log merge + `serverModified` cursor; **return `304` when unchanged** and never
      spuriously empty the queue (>75% deletion triggers a client error).
- [ ] `history/sync` (add/delete/clearAll, `lastCleared`, most-recent-first, 100-item apply cap).
- [ ] `sync/update_episode`, `sync/update_episode_star`, `starred/list`.

### Phase 4 — catalog & discovery
- [ ] Refresh service: `user/update` (batch new-episode poll), `podcasts/refresh`, `podcasts/show`,
      `import/opml` (+`poll_uuids`), `import/export_feed_urls`, `api/v1/update_podcast` (**`202` long-poll
      with `Location` + `retry-after`**).
- [ ] Cache service: `mobile/podcast/full/{uuid}` (+`If-Modified-Since`/`304`), `findbyepisode/...`,
      `mobile/episode/url/...` (plain-text URL body), `mobile/show_notes/full/{uuid}` (ETag **and**
      Last-Modified), `mobile/podcast/episode/search`.
- [ ] Discover static JSON (`ios/content_v3.json` + dynamic source shapes) with `Expires`/`Cache-Control`.
- [ ] Artwork/color image endpoints; `recommend_episodes` (protobuf); `recommendations/podcast/{uuid}`.

### Phase 5 — files, search & the rest
- [ ] User Files: `files`, `files/upload/request`, `files/upload/image`, `files/upload/status/{uuid}`,
      `files/play/{uuid}`, `files/{uuid}`, `files/image/{uuid}`, `files/usage/` + presigned-URL byte
      storage + SNS upload-confirmation pipeline + `files_*` error codes (§11).
- [ ] Search: `search/combined`, `podcasts/search` (**pollable**), `autocomplete/search`, `episode/search`.
- [ ] Ratings (`podcast/rating/{uuid}`, `user/podcast_rating/{list,add,show}`), stats
      (`user/stats/summary`), bookmarks (`user/bookmark/list`).
- [ ] Sharing (`share/list` with SHA-1 signature), suggested folders, support feedback.
- [ ] Subscriptions/IAP protobuf endpoints (§12.5) for cross-platform parity.

### Cross-cutting
- [ ] Serve the production hostnames in §2 (or repoint the app).
- [ ] Success bodies protobuf (api host) / JSON (others); error bodies JSON `{errorMessageId,error}`.
- [ ] Honor `X-User-Region` / `X-App-Language` for regionalized content.
- [ ] Match every protobuf field number and wrapper-vs-scalar choice exactly against the two `.pb.swift`
      files (§14) — these are the authoritative contract.
- [ ] Own canonical `.proto` files; treat the client's generated Swift as the frozen snapshot to match.

### Open questions to confirm against the real backend (not fully determined by the client)

The client only *reads* responses, so a few things are inferred and should be confirmed with a captured
production trace or the original backend team:

1. **Exact HTTP status codes** for validation/business errors (the client keys on `errorMessageId`, not
   status — see §5.2, §11).
2. **`Api_UserTokenResponse` vs `Api_TokenLoginResponse`** on `user/token` — the client decodes the latter;
   confirm the server emits it.
3. **Subscription/IAP endpoint paths** (§12.5) — messages are defined but no iOS call site exists.
4. **Year-history endpoint path** — `Api_YearHistoryRequest/Response` exist but are wired elsewhere.
5. **Whether `podcasts/search` is synchronous or truly pollable** in the target backend (client supports both).

---

*This document was produced by reverse-engineering the shipping iOS client. It captures the contract the
client depends on; it does not describe the original backend's internal architecture, storage, or
business rules beyond what the client observably relies on. Validate against a production capture before
go-live.*
