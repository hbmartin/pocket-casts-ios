# Local-First & Product Modernization Program — July 2026 Summary

The full program from `plans/Pocket Casts iOS — Local-First & Product Modernization Program.md`
shipped on the `local-first-program` branch: every A–J track item landed, each slice
gate-verified (build, app + module test suites, snapshot tests, static checks, ratchets,
semgrep fixture suites) before commit.

## What shipped, by track

- **A — Local-first flags & behavior**: fileSync/upNextSort/shareProfile/generatedChapters/
  voiceBoostN un-gated (A1/A4/A5); episode-identity matcher for local feeds (A2);
  signed-out subscribe defaults to local RSS with sticky refresh source (A3); synced
  settings storage + sync enabled with remote kill switches (A6a — A6b deletion deferred
  one release, see DeferredWork.md). A6a soak immediately caught and fixed a settings
  writer that clobbered podcast syncStatus on every save.
- **B — Data layer**: concurrentDatabaseReads retired (B0); raw-SQL conversions and
  survey (B1–B4); PlaylistQueryBuilder rewritten as typed GRDB `SQLRequest` builders with
  a ~1,080-comparison row-set parity suite and a semgrep rule guarding the legacy path
  (B5); ValueObservation piloted behind a `DatabaseObserving` AsyncStream API — podcast
  grid + BadgeHelper converted (B6).
- **C — Typed NotificationCenter**: infrastructure + spike (Phase 4), all six domain
  sweeps plus a straggler pass (Phase 5, ~90 message structs), and cleanup (Phase 6):
  8 dead names deleted, 41 constants inlined into their structs and removed, the legacy
  string post helper deleted, and a CI allowlist check against regressions.
  Key SDK finding (probe-verified): typed `post(_:)` drops makeNotification's
  object/userInfo for legacy observers — the bridge helper posts the legacy Notification.
- **D — Feature-flag debt**: all 48 simple + playback flags retired (D1/D2).
- **E — Playback features**: loudness normalization as a first-class effect (E1), chapter
  smart-skip rules (E2), route-aware playback rules replacing dontAutoplayOnRouteChange (E3).
- **F — System integration**: Live Activity/Dynamic Island (F1), three new Control Center
  controls (F2), SiriKit fully removed in favor of App Intents — both extension targets
  deleted (F3), MetricKit collector (F4), TipKit migration (F5).
- **G — Product**: transcript reader (G1), Explore tab (G2), bookmark Markdown export (G3).
- **H — Testing/CI**: CI test-target coverage (H1), all-themes snapshot harness with 63
  baselines (H2), FeedParser fuzz corpus (H3), FileSync merge simulation (H4), mutation
  scaffold (H5), build-time trends (H6), @unchecked-Sendable semgrep gate (H7).
- **I/J — Cleanup & docs**: ID3 chapter parser ported to Swift, last Objective-C removed
  (I1); generated theme colors moved to a runtime JSON table, 6,087 → 2,868 lines (I2);
  ServerBackendSpec deleted; Fingerprinting/SemanticSearch/DeferredWork/LocalFirst docs (I3/J).

## Where the details live

Per-slice rationale is in the commit history of `local-first-program`; deferred items and
re-entry criteria in `docs/DeferredWork.md`; flag state in `docs/FeatureFlagAudit.md`; the
Swift 6.3/iOS 26 concurrency specifics in `docs/Swift 6.3 + iOS 26 Full Migration Plan —
Pocket Casts iOS.md` (Phases 4–6 now complete).
