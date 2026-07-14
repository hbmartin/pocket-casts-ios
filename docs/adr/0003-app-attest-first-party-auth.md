# App Attest is the first-party proof for fork-owned anonymous endpoints

Anonymous write endpoints on this fork's backend (transcript contributions,
sightings, shake feedback) need proof that requests come from an unmodified build
of this app on real Apple hardware — an account credential doesn't exist for
signed-out users, and a DPoP-style self-generated key proves key possession but
not first-party-ness. We decided to use **DeviceCheck App Attest**: a per-install
Secure Enclave key, attested once with Apple, producing per-request assertions
over the request body hash. This deliberately **front-runs the App Attest item
deferred by the API Auth Hardening Plan** (`plans/old/API Auth Hardening Plan.md`
§7 non-goals): a brand-new low-stakes endpoint is the ideal pathfinder to de-risk
attestation before it ever gates account-bearing endpoints.

## Consequences

- The client module is built as reusable infrastructure (the hardening plan's
  `RequestSigner` shape): any request can opt into carrying an assertion; the
  transcript endpoints require it and the feedback endpoint is retrofitted in the
  same pass (server dual-accepts during rollout: log-only → required).
- The App Attest key ID doubles as the anonymous attribution identity for
  contributions (account ID wins when the request is authenticated) — the server
  stores the association deliberately, as an abuse/provenance handle.
- Simulator and dev builds cannot attest; the server contract defines the bypass
  policy (staging-only acceptance of unattested requests). Attestation requires
  real server-side verification work (Apple cert chain, receipts, counters) —
  specified in `docs/AppAttest.md`, which the backend must implement before the
  client ships (the client has no flag to hold it back).
