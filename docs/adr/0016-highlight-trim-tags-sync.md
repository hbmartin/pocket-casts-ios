# Sync highlight trims and tags over account sync, with user edits beating machine enrichment

> **2026-08-04 note: account-sync-only now.** The local-first reversal removed
> the library file-sync engine, and with it this contract's historical
> file-sync path for trims/tags. (The repository's uploads-folder file-sync
> components remain active but never carried these fields.) `api.proto` fields
> 1001–1005, the SyncTask changes, and the account-sync merge semantics below
> are now the only cross-device path for trims/tags (gated on
> `FeatureFlag.highlightAccountSync` until backend B1 ships).

A Highlight's excerpt window (`excerpt`, `endTime`) was originally designed as
machine-derived presentation data, and account sync deliberately did not carry
the fields (they existed in `api.proto` as fork fields 1001/1002 but were not
wired). Trim-on-save changes the fields' nature — a trimmed window is
**user-authored content** — and free-form tags are user content from birth. Both
now sync over account sync, with two new kinds of state on `SyncUserBookmark`:
`trim_modified` (1003), `repeated string tags` (1004), and `tags_modified` (1005)
in `api.proto`. The fork backend persists all five fields and returns them from
`user/bookmark/list` (`Api_BookmarkResponse` previously had no fork fields).

Account-sync merge semantics:

- **A record whose `trim_modified` is set beats machine-derived enrichment
  regardless of arrival order.** Re-enrichment and auto-suggestion never write to
  a bookmark with a non-nil trim stamp; two user trims resolve LWW by stamp —
  the same rule `title`/`title_modified` already uses.
- **Tags merge as a whole set** (LWW by `tags_modified`), not per-tag. Per-tag
  CRDT merging was rejected: tag sets are small, edited in one sitting on one
  device, and whole-set semantics are what the editor UI actually saves. The
  cost — a concurrent tag edit on a second device loses wholesale — is accepted.
- An account-sync implementation is required because device-local trims with
  re-enrichment per device would make a trim visibly vanish on another device.

## Consequences

- Backend milestone B1 (bookmark columns + merge + list response + the fork
  settings fields for review-after-capture, prompt style, and confirmation
  style) must be **live in production before `highlightAccountSync` is
  enabled**; the iOS wiring ships dark behind that flag.
- `excerpt` stops being safely regenerable: any future re-enrichment sweep must
  filter on `trim_modified IS NULL`.
- The glossary's Highlight entry drops "write-once"; the enricher's write-once
  guard remains for the *auto* path only.
- Tag identity is the case-insensitively-folded string; renames are
  remove+add, so there is no tag-rename sync story to design.
