# 11. Shared lists are social objects with mirrored playlists

Date: 2026-07-18

## Status

Accepted

## Context

Slice 7 delivers §8's collaborative + subscribable lists — the program's first
*multi-writer* object — and with it the long-flagged question of the
custom-playlist sync exclusion. The exclusion turned out narrower than the
roadmap assumed: manual playlists (explicit episode membership) already sync
end-to-end; only custom (query-envelope) playlists were excluded, because
`customQuery` had no wire field and no backend column. Collaboration, however,
cannot ride device sync at all: the sync protocol moves one account's state
between that account's devices, and merging several accounts' edits inside it
means implicit conflict machinery in a channel nobody audits for it.

## Decision

1. **A shared list is a first-class server object** (`social_lists` +
   entries + members), edited through explicit operations (add/remove/move,
   server-authoritative last-write-wins) by the owner and invited
   collaborators. Consent is explicit: invites are accepted or declined;
   the owner can kick; entries carry "added by" attribution. Visibility
   reuses the ADR-0006 tiers, and followers/public lists ride the profile.
   The list dies with its owner (Shared Item precedent); an erased
   collaborator's entries survive with attribution wiped (ADR-0010
   philosophy).
2. **Local playlists mirror the server object.** Collaborator/subscriber
   mirrors are server-derived caches — refreshes REBUILD them rather than
   merge. The owner's published playlist is deliberately never rebuilt: it
   keeps syncing as a normal manual playlist, and the shared-list screen is
   where the shared truth (including others' additions) lives.
3. **The sync overturn is orthogonal**: `custom_query = 1001` — a fork-owned
   field on the shared upstream playlist messages (≥1001 convention, guarded
   by `ApiForkPlaylistFieldsTests`) — plus a backend column. Custom playlists
   now sync between an account's devices but stay personal: **queries never
   share**. Publishing a smart/custom playlist *materializes* its current
   results into a new shared manual list.

## Consequences

- Multi-writer state lives where moderation, blocking, visibility, and GDPR
  erasure already operate; device sync stays single-writer and boring.
  The cost is a second write path for list edits (ops vs sync records) and
  read-through mirrors that can lag until the next refresh.
- Rebuild-not-merge makes mirrors trivially correct but discards nothing
  local — mirrors hold no local-only state by construction. The owner-side
  asymmetry (their playlist is not auto-reconciled with collaborator
  additions) is the deliberate price of never merging into a syncing
  playlist; revisit only with real conflict machinery.
- Materialize-to-share means a "shared smart list" is a snapshot, not a live
  query — sharper than explaining per-viewer query results, but users must
  republish to refresh a snapshot.
- En route, the overturn surfaced a latent backend bug (playlist records
  without `episode_order` stored SQL NULL and 500ed) — fixed by coalescing;
  any smart-playlist sync had been affected.
