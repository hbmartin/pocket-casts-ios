# Podcast backend client development handoff

Updated: 2026-07-26

This is the resumption document for the next Pocket Casts iOS development
round. It describes the coordinated client contract implemented with
`hbmartin/podcast-backend`, the important code paths, rollout constraints, and
work that still requires a configured environment or real device.

## Release boundary

The client and backend form one pre-release protocol migration. Older clients
and legacy refresh tokens are intentionally unsupported. Do not independently
ship this client against an older backend or switch App Attest to required while
acceptance is incomplete.

The release backend origin currently comes from `PODCAST_BACKEND_ORIGIN` in
`config/PocketCasts.base.xcconfig` and is injected as
`PCPodcastBackendOrigin`. Confirm the production custom hostname with the
operator before release. It must be a root HTTPS origin; only DEBUG may use
localhost/loopback HTTP.

## Implemented client architecture

### Origin and networking

- `ServerOriginPolicy` validates the configured origin, persists it on first
  launch, and blocks backend networking after a build-origin mismatch until
  reinstall. Offline and local playback remain available.
- `ServerConstants.Urls` points active API, refresh, cache, search, discover,
  sharing, artwork, generated-transcript, and list traffic at that one origin.
- The shared `URLConnection` boundary applies origin enforcement and App Attest
  consistently. New first-party networking should use this boundary rather than
  a direct `URLSession` call.
- The status screen reports origin/mismatch state and probes `/livez`, discover,
  default artwork, and the attested capability manifest.
- Custom associated-domain entries are present in the app entitlements.

Important files:

- `Modules/Sources/PocketCastsServer/Public/ServerOriginPolicy.swift`
- `Modules/Sources/PocketCastsServer/Public/URLConnection.swift`
- `Modules/Sources/PocketCastsServer/Public/Sharing/Structs/ServerConstants.swift`
- `podcasts/StatusPageView.swift`
- `podcasts/StatusPageViewModel.swift`

### App Attest

- `AppAttestCanonicalRequest` implements the versioned method/path/query/body
  canonicalization documented in `docs/AppAttest.md`.
- `AppAttestService` serializes assertion generation, send, and completion so
  assertion counters cannot race.
- Typed stale-counter responses generate a fresh assertion and retry once.
  Typed invalid-assertion responses discard/re-enroll the App Attest key and
  retry once. Neither path deletes account tokens or signs the user out.
- Public route exemptions and optional-Bearer behavior are centralized at the
  transport boundary. Extend the route-matrix tests whenever adding an endpoint.

Important files/tests:

- `Modules/Sources/PocketCastsServer/Public/AppAttest/AppAttestCanonicalRequest.swift`
- `Modules/Sources/PocketCastsServer/Public/AppAttest/AppAttestService.swift`
- `Modules/Tests/PocketCastsServerTests/AppAttestCanonicalRequestTests.swift`

### Authentication and APNs

- Login, registration, refresh, and reset requests carry the installation/device
  identifier expected by the coordinated backend protobuf.
- Authentication responses persist access and refresh tokens. Logout uses the
  possession-only revoke contract.
- The former forgot-password request was replaced by submission of an
  administrator-issued reset code plus email, identifier, and a 12–72-byte new
  password. The backend does not send reset email.
- `user/update` reports `sandbox` or `production` with the APNs device token.

Before release, replace the reset flow's temporary alert-based code/password UI
with a designed screen if product polish is required, localize all new copy, and
exercise account-family rotation/replay behavior on a real device.

### Background synchronization

`BackgroundSyncManager` now sends refresh, Up Next, and regular sync sequentially
through the same authenticated/App-Attest transport used in the foreground. Do
not reintroduce a background `URLSession` path that bypasses origin or assertion
serialization.

### Podcast refresh, recommendations, and folders

- Podcast update handles immediate 200 or durable 202. The 202 path follows the
  absolute `Location` every two seconds for at most two minutes.
- Folder suggestions send the existing JSON shape and defensively repair bad
  responses: case-fold duplicate names, discard invented UUIDs, move duplicate
  or missing assignments to Other, remove empty groups, merge groups smaller
  than two, and cap output at seven deterministic groups plus Other.
- Episode and related-podcast recommendation response formats remain compatible
  with existing client types.

Important tests:

- `Modules/Tests/PocketCastsServerTests/SuggestedFoldersRepairTests.swift`
- refresh behavior tests near `MainServerHandler` and `RefreshOperation`

### Capabilities, avatars, and sharing

- `CapabilitiesClient` decodes server version, App Attest mode, and avatar,
  AI-folder, and corpus booleans. Feature UI should trust these values and treat
  404 as unavailable.
- Own-profile UI supports photo selection, upload, expected protobuf rejection
  messages, capability URL display, and DELETE removal.
- Share creation always uses Bearer+App Attest. Legacy SHA-1 signing,
  `ServerCredentials`, embedded sharing secrets, the hosted-player handoff, and
  list-bundle helper were removed. Public share resolution remains anonymous.

