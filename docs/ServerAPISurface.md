# Server and remote interaction surface

This fork routes active first-party API, refresh, cache, search, discover,
sharing, generated-transcript, artwork, and list resolution through one custom
backend origin. Support/marketing destinations and intentionally deferred
TV/Sonos references remain external. Podcast media and publisher resources still
come from their cataloged public URLs.

## Origin policy

`PODCAST_BACKEND_ORIGIN` is injected through xcconfig and Info.plist for device
and release targets. It must be a root HTTPS origin with no credentials, path,
query, or fragment. DEBUG may override it for localhost or loopback HTTP.

On first launch the app persists the build origin in reinstall-cleared local
settings. If a future build changes it, every backend request is blocked while
offline/local playback remains available. Settings explains that reinstall is
required. The custom host is also configured as the associated domain.

`ServerOriginPolicy` enforces this at the shared `URLConnection` boundary, so
foreground and background clients cannot bypass it. The Settings status screen
shows the origin/mismatch state and checks `/livez`, a representative discover
request, default artwork, and the attested capabilities manifest.

## Authentication

Login, registration, refresh, and reset include the ordinary installation/device
identifier. Login/register return an access token with a lifetime no greater
than 24 hours and a rotating refresh-token family with a 12-month absolute
lifetime and a 90-day idle timeout. Logout calls `POST /user/token/revoke`
without Bearer authentication or App Attest; a DPoP-bound family additionally
requires a proof whose key thumbprint matches its `jkt`. The public reset form submits an administrator-issued
15-minute code, email, identifier, and a 12–72-byte password; the backend does
not send email.

Bearer authentication and App Attest are independent. Attestation behavior and
the full public/protected route matrix are defined in [AppAttest.md](AppAttest.md).
Foreground and background authenticated work passes through the same serialized
App Attest transport. Background sync runs refresh, Up Next, and normal sync
sequentially inside its task.

## Product contracts

- `GET /api/v1/capabilities` supplies server version, App Attest mode, and
  avatar, AI-folder, and corpus booleans. Corpus UI trusts this flag and never
  probes object storage.
- Podcast refresh returns either immediate 200 or a durable 202 job with an
  absolute `Location`; the app polls every two seconds for no more than two
  minutes.
- Folder suggestions are anonymous+attested JSON. The app case-fold merges
  duplicate folder names, discards invented UUIDs, repairs duplicate/missing
  assignments into Other, removes empty groups, merges groups under two, and
  retains at most seven deterministic groups plus Other.
- Avatar upload sends raw JPEG/PNG and decodes expected rejection status from the
  protobuf envelope. Settings/profile UI also exposes attested Bearer DELETE.
- Share creation requires Bearer+App Attest. Resolution and HTML/Open Graph pages
  remain public; there is no legacy SHA-1 credential or web-player handoff.
- APNs registration reports sandbox/production with each device token.
- Transcript manifests and durable metadata generation are specified in
  [TranscriptContributions.md](TranscriptContributions.md).

Device authorization, TV pairing, Sonos exchange, user-file hosting,
subscriptions/IAP, supporter bundles, promotions, and paid recommendations are
unsupported by this coordinated release.
