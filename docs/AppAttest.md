# App Attest first-party request contract

The fork's custom backend uses DeviceCheck App Attest to authenticate the app
installation independently of account authentication. The client supports
server modes `log-only` and `required`; production begins in log-only.

## Enrollment and serialization

The client keeps one nonmigrating App Attest key per install. It obtains a
single-use challenge from `GET /attest/challenge`, enrolls through
`POST /attest/enroll`, and stores only the key identifier. Development
attestations require the server's explicit `APP_ATTEST_ALLOW_DEV=true` policy.
Simulators work only with log-only environments.

Each assertion signs the SHA-256 of this exact UTF-8 value:

```text
v1\n<METHOD>\n<normalized escaped path>\n<sorted RFC3986 query>\n<lowercase SHA-256 of exact body bytes>
```

The method is uppercase. The escaped path must be canonical. Duplicate query
keys are preserved and encoded key/value pairs are sorted by key then value.
The body digest covers the exact bytes sent. `AppAttestService` serializes
assertion generation, request send, and completion through one actor so Apple
counters cannot race.

The assertion travels in `X-Attest-Key-Id` and `X-Attest-Assertion`. A typed
`409 stale_attestation` produces one fresh-assertion retry. A typed
`401 invalid_attestation` discards the App Attest key, re-enrolls, and retries
once. Attestation errors never erase access/refresh tokens or sign the user out.

## Route matrix

App Attest applies to:

- authenticated APIs, including login, registration, token issuance, avatar
  lifecycle, sharing creation, and sync;
- optional-auth routes whenever a Bearer token is supplied;
- anonymous native device/compute routes such as update polling, folder and
  related recommendations, capabilities, corpus reads, and contribution writes.

It does not apply to public catalog/search/discover, feed artwork, public share
resolution, profile/podcast/episode HTML, AASA, `/health.html`, or `/livez`.
Refresh exchange accepts either valid Bearer authentication or App Attest.
`POST /user/token/revoke` deliberately requires neither Bearer authentication
nor App Attest. Possession of an unbound refresh token is sufficient; a
DPoP-bound refresh family additionally requires a proof whose key thumbprint
matches the family's `jkt`.

Required mode is a release operation, not a client toggle. It should be enabled
only after a real production device enrolls and seven continuous telemetry days
show no invalid or unattested authenticated requests.