Important files:

- `Modules/Sources/PocketCastsServer/Public/Capabilities/`
- `Modules/Sources/PocketCastsServer/Public/Social/SocialAvatarUploadSender.swift`
- `podcasts/Social/OwnSocialProfileView.swift`
- `Modules/Sources/PocketCastsServer/Public/Sharing/SharingServerHandler.swift`
- `docs/SocialAvatars.md`

### Transcript corpus and on-device metadata

- `CorpusManifestClient` is the only source of transcript/fingerprint/summary/
  chapter URLs and types. Do not construct `.vtt` or fingerprint URLs.
- Manifest reads use App Attest, ETags/304, strict same-origin capability URLs,
  and SHA-256 verification. Object-storage URLs must never reach the client.
- The transcript uploads immediately. A successful response persists the
  candidate ID and attachment token for a later metadata attachment.
- `TranscriptCorpusMetadataGenerator` performs a bounded Foundation Models
  segment map/reduce. Unavailable generation remains durable and retries on
  lifecycle opportunities and weekly until success or candidate deletion.
- Generated transcripts remain ungated; the existing always-false premium
  decision is unchanged.

Important files:

- `Modules/Sources/PocketCastsServer/Public/Transcripts/CorpusManifestClient.swift`
- `Modules/Sources/PocketCastsServer/Public/Transcripts/CorpusMetadataAttachmentClient.swift`
- `podcasts/Transcription/TranscriptContributionManager.swift`
- `podcasts/Transcription/TranscriptCorpusMetadataGenerator.swift`
- `podcasts/TranscriptsDataRetriever.swift`
- `docs/TranscriptContributions.md`

## Next-round priorities

1. Align the development machine with the repository: Xcode/Swift 6.3 and the
   simulator runtime selected by `mise run test:staging`. Then run, in order,
   `mise run format`, `mise run check:static`, `mise run build:staging`, and
   `mise run test:staging`.
2. Fix any compiler/test findings that were masked by toolchain resolution.
   Keep protobufs synchronized with the backend using
   `mise run generate:proto` and verify generated Go/Swift wire compatibility.
3. Confirm the custom production origin and associated domain. Test first-launch
   persistence, a deliberate build-origin mismatch, blocked networking, and
   unaffected offline playback.
4. Add/finish focused tests for sequential background sync, avatar removal,
   refresh polling, typed manifest fetching, capability-driven UI, and durable
   Foundation Models retries. Existing canonicalization, origin, and folder
   repair tests are the starting pattern.
5. Localize the reset, origin-mismatch, status, capability, avatar, and corpus
   user-facing strings through the repository SwiftGen workflow.
6. Run paired real-device acceptance against the candidate Railway digest:
   registration/login/rotation/logout; refresh polling; episode and related
   recommendations; folder AI/fallback/repair; avatar upload/reject/replace/
   delete; authenticated share creation and public resolution; transcript
   contribution, delayed metadata, manifest readback and 304; admin publisher
   promotion/rollback; status checks; and APNs sandbox/production selection.
7. Leave `APP_ATTEST_MODE=log-only` throughout acceptance. Confirm one production
   device enrollment, then collect seven continuous days with zero invalid or
   unattested authenticated requests before a separate required-mode change.

## Verification state at handoff

- Backend `go test ./...` and `git diff --check` pass after the coordinated proto,
  schema, and corpus changes.
- `mise run generate:proto` passes and the generated client protobuf matches the
  backend schema.
- Every changed/new Swift source parses with the installed compiler.
- The repository's required `mise run format`, `mise run check:static`, and
  `mise run build:staging` cannot run as declared on this machine because the
  checkout requires Swift tools 6.3 while installed Xcode provides Swift 6.2.4.
  `mise run test:staging` additionally defaults to iOS 26.5 while the installed
  simulator runtime is 26.3.
- A temporary, reverted 6.2 manifest compatibility pass ran the formatter and
  static suites far enough to catch and fix the new Sendable rationale. A full
  staging compile reached the main app and then stopped at the existing
  `AnalyticsEpisodeHelper` use of `nonisolated` on a property wrapper, a language
  construct this 6.2 compiler rejects. Both package manifests are restored to
  6.3 in the committed tree.

## Acceptance evidence to retain

Record the exact backend OCI digest, client commit, device/build identifiers,
custom origin, App Attest environment, and timestamps for each paired flow.
Capture capability JSON without tokens, relevant typed HTTP status/envelopes,
and Grafana panels for readiness, assertion failures, worker heartbeat, queue
age, and scheduler freshness. Never attach access/refresh tokens, assertion
CBOR, transcript content, avatar bytes, or request bodies to tickets or PRs.

The backend deployment and release-side contract lives in
`hbmartin/podcast-backend/docs/DeploymentAndProtocol.md`.
