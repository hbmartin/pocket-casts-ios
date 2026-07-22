# Server, API & Remote Interaction Surface Area

This document maps **every way the Pocket Casts iOS app talks to a remote server** — first‑party Pocket Casts services, podcast/CDN hosts, and third‑party SDKs.

It is intended as a reference for engineers and security reviewers: where requests go, how they are authenticated, what they carry, and what triggers them.

> Scope note: the networking layer lives almost entirely in the **`PocketCastsServer`** Swift package (`Modules/Sources/PocketCastsServer/`). The main app (`podcasts/`) and extensions add downloads, image loading, analytics SDKs, push registration, transcripts, and web links. Both are covered here.

> **Building a backend?** This document is a *surface map* (what talks to what). The separate backend re-implementation spec was removed 2026-07-12 (program decision #59): this fork's direction is local-first operation with the production service as the optional sync layer, so no first-party backend re-implementation is planned. The protobuf schemas in `Modules/Sources/PocketCastsServer/Private/Protobuffer/` remain the wire-format reference.

---

## Table of Contents

1. [Architecture overview](#1-architecture-overview)
2. [Hosts & environments](#2-hosts--environments)
3. [Authentication & tokens](#3-authentication--tokens)
4. [Request infrastructure](#4-request-infrastructure)
5. [API endpoint reference (`api` host)](#5-api-endpoint-reference-api-host)
6. [Sync subsystem](#6-sync-subsystem)
7. [Refresh subsystem (`refresh` host)](#7-refresh-subsystem-refresh-host)
8. [Discover (`static` host)](#8-discover-static-host)
9. [Search](#9-search)
10. [Cache & metadata (`cache` host)](#10-cache--metadata-cache-host)
12. [Sharing & curated lists](#12-sharing--curated-lists)
13. [Stats](#13-stats)
14. [Ratings](#14-ratings)
15. [Recommendations & suggested folders](#15-recommendations--suggested-folders)
16. [Episode downloads (main app)](#16-episode-downloads-main-app)
17. [Image & artwork loading (main app)](#17-image--artwork-loading-main-app)
18. [Transcripts & chapters (main app)](#18-transcripts--chapters-main-app)
19. [Push notifications](#19-push-notifications)
20. [Analytics & telemetry](#20-analytics--telemetry)
22. [OPML import/export & status page](#22-opml-importexport--status-page)
23. [Protocol Buffers catalog](#23-protocol-buffers-catalog)
24. [Server notifications (NSNotification)](#24-server-notifications-nsnotification)
25. [Persistence keys (Keychain / UserDefaults)](#25-persistence-keys-keychain--userdefaults)
26. [Complete host inventory](#26-complete-host-inventory)
27. [File map](#27-file-map)

---

## 1. Architecture overview

```
┌──────────────────────────────────────────────────────────────────────┐
│  podcasts/ (main app + extensions)                                     │
│   • DownloadManager        → podcast CDN audio/video                   │
│   • ImageManager (Kingfisher) → static.pocketcasts artwork   │
│   • Analytics adapters     → Bitdrift, TelemetryDeck                   │
│   • NotificationsHelper    → APNs registration                         │
│   • Transcript / Chapter retrievers → per-episode URLs                 │
└───────────────────────────────┬──────────────────────────────────────┘
                                 │ depends on
┌───────────────────────────────▼──────────────────────────────────────┐
│  Modules/Sources/PocketCastsServer  (the networking layer)            │
│                                                                        │
│   ApiServerHandler ── API Tasks (ApiBaseTask) ──► api.pocketcasts.com  │
│   SyncManager / SyncTask / UpNext / History / Settings ──► api host    │
│   RefreshManager / MainServerHandler ──► refresh.pocketcasts.com       │
│   DiscoverServerHandler ──► static.pocketcasts.com/discover            │
│   CacheServerHandler / ShowInfoDataRetriever ──► cache.pocketcasts.com │
│   Search tasks ──► refresh / cache / search hosts                      │
│   SharingServerHandler ──► sharing.pocketcasts.com / lists host        │
│                                                                        │
│   TokenHelper (Bearer auth, 401 refresh) · ServerHelper (request       │
│   builders) · URLConnection (URLSession wrapper) · protobuf (api.pb)   │
└────────────────────────────────────────────────────────────────────┘
```

Two wire formats are in use:

- **Protocol Buffers** (`application/octet-stream`) for almost everything on the `api` host (auth, sync, ratings, stats, bookmarks).
- **JSON** for the `refresh`, `cache`, `static`/discover, `search`, `sharing`, and `lists` hosts, plus error envelopes.

---

## 2. Hosts & environments

All base URLs are defined in **`ServerConstants.Urls`** (`Public/Sharing/Structs/ServerConstants.swift`). Each first‑party host has a **production (`.com`)** and a **staging (`.net`)** variant. Selection is driven by `ServerConfig.shared.syncDelegate?.production()` (defaults to production when no delegate is set — `ServerConstants.production()`).

| `Urls` accessor | Production | Staging | Used for |
|---|---|---|---|
| `main()` | `https://refresh.pocketcasts.com/` | `https://refresh.pocketcasts.net/` | Podcast refresh, podcast search/show, OPML import |
| `api()` | `https://api.pocketcasts.com/` | `https://api.pocketcasts.net/` | Account, auth, sync, ratings, stats |
| `cache()` | `https://cache.pocketcasts.com/` | `https://podcast-api.pocketcasts.net/` | Full podcast/show‑notes JSON, episode URLs, suggest folders, aggregate ratings |
| `sharing()` | `https://sharing.pocketcasts.com/` | `https://sharing.pocketcasts.net/` | Create shareable podcast lists |
| `discover()` | `https://static.pocketcasts.com/discover/` | `https://static.pocketcasts.net/discover/` | Discover layout JSON + thumbnails |
| `image()` | `https://static.pocketcasts.com/` | `https://static.pocketcasts.net/` | Static image host |
| `share()` | `https://pca.st/` | `https://pcast.pocketcasts.net/` | Short share links |
| `lists()` | `https://lists.pocketcasts.com/` | `https://lists.pocketcasts.net/` | Curated lists / bundle JSON |
| `search` | `https://search.pocketcasts.com/` | `https://search.pocketcasts.net/` | Predictive/autocomplete search |
| `generatedTranscripts` | `https://shownotes.pocketcasts.com/generated_transcripts/` | `https://shownotes.pocketcasts.net/generated_transcripts/` | AI‑generated transcripts |
| `tvPair` / `tvCreate` | `https://pocketcasts.com/pair` · `/create` | `https://pocketcasts.net/...` | TV device pairing web pages |

Static link constants (always production): `support` (`support.pocketcasts.com/ios/`), `termsOfUse`, `privacyPolicy`, `pocketcastsDotCom`, `automatticDotCom`, App Store URLs, and several knowledge‑base article links.

---

## 3. Authentication & tokens

### 3.1 Credential storage

Credentials live in the **Keychain** (accessibility `kSecAttrAccessibleAfterFirstUnlock`), accessed via `ServerSettings`:

| Item | Keychain key | Notes |
|---|---|---|
| Sync access token (v2 / OAuth) | `SJSyncV2Token` | Bearer token for all authenticated calls |
| Refresh token | `SJRefreshToken` | SSO / device‑flow refresh |
| Email | `SJSyncingEmail` | Legacy email/password |
| Password | `SJSyncingPwd` | Legacy email/password |
| Push token | `SJPushToken` | APNs device token |
| Apple auth user id | `SJAppleAuthUserID` | Sign in with Apple |

### 3.2 Authorization header

Authenticated requests carry `Authorization: Bearer <token>` (`ServerConstants.HttpHeaders.authorization`), injected by `TokenHelper` and `ApiBaseTask`.

### 3.3 Sign‑in flows

| Flow | Endpoint | Request → Response | Notes |
|---|---|---|---|
| Email / password | `POST api/user/login` | `Api_UserLoginRequest{email,password,scope}` → `Api_UserLoginResponse{token,uuid,email}` | No refresh token issued |
| Register | `POST api/user/register` | `Api_RegisterRequest{email,password,scope}` → `Api_RegisterResponse{success,uuid}` | |
| Forgot password | `POST api/user/forgot_password` | `Api_EmailRequest{email}` → `Api_UserChangeResponse` | |
| Sign in with Apple (SSO) | `POST api/user/token` | `Api_UserTokenRequest{grantType:"refresh_token", refreshToken:<identityToken>, scope}` → `Api_TokenLoginResponse{accessToken,uuid,email,refreshToken,isNew}` | Token persisted & refreshable |
| Refresh identity token | `POST api/user/token` | Stored refresh token → new `AuthenticationResponse` | `refreshIdentityToken()` |
| Device authorization (TV) | `POST api/device/authorize` then poll `POST api/user/token` | `Api_DeviceAuthorizeRequest{scope}` → `{deviceCode,userCode,verificationUri,verificationUriComplete}`; then `grantType:"urn:ietf:params:oauth:grant-type:device_code"` | User confirms at `pocketcasts.com/pair` |
| Sonos token exchange | `POST api/user/exchange_sonos` | empty → JSON `{accessToken, refreshToken?}` | Sonos‑scoped token |

**Scopes** (`AuthenticationScope`): `mobile`, `tv`, `sonos`. The default API scope value is `mobile` (`ServerConstants.Values.apiScope`).

`AuthenticationResponse` (unifies both login shapes):

```swift
struct AuthenticationResponse: Codable {
    let token: String?
    let uuid: String?
    let email: String?
    let refreshToken: String?
    let isNewAccount: Bool?
}
```

### 3.4 Token refresh on 401

`TokenHelper.performCallSecureUrl(...)` wraps authenticated requests:

1. Attach `Bearer` token and send.
2. On **401 Unauthorized** and first attempt → discard cached token, re‑acquire via `acquireToken()` (password or identity token), retry **once**.
3. If the retry also 401s → delete the token from the Keychain (forces re‑login). A `Server.User.WillBeSignedOut` notification path exists for deauth.

Account mutations: `POST api/user/change_email` (`Api_UserChangeEmailRequest`), `POST api/user/change_password` (`Api_UserChangePasswordRequest`), `POST api/user/delete_account` (`Api_BasicRequest`).

---

## 4. Request infrastructure

### 4.1 Request builders (`ServerHelper`, `ApiBaseTask`)

| Builder | Method | Content‑Type / Accept | Default timeout |
|---|---|---|---|
| `createProtoRequest` / `createEmptyProtoRequest` | POST | `application/octet-stream` | 15 s (empty) |
| `createJsonRequest` | POST | `application/json; charset=UTF8` / `application/json` | caller‑specified |
| `ApiBaseTask.createRequest` | GET/POST/DELETE | `application/octet-stream` | `syncTimeout` = 60 s, cache policy `.reloadIgnoringLocalCacheData` |

Standard timeouts (`ServerConstants.Timeouts`): `sync` = 60 s, `general` = 60 s, `cache` = 30 s.

### 4.2 Headers added to every request

- `User-Agent` → `ServerConfig.shared.syncDelegate?.privateUserAgent()` (falls back to `"Pocket Casts"`).
- `Authorization: Bearer <token>` on authenticated calls.
- **Localization headers** via `URLRequest.addLocalizationHeaders()` — adds `X-User-Region` and `X-App-Language` **only** when the request host is in `InternationalizationProvider.allowedHosts` (all first‑party hosts: `main`, `api`, `cache`, `sharing`, `discover`, `image`, `share`, `lists`, `search`).

### 4.3 Conditional caching

`URLRequest+RefreshIfNeeded` sets `If-None-Match` (from `ETag`) and `If-Modified-Since` (from `Last-Modified`) using a cached response, enabling **304 Not Modified** handling. `URLResponse+HttpHelpers` parses `ETag`, `Last-Modified`, `Cache-Control`, `Expires`, `Date` and computes cache expiry. Several handlers keep their own `URLCache` (Discover, show notes, colors, transcripts, chapters).

### 4.4 Networking primitives

| Type | Role |
|---|---|
| `URLConnection` | Thin `URLSession` wrapper (`send`, async `send`, `sendSynchronousRequest`) conforming to `RequestHandler` |
| `TokenHelper` | Token acquisition/caching, secure‑URL calls, 401 retry |
| `ApiBaseTask` | Base `Operation` for protobuf API tasks (acquires token, builds request, parses response) |
| `JSONDecodableURLTask<Response>` | Generic JSON GET/POST helper (`.convertFromSnakeCase`, throws on 404/403) |
| `URL(throwing:)` | Throwing URL initializer |
| `NSError.isConnectivityError` | Classifies offline/timeout/DNS `URLError`s |

### 4.5 Error model

`ErrorResponse.swift` defines `APIError` covering login/auth (`INCORRECT_PASSWORD`, `EMAIL_NOT_FOUND`, `ACCOUNT_LOCKED`, …), account creation (`EMAIL_TAKEN`, `USER_REGISTER_FAILED`, …), OAuth/device (`AUTHORIZATION_PENDING`, `EXPIRED_TOKEN`, `ACCESS_DENIED`, `INVALID_GRANT`), promo codes, and client‑side states (`NO_CONNECTION`, `TOKEN_DEAUTH`, `PERMISSION_DENIED`, `UNKNOWN`). HTTP codes are mapped from `ServerConstants.HttpConstants` (200/304/400/401/403/404/409/500).

---

## 5. API endpoint reference (`api` host)

All endpoints below are relative to `ServerConstants.Urls.api()` and require a Bearer token unless noted. Bodies/responses are Protocol Buffers unless stated.

### Account & auth
| Method | Path | Request → Response | Purpose |
|---|---|---|---|
| POST | `user/login` | `Api_UserLoginRequest` → `Api_UserLoginResponse` | Email/password login *(unauthenticated)* |
| POST | `user/register` | `Api_RegisterRequest` → `Api_RegisterResponse` | Create account *(unauthenticated)* |
| POST | `user/token` | `Api_UserTokenRequest` → `Api_TokenLoginResponse` | SSO / device / refresh token |
| POST | `user/forgot_password` | `Api_EmailRequest` → `Api_UserChangeResponse` | Password reset *(unauthenticated)* |
| POST | `device/authorize` | `Api_DeviceAuthorizeRequest` → `Api_DeviceAuthorizeResponse` | TV device code *(unauthenticated)* |
| POST | `user/change_email` | `Api_UserChangeEmailRequest` → `Api_UserChangeResponse` | Change email |
| POST | `user/change_password` | `Api_UserChangePasswordRequest` → `Api_UserChangeResponse` | Change password |
| POST | `user/delete_account` | `Api_BasicRequest` → `Api_UserChangeResponse` | Delete account |
| POST | `user/exchange_sonos` | empty → JSON `{accessToken,refreshToken?}` | Sonos token exchange |

### Sync & state
| Method | Path | Request → Response | Purpose |
|---|---|---|---|
| POST | `user/sync/update` | `Api_SyncUpdateRequest` → `Api_SyncUpdateResponse` | Incremental sync (podcasts/episodes/playlists/folders/bookmarks/stats) |
| POST | `up_next/sync` | `Api_UpNextSyncRequest` → `Api_UpNextResponse` | Up Next queue |
| POST | `history/sync` | `Api_HistorySyncRequest` → `Api_HistoryResponse` | Listening history |
| POST | `user/named_settings/update` | `Api_NamedSettingsRequest` → `Api_NamedSettingsResponse` | App/podcast settings |
| POST | `sync/update_episode` | `Api_UpdateEpisodeRequest` | Real‑time playback position/status |
| POST | `sync/update_episode_star` | `Api_UpdateEpisodeStarRequest` | Star/unstar episode |
| POST | `user/last_sync_at` | `Api_EmptyRequest` → `Api_UserLastSyncAtResponse` | Last sync timestamp (full sync) |

### Library retrieval (full sync)
| Method | Path | Response | Purpose |
|---|---|---|---|
| POST | `user/podcast/list` | `Api_UserPodcastListResponse` | Subscribed podcasts + folders |
| POST | `user/podcast/episodes` | `Api_SyncEpisodesResponse` | Episode sync state for one podcast |
| POST | `user/playlist/list` | `Api_UserPlaylistListResponse` | Filters/playlists (incl. episodes) |
| POST | `user/bookmark/list` | `Api_BookmarksResponse` | Bookmarks |
| POST | `starred/list` | `Api_StarredEpisodesResponse` | Starred episodes |

### Ratings, stats, recommendations, feedback
| Method | Path | Request → Response | Purpose |
|---|---|---|---|
| GET | `user/podcast_rating/list` | → `Api_PodcastRatingsResponse` | All of the user's ratings |
| POST | `user/podcast_rating/add` | `Api_PodcastRatingAddRequest` | Add/update a rating (1–5) |
| POST | `user/podcast_rating/show` | `Api_PodcastRatingShowRequest` → `Api_PodcastRating` | One podcast's user rating |
| POST | `user/stats/summary` | `Api_StatsRequest` → `Api_StatsResponse` | Listening stats summary |
| POST | `discover/recommend_episodes` | `Api_BasicRequest` → `Api_EpisodesResponse` | Recommended episode |
| POST | `support/feedback` *(auth)* / `anonymous/feedback` *(anon)* | `Api_SupportFeedbackRequest` | Submit feedback |

---

## 6. Sync subsystem

Source: `Public/Sync/`. The sync engine reconciles the local GRDB database with the server through the `ServerSyncDelegate` bridge (`ServerSyncDelegateProtocol.swift`).

### 6.1 Full vs incremental

`SyncTask.performSync` branches on the stored `PCLastModifiedServerDate` UserDefault:

- **Empty → full sync** (`SyncTask+FullSync`): `RetrieveLastSyncDateTask` → `RetrievePodcastsTask` (podcasts+folders) → `RetrievePlaylistsTask` → `RetrieveBookmarksTask` → per‑podcast `addFromUuid` + `RetrieveEpisodesTask`. Stores `lastSyncAt`.
- **Present → incremental sync** (`SyncTask+LocalChanges` / `+ServerChanges`): builds `Api_SyncUpdateRequest` from records with `SyncStatus.notSynced` / `.notSyncedRemove` (limit `maxEpisodesToSync = 2000`), POSTs `user/sync/update`, then imports server records and stores `response.lastModified`.

`lastModified` is an `Int64` millis token (legacy ISO‑8601 strings are tolerated and converted).

### 6.2 Record union

`Api_SyncUpdateRequest.records` is a list of `Api_Record`, each one of:

| Record | Key synced fields |
|---|---|
| `Api_SyncUserPodcast` | subscribed, isDeleted, autoStartFrom, autoSkipLast, sortPosition, folderUuid, dateAdded, `settings` (when settings‑sync flag on) |
| `Api_SyncUserEpisode` | playingStatus, playedUpTo, starred, isDeleted (archived), duration, deselectedChapters — each with a `*Modified` millis token |
| `Api_SyncUserPlaylist` | title, filter flags, podcastUuids, sort, manual + episode order |
| `Api_SyncUserFolder` | name, color, sortPosition, podcastsSortType, dateAdded |
| `Api_SyncUserDevice` | time stats (silence/skip/intro/variable/listened), deviceID, deviceType |
| `Api_SyncUserBookmark` | episode/podcast uuid, time, title, createdAt, isDeleted (each with modified tokens) |

### 6.3 Up Next, History, Settings

- **Up Next** (`UpNextSyncTask`, `up_next/sync`): sends `Api_UpNextChanges` against a `serverModified` token (`SJUpNextServerLastModified`). On **login** (`syncReason == .login`) it performs a non‑destructive merge (keeps local episodes not on server); otherwise it sends local add/remove/replace changes.
- **History** (`SyncHistoryTask`, `history/sync`): sends `Api_HistoryChange` (add/delete/clearAll) against `SJHistoryServerLastModified`; supports cross‑device clear via `lastClearHistoryDate`. Capped at `maxHistoryItems = 100`.
- **Settings** (`SyncSettingsTask`, `user/named_settings/update`): when `FeatureFlag.settingsSync` is on, sends `Api_ChangeableSettings` (only modified keys); legacy mode syncs a small subset (skip times, marketing opt‑in, grid order). Per‑podcast settings ride along inside `Api_SyncUserPodcast.settings`.

### 6.4 Real‑time position/star

During playback, `ApiServerHandler.saveUpTo/saveCompleted/saveStarred` enqueue `PositionSyncTask` (`sync/update_episode`) and `StarredSyncTask` (`sync/update_episode_star`) on a serial `apiQueue` — independent of the main sync cycle and throttled by `minTimeBetweenProgressSaves`.

### 6.5 Background sync

`BackgroundSyncManager` uses a **background `URLSession`** (`URLSessionConfiguration.background(withIdentifier: "SyncBgSession" + UUID())`) driving `URLSessionDownloadTask`s tagged `"refresh"`, `"upnext"`, `"sync"`. The system completion handler is stashed in `ServerConfig.backgroundSessionCompletionHandler` and invoked on the main queue in `urlSessionDidFinishEvents`. Feature flags `detectTruncatedBackgroundSyncDownloads` (Content‑Length validation) and `trackNetworkDataUsage` (byte accounting) refine behavior.

### 6.6 Triggers & cadence

The sync cycle is kicked off **after a refresh** (`RefreshOperation`) when logged in, in order: Up Next → main sync → history → settings → remote stats. Refresh itself fires on: pull‑to‑refresh, app foreground, scheduled background refresh, and login. `RefreshManager` throttles to a minimum 15 s between refreshes. `SyncingReason` (`accountCreated`/`login`/`replace`/`remove`/`add`) modulates Up Next behavior.

### 6.7 Conflict resolution highlights

- Episode currently playing → local playing status/position wins and is re‑queued as unsynced.
- Server archive ignored if the episode is actively playing locally.
- Paused player → server playback position is applied (seek); playing player → ignored.
- Up Next on login → non‑destructive merge. Settings overwrites are logged via `Diffable+Logging`.

---

## 7. Refresh subsystem (`refresh` host)

Source: `Public/Refresh/`. JSON over `ServerConstants.Urls.main()`.

| Method | Path | Purpose |
|---|---|---|
| POST | `user/update` | **Primary refresh** — checks all subscribed podcasts for new episodes |
| POST | `podcasts/refresh` | Force server to re‑fetch a single podcast's feed |
| POST | `podcasts/show` | Get podcast details |
| POST | `podcasts/search` | Podcast search (also used by `PodcastSearchOperation`) |
| POST | `import/opml` | Upload OPML feed URLs (chunked, then poll) |
| GET | `import/export_feed_urls` | Export subscribed feed URLs |
| GET | `api/v1/update_podcast?{query}` | Legacy single‑podcast update |
| POST | `{sharePath}` | Resolve a shared podcast list link |

`MainServerHandler.refresh(podcasts:)` POSTs a JSON body with standard params (`device`, `m`, `av`, `l`, `c`, `dt=1`, `v="1.7"`, `push_sound`, `podcasts` (CSV of UUIDs), `last_episodes`, `push_messages_on`, `push_token`, `push_on`). Response is `PodcastRefreshResponse` → `RefreshResult.podcastUpdates` (per‑podcast arrays of `RefreshEpisode`), with a `status` of `"ok"` or `"poll"`. `RefreshOperation` writes new episodes, kicks metadata updates, and (if logged in) the sync cycle.

---

## 8. Discover (`static` host)

Source: `Public/Discover/DiscoverServerHandler.swift`. JSON over `ServerConstants.Urls.discover()`, with a dedicated `URLCache` (1 MB mem / 5 MB disk, ETag + Last‑Modified revalidation).

- **Layout:** `GET discover/ios/content_v3.json` when `FeatureFlag.recommendations` is enabled, else `content_v2.json` → `DiscoverLayout`.
- **Generic loader:** `discoverRequest<T>(path:type:authenticated:)` fetches each layout row's `source` URL → `[PodcastNetwork]`, `PodcastList`, `[DiscoverCategory]`, `DiscoverCategoryDetails`, `PodcastCollection`. When `authenticated` and the recommendations flag is on, uses `TokenHelper.callSecureUrl`.
- **Thumbnails:** `discover/images/{size}/{uuid}.jpg`, color metadata `discover/images/metadata/{uuid}.json`, default user‑episode artwork `discover/images/artwork/{theme}/{size}/{color}.png`.

Region/language flow through `X-User-Region` / `X-App-Language` headers.

---

## 9. Search

| Task | Method | Host + path | Notes |
|---|---|---|---|
| `PodcastSearchTask` | POST | `main()` + `podcasts/search` | Podcast/URL search; supports `status:"poll"` with exponential backoff |
| `EpisodeSearchTask` | POST | `cache()` + `episode/search` | Global episode search (`EpisodeSearchEnvelope`) |
| `CombinedSearchTask` | POST | `cache()` + `search/combined` | Unified podcasts + episodes (`CombinedSearchResultType`) |
| `PredictiveSearchTask` | GET | `search` + `autocomplete/search?q=` | Autocomplete (terms + podcasts) |
| `CacheServerHandler.searchEpisodesInPodcast` | POST | `cache()` + `mobile/podcast/episode/search` | Episode search within one podcast (authenticated) |

All add localization headers and generally use a no‑cache policy for freshness.

---

## 10. Cache & metadata (`cache` host)

Source: `Public/Cache/` and `Public/ServerPodcastManager*.swift`. JSON over `ServerConstants.Urls.cache()`.

| Method | Path | Purpose |
|---|---|---|
| GET | `mobile/podcast/full/{uuid}` | Full podcast + episodes JSON (auth via `TokenHelper`); supports `If-Modified-Since` → 304 |
| GET | `mobile/show_notes/full/{podcastUuid}` | Show notes for all episodes; `URLCache` 1 MB/100 MB, ETag revalidation, falls back to cache on error |
| GET | `mobile/episode/url/{podcastUuid}/{episodeUuid}` | Resolve an episode's playable URL (plain text) |
| GET | `mobile/podcast/findbyepisode/{podcastUuid}/{episodeUuid}` | Add missing podcast/episode (e.g. from shared links) |
| POST | `mobile/podcast/episode/search` | Episode search within a podcast |
| POST | `podcast/suggest_folders` | AI folder suggestions for a set of UUIDs *(unauthenticated; JSON `{language,uuids}`)* |
| GET | `podcast/rating/{uuid}` | **Aggregate** podcast rating `{total, average}` |

`CacheServerHandler.loadPodcastColors` reads color metadata from the **`static`** host (`discover/images/metadata/{uuid}.json`) with its own small `URLCache`. `ServerPodcastManager.loadRecommendations` calls `api/recommendations/podcast/{uuid}?country=` → `PodcastCollection`. `addFromUuid` retries up to 7× with backoff for freshly added podcasts; `updatePodcastIfRequired` uses conditional GET and auto‑archives episodes older than `oldEpisodeCutoff = 2 weeks` for subscribed podcasts.

`MetadataTask` (`Private/API Tasks/MetadataTask.swift`, via `MetadataUpdater`) issues an **HTTP `HEAD`** against an episode's `downloadUrl` to read `Content-Type` and `Content-Length` (min 150 KB) without downloading; posts `episodeTypeOrLengthChanged`. Queue concurrency 2; no auth.

---

## 12. Sharing & curated lists

Source: `Public/Sharing/`.

- **Create a shareable podcast list:** `SharingServerHandler.sharePodcastList` → `POST sharing()/share/list` (JSON, 20 s timeout). Body `{title, description?, podcasts:[{uuid}], datetime:"yyyyMMddHHmmss", h}` where `h` is an `Insecure.SHA1` signature of `datetime + ServerCredentials.sharing`. Response `{status, result:{share_url}}`.
- **Load a list/bundle:** `loadList` GETs a `PodcastList` JSON, typically `lists()/bundle-{bundleUuid}.json` (`ServerHelper.bundleUrl`). Used for supporter **bundles** (`BundleSubscription` / `PodcastSubscription`).
- **Short share links** (built in the app, `SharingHelper`): `share()` + `podcast/{uuid}` or `episode/{uuid}` (i.e. `https://pca.st/...`).
- Shared‑link payloads decode to `ShareListResponse` → `SharedPodcast` / `RefreshEpisode`; `UpNextItem` carries `{podcastUuid, episodeUuid, title, url, published}` for shared Up Next lists.

---

## 13. Stats

Source: `Public/StatsManager.swift`. Stats are accumulated **locally** in UserDefaults (silence‑removal, variable‑speed, total listened, skipped, auto‑skip; `statsStartDate`) and pushed into the sync stream as an `Api_SyncUserDevice` record. Remote totals are fetched via `loadRemoteStats` → `RetrieveStatsTask` → `POST api/user/stats/summary` (`Api_StatsRequest{deviceID, deviceType:1}`; empty `deviceID` requests account‑wide totals) → `Api_StatsResponse`, mirrored into `*Server` UserDefaults keys. `statsSyncStatus` tracks `.synced`/`.notSynced`.

---

## 14. Ratings

- **User's own rating:** add `POST api/user/podcast_rating/add`, show `POST api/user/podcast_rating/show`, list `GET api/user/podcast_rating/list` (see [§5](#5-api-endpoint-reference-api-host)).
- **Aggregate rating:** `PodcastRatingTask.retrieve(for:)` → `GET cache()/podcast/rating/{uuid}` → `PodcastRating{total, average}` (optionally bypassing cache).

---

## 15. Recommendations & suggested folders

- **Recommended episode:** `RecommendationHelper` → `RecommendEpisodesTask` → `POST api/discover/recommend_episodes` (`Api_BasicRequest` → `Api_EpisodesResponse`, first episode used).
- **Suggested folders:** `SuggestedFolderTask` → `POST cache()/podcast/suggest_folders` (unauthenticated JSON `{language, uuids}` → `{folderName: [uuid,…]}`).
- **Related podcasts:** `ServerPodcastManager.loadRecommendations` → `GET api/recommendations/podcast/{uuid}?country=` → `PodcastCollection`.

---

## 16. Episode downloads (main app)

Source: `podcasts/DownloadManager.swift` (+ `DownloadManager+URLSessionDelegate.swift`, `+SessionManagement.swift`).

Three `URLSession`s:

| Session | Identifier | Cellular |
|---|---|---|
| Wi‑Fi background | `au.com.shiftyjelly.PCBackgroundSession` | disabled |
| Cellular background | `au.com.shiftyjelly.PCManualSession` (`cellBackgroundSessionId`) | enabled (expensive‑network or cellular API per `FeatureFlag.useCellularNetworkApis`) |
| Foreground | default config | enabled |

- **Cookies disabled** on download sessions (`httpShouldSetCookies = false`, no cookie storage) to avoid tracking.
- Download URLs come from the episode's `downloadUrl` (populated by refresh/cache responses) — i.e. the **podcast publisher's CDN**, not a Pocket Casts host.
- **Resumable** via `downloadTask(withResumeData:)`; downloads transfer between foreground/background sessions.
- **Retry** strips the `User-Agent` header on a failed first attempt (some hosts reject it).
- Files saved to `Documents/podcasts_non_backed_up` and flagged do‑not‑back‑up.

---

## 17. Image & artwork loading (main app)

Source: `podcasts/ImageManager.swift`, `PodcastImage.swift`, `EpisodeArtwork.swift`. Uses **Kingfisher**.

- **Podcast artwork:** `static.pocketcasts.com/discover/images/{size}/{uuid}.jpg` (sizes 130–960). Episode artwork URLs come from show notes (`ShowInfoCoordinator`), preferring publisher image over embedded ID3 art.
- **Caches** (Kingfisher `ImageCache`): subscribed artwork `Documents/artworkv3` (≈400 MB, 1 yr), network images (8 wk), search (10 MB), user‑episode (10 MB, 1 yr), discover (10 MB, 10 d), discover video thumbnails (50 MB, 10 d).

---

## 18. Transcripts & chapters (main app)

- **Transcript contributions (fork backend, write-only):** `POST transcripts/contribute` (gzipped VTT + `fingerprint-compact-v2` fingerprint + source metadata) and `POST transcripts/sighting` (publisher transcript URL for server-side fetch), both App Attest-authenticated with optional Bearer attribution. Full contract: `docs/TranscriptContributions.md`; auth: `docs/AppAttest.md`; decisions: ADR-0002/0003.

- **Transcripts:** `TranscriptsDataRetriever` fetches per‑episode transcript URLs (from episode metadata) over an **ephemeral** `URLSession`; `URLCache` 1 MB/100 MB in `transcripts/`, `reloadRevalidatingCacheData`, ETag/Last‑Modified conditional requests. **Generated transcripts** use `generatedTranscripts` host: `shownotes.pocketcasts.com/generated_transcripts/{podcastUuid}/{episodeUuid}.{ext}` (gated by `FeatureFlag.generatedTranscripts`), built in `ShowInfoCoordinator`.
- **Chapters:** `PodcastIndexChapterDataRetriever` fetches Podcast Index chapter JSON from per‑episode URLs; `URLCache` 1 MB/10 MB in `podcast_index_chapters/`, snake‑case decoding. Per‑chapter `url` (external link — surfaced by the player chapter link UI after http(s) validation in `PodcastChapterParser`) and `img` (artwork URL — decoded and stored; fetching/display is a documented follow‑up) are read since AI UX Phase 6.
- **Generated episode metadata:** `GeneratedEpisodeMetadataRetriever` GETs `shownotes.pocketcasts.com/generated_transcripts/{podcastUuid}/{episodeUuid}-meta.json`; `URLCache` 1 MB/10 MB in `generated_episode_metadata/`, snake‑case decoding, in‑flight request coalescing. Envelope (`GeneratedMetadataEnvelope`): `summary: String?` (AI episode summary — rendered by the episode‑detail summary card behind `FeatureFlag.episodeSummaries`, `ShowInfoCoordinator.loadEpisodeSummary`) and `chapters: [{title, timestamp, start_time}]?` (AI chapters, lowest‑priority chapter source in `ShowInfoCoordinator.loadChapters`). A per‑chapter `url` field is **backend‑optional**: the client currently ignores unknown keys on generated chapters and does not render links for them; if the backend ever emits one, adding client decode is a small follow‑up (AI UX Phase 6 note).
- **Episode metadata payload (`Episode.Metadata`, from `mobile/show_notes/full/{podcastUuid}`):** decoded with snake‑case conversion in `ShowInfoCoordinator`. Per episode: `show_notes`, `image`, `chapters` (Podlove‑style inline chapters: `{start_time, title?, end_time?, url?|href?, image?}` — `url` wins when both link keys are present; links are http(s)‑validated before reaching the chapter UI; `image` is stored, artwork fetch is a follow‑up), `chapters_url` (Podcast Index chapters JSON), `transcripts` (required key; entries `{url, type}`), `pocket_casts_transcripts`, and — expected once the cache server forwards `<podcast:person>` — `persons?: [{name, role?, group?, img?, href?}]` (`name` required per entry; item‑level credits, with channel‑level credits pre‑merged as the fallback). Until the server emits `persons`, only local‑feed podcasts (whose show‑info JSON is synthesized on device by `LocalFeedShowInfo` from the parsed feed) show the episode‑credits card (`FeatureFlag.episodeCredits`).

---

## 19. Push notifications

Source: `podcasts/Utilities/NotificationsHelper.swift`, `AppDelegate.swift`, `PodcastManager.swift`.

1. `registerForPushNotifications()` → `UIApplication.registerForRemoteNotifications()` (auth `.alert/.badge/.sound`).
2. `didRegisterForRemoteNotificationsWithDeviceToken` → hex‑encode token → `PodcastManager.didReceiveToken`.
3. Token stored via `ServerSettings.setPushToken` (Keychain `SJPushToken`); on change triggers a forced refresh, which carries `push_token`/`push_on`/`push_messages_on` to `refresh.pocketcasts.com/user/update`. APNs delivery is therefore registered through the **refresh** payload — there is no standalone "register device" endpoint.
4. Failure → `ServerSettings.removePushToken()`.

Notification categories/actions (download, play now, add to Up Next first/last, archive, deep links) are handled in `UNUserNotificationCenterDelegate`.

---

## 20. Analytics & telemetry

Source: `podcasts/Analytics/`. All gated on the user **not** opting out (`Settings.analyticsOptOut()`), and each SDK only initializes when its credential is present.

| Service | Type | Init / transport |
|---|---|---|
| **Bitdrift** (`import Capture`) | Error/session logging | `Capture.Logger.start(withAPIKey: ApiCredentials.bitdriftSDKKey, …)` in `AppDelegate`; SDK manages its own network |
| **TelemetryDeck** (`import TelemetryDeck`) | Product analytics | `TelemetryDeck.initialize(config:.init(appID: ApiCredentials.telemetryDeckAppID))`; `TelemetryDeck.signal(name, parameters:)` |
| `AnalyticsLoggingAdapter` | Local only | No network |

Opt‑in/opt‑out transitions (`analyticsOptIn`/`analyticsOptOut`) are themselves tracked before adapters are torn down.

---

## 22. OPML import/export & status page

- **OPML import:** `OpmlImporter` parses the OPML locally, then `MainServerHandler.sendOpmlChunk` POSTs feed URLs (100 per chunk) to `refresh.pocketcasts.com/import/opml` and polls (~20×, increasing delay) for resolved podcast UUIDs. URL‑based import downloads a remote OPML then follows the same path.
- **OPML export:** entirely local (generates XML, shares via `UIDocumentInteractionController`) — no network.
- **Status page** (`StatusPageViewModel`, user‑initiated diagnostics, `GET`):
  - `https://refresh.pocketcasts.com/health.html`
  - `https://api.pocketcasts.com/health`
  - `https://static.pocketcasts.com/discover/ios/content.json`
  - `https://cache.pocketcasts.com/mobile/podcast/full/{test-uuid}`
  - `https://dts.podtrac.com/redirect.mp3/static.pocketcasts.com/assets/feeds/status/episode1.mp3` (podcast‑hosting path via Podtrac)

---

## 23. Protocol Buffers catalog

Generated Swift lives in `Private/Protobuffer/api.pb.swift` (~149 message types). The proto is regenerated with `mise run generate:proto /path/to/pocketcasts-api/api/modules/protobuf/src/main/proto` (see `README.md` and `AGENTS.md`).

**`api.pb.swift` groups:** auth (`Api_UserLoginRequest/Response`, `Api_UserTokenRequest`, `Api_TokenLoginResponse`, `Api_DeviceAuthorize*`), account (`Api_RegisterRequest/Response`, `Api_UserChange*`, `Api_EmailRequest`, `Api_UserLastSyncAtResponse`), sync (`Api_SyncUpdateRequest/Response`, `Api_Record`, `Api_SyncUser{Podcast,Episode,Playlist,Folder,Device,Bookmark}`), Up Next/history/settings (`Api_UpNext*`, `Api_History*`, `Api_NamedSettings*`, `Api_ChangeableSettings`, `Api_{Bool,Int32,Double,String}Setting`), episodes (`Api_Episode(s)Response`, `Api_UpdateEpisode*`, `Api_StarredEpisode(s)Response`), podcasts/folders/playlists/bookmarks/ratings/stats, search,  and misc (`Api_BasicRequest`, `Api_EmptyRequest/Response`, `Api_SupportFeedbackRequest`, legacy types).

> Not every defined message is wired to an active endpoint (notably the commerce types).

---

## 24. Server notifications (NSNotification)

Posted by `ServerNotifications` / `ServerNotificationsHelper` so the UI can react to remote activity:

| Constant | Name | Meaning |
|---|---|---|
| `syncStarted` / `syncCompleted` / `syncFailed` | `PCSyncStarted` / `PCSyncDone` / `PCSyncFailed` | Sync lifecycle |
| `podcastsRefreshed` / `podcastRefreshFailed` / `podcastRefreshThrottled` | `PCRefreshed` / `PCRefFailed` / `PCRefreshedThrottled` | Refresh lifecycle |
| `syncProgressPodcastCount` / `…ImportedPodcasts` / `…PodcastUpto` | `PCSyncCount` / `PCSyncPodcastsDone` / `PCSyncUpto` | Full‑sync progress |
| `episodeTypeOrLengthChanged` | `SJEpisodeTypeChanged` | Metadata (`HEAD`) update |
| `subscriptionStatusChanged` | `SJSubscriptionStatusChanged` | Plus status changed |
| (`NSNotification.Name`) `serverUserWillBeSignedOut` | `Server.User.WillBeSignedOut` | Token deauth → sign‑out |

---

## 25. Persistence keys (Keychain / UserDefaults)

**Keychain** (`ServerConstants.Values`): `SJSyncV2Token`, `SJRefreshToken`, `SJSyncingEmail`, `SJSyncingPwd`, `SJPushToken`, `SJAppleAuthUserID`.

**UserDefaults** (`ServerConstants.UserDefaults`, sync‑relevant subset): `PCLastModifiedServerDate`, `PCLastSyncStartDate`, `SJLastRefreshDate`, `SJLastSyncDate`, `SJHistoryServerLastModified`, `SJUpNextServerLastModified`, `SJLastClearHistoryDate`, `SJPushToken`, `SJMarketingOptIn`(+`…NeedsSync`), the `Stats*` (local) and `Stats*Server` (remote) family, and `UserId`.

**Limits:** `maxHistoryItems = 100`, `maxEpisodesToSync = 2000`. **Misc:** `oldEpisodeCutoff = 2 weeks`, `deviceTypeiOS = 1`.

---

## 26. Complete host inventory

**First‑party (each with `.com` prod / `.net` staging unless noted):**

| Host | Role |
|---|---|
| `refresh.pocketcasts.com` | Refresh, podcast search/show, OPML import |
| `api.pocketcasts.com` | Account, auth, sync, ratings, stats |
| `cache.pocketcasts.com` (staging `podcast-api.pocketcasts.net`) | Podcast/show‑notes JSON, episode URLs, suggest folders, aggregate ratings |
| `static.pocketcasts.com` (+`/discover/`) | Artwork, color metadata, discover layout |
| `sharing.pocketcasts.com` | Create shareable lists |
| `lists.pocketcasts.com` | Curated lists / bundles |
| `search.pocketcasts.com` | Predictive/autocomplete search |
| `shownotes.pocketcasts.com` | Generated transcripts |
| `pca.st` (staging `pcast.pocketcasts.net`) | Short share links |
| `pocketcasts.com` | TV pair/create web pages, marketing |
| `support.pocketcasts.com` | Help, terms, privacy, KB articles |

**Third‑party / external:**

| Host / SDK | Role |
|---|---|
| Podcast publisher CDNs | Episode audio/video downloads (URLs from feeds) |
| `dts.podtrac.com` | Status‑page hosting check (Podtrac redirect) |
| **Bitdrift** (`Capture` SDK) | Error/session logging |
| **TelemetryDeck** SDK | Product analytics |
| Apple **APNs** | Push delivery (token registered via refresh) |
| `x.com`, `instagram.com` | Social links (deep link / web fallback) |

---

## 27. File map

| Area | Key files |
|---|---|
| Hosts & constants | `Public/Sharing/Structs/ServerConstants.swift` |
| Config & delegate | `Public/ServerConfig.swift`, `Public/Sync/ServerSyncDelegateProtocol.swift` |
| Auth & tokens | `Private/TokenHelper.swift`, `Public/API/ApiServerHandler+Account.swift`, `+DeviceAuth.swift`, `+SocialAuth.swift`, `Public/Models/AuthenticationResponse.swift`, `Public/ServerSettings.swift`, `Public/ServerCredentials.swift` |
| Request infra | `Public/ServerHelper.swift`, `Private/API Tasks/ApiBaseTask.swift`, `Public/URLConnection.swift`, `Public/Helpers/*`, `Public/URLResponse+HttpHelpers.swift`, `Public/NSError+Connectivity.swift` |
| API tasks | `Private/API Tasks/*`, `Public/API/ApiServerHandler*.swift`, `Public/API/ErrorResponse.swift` |
| Sync | `Public/Sync/SyncManager.swift`, `SyncTask*.swift`, `UpNextSyncTask.swift`, `SyncHistoryTask.swift`, `SyncSettingsTask.swift`, `BackgroundSyncManager*.swift` |
| Refresh | `Public/Refresh/RefreshManager.swift`, `RefreshOperation.swift`, `MainServerHandler.swift`, `PodcastSearchOperation.swift` |
| Discover / Search / Cache | `Public/Discover/DiscoverServerHandler.swift`, `Public/Search/*`, `Public/Cache/*`, `Public/ServerPodcastManager*.swift` |
| Sharing / Stats / Ratings | `Public/Sharing/*`, `Public/StatsManager.swift`, `Public/Ratings/PodcastRatingTask.swift` |
| Settings model | `Public/AppSettings.swift`, `SettingsStore.swift`, `CodableStore.swift`, `ApiSetting*.swift` |
| Protobuf | `Private/Protobuffer/api.pb.swift` |
| Downloads (app) | `podcasts/DownloadManager*.swift` |
| Images (app) | `podcasts/ImageManager.swift`, `PodcastImage.swift`, `EpisodeArtwork.swift` |
| Transcripts/Chapters (app) | `podcasts/TranscriptsDataRetriever.swift`, `PodcastIndexChapterDataRetriever.swift`, `Episode Info Coordinator/ShowInfoCoordinator.swift` |
| Push (app) | `podcasts/Utilities/NotificationsHelper.swift`, `AppDelegate.swift` |
| Analytics (app) | `podcasts/Analytics/Adapters/*` (`BitdriftAnalyticsAdapter`, `TelemetryDeckAnalyticsAdapter`) |
| Status page (app) | `podcasts/StatusPageViewModel.swift` |

---

*Generated from a source audit of `Modules/Sources/PocketCastsServer` and `podcasts/`. Endpoint paths, hosts, and identifiers were verified against the code; the commerce/IAP protobuf messages are defined but not wired to networking in this repository.*
