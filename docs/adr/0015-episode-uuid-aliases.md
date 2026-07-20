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

The backend maintains an `episode_aliases(device_uuid → catalog_uuid)` table.
Because both schemes are pure functions of the feed item's guid (falling back
to the enclosure URL), the crawler derives the device-scheme uuid alongside
its own at every episode ingest and writes the alias — no client changes, no
wire changes, no migration of either scheme. Episode-scoped social endpoints
resolve incoming uuids through the table and store canonically (catalog
uuid); the listen-gate checks both forms. A one-time startup backfill covers
the pre-existing catalog.

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
  breakage. Resolution is a point lookup on writes and episode-scoped reads.
- If the device scheme ever changed (it is documented frozen), aliases would
  be derived wrongly; the ADR pins both derivations side by side in
  `crawler/deviceuuid.go` as the single place to keep honest.
