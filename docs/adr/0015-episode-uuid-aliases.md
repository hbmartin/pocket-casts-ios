# ADR-0015: Episode identity canonicalizes through server-derived aliases

Date: 2026-07-19 (Slice 16 grill)

## Context

The fork has two deterministic episode-uuid schemes that never agree: devices
derive `sha256("au.com.pocketcasts.localfeed:" + guid)` (local-first refresh,
frozen forever by design), while the catalog derives `uuidv5(podcastUuid,
guid)`. Device↔device agrees; server↔device never does. Episode-anchored
social objects (comments, Moments, reactions, shares) therefore fragmented
across uuid spaces — proven in the Slice-15 QA walk.

## Decision

The backend maintains an
`episode_aliases((podcast_uuid, device_uuid) → catalog_uuid)` table with a
unique key on `(podcast_uuid, device_uuid)`. The podcast UUID is required
context for every alias lookup because device UUIDs can collide across shows.
Endpoints that cannot establish an unambiguous podcast UUID fail closed rather
than resolving a device UUID globally.
Because both schemes are pure functions of the feed item's guid (falling back
to the enclosure URL), the crawler derives the device-scheme uuid alongside
its own at every episode ingest and writes the alias — no client changes, no
wire changes, no migration of either scheme. Episode-scoped social endpoints
resolve incoming UUIDs with podcast context and store canonically (catalog
UUID); the listen-gate checks both forms. Reads dual-read the canonical and
device identities immediately so objects created before alias ingestion remain
visible. A one-time startup backfill covers the pre-existing catalog.

Creating or changing an alias also enqueues an idempotent reconciliation in
the same transaction/outbox boundary. Reconciliation rewrites episode-keyed
comments, reactions, shares, listen-gate rows, and any other social references
from the device identity to the canonical identity. It uses natural unique keys
to merge duplicates safely and can be replayed. When two source rows collide
with one unique canonical row, the row with the newest `modified_at` wins;
equal timestamps break ties by the stable source row ID. Dependent rows are
repointed before the losing row is removed. Dual-read remains in place until
reconciliation completion is recorded, so no deployment window hides objects.

## Why not the alternatives

- Migrating the catalog to the device scheme makes uuids literally equal but
  rewrites every catalog row and inherits the device scheme's weaker,
  globally-namespaced identity (guid collisions across shows).
- Sending guids over the wire touches every episode-scoped message, and the
  app does not reliably persist guids.
- Re-keying social on (podcast, guid) is the deepest fix with the same
  client-side guid problem plus a data migration.

## Consequences

- Episodes the catalog has not ingested stay device-keyed until sync-driven
  ingestion (Slice 11) catches up — degradation to today's behavior, never
  breakage. Resolution is a point lookup on writes and a bounded dual-read on
  episode-scoped reads. Ambiguous or missing podcast context fails closed.
- If the device scheme ever changed (it is documented frozen), aliases would
  be derived wrongly; the ADR pins both derivations side by side in
  `crawler/deviceuuid.go` as the single place to keep honest.

## Backend handoff requirements

This repository documents the contract but does not implement the backend.
The backend owner must add the composite uniqueness constraint, require
podcast context in resolver call sites, ship dual-read before or with alias
writes, implement the transactional outbox/reconciler, and cover collision,
retry, partial-failure, and fail-closed ambiguity cases. Rollout verification
must prove that pre-alias objects remain readable before reconciliation and
resolve to one deterministic canonical row afterward.
