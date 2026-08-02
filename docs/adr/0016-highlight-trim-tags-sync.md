# Sync highlight trims and tags over account sync, with user edits beating machine enrichment

A Highlight's excerpt window (`excerpt`, `endTime`) was designed as machine-derived
presentation data: devices could legitimately compute different excerpts, so the
file-sync merge used last-writer-wins by op stamp and account sync deliberately
never carried the fields (they exist in `api.proto` as fork fields 1001/1002 but
were never wired). Trim-on-save changes the fields' nature — a trimmed window is
**user-authored content** — and free-form tags are user content from birth. Both
now sync over both sync systems, with two new kinds of state on `SyncUserBookmark`:
`trim_modified` (1003), `repeated string tags` (1004), and `tags_modified` (1005)
in `api.proto` (mirrored at 1002/1003/1004 in the file-sync proto, whose fork
space starts at 1000). The fork backend persists all five fields and returns them
from `user/bookmark/list` (`Api_BookmarkResponse` previously had no fork fields).

Merge semantics, identical in both sync systems:

- **A record whose `trim_modified` is set beats machine-derived enrichment
  regardless of arrival order.** Re-enrichment and auto-suggestion never write to
  a bookmark with a non-nil trim stamp; two user trims resolve LWW by stamp —
  the same rule `title`/`title_modified` already uses.
- **Tags merge as a whole set** (LWW by `tags_modified`), not per-tag. Per-tag
  CRDT merging was rejected: tag sets are small, edited in one sitting on one
  device, and whole-set semantics are what the editor UI actually saves. The
  cost — a concurrent tag edit on a second device loses wholesale — is accepted.
- Alternatives rejected: file-sync-only (account-sync users would get
  silently device-local trims/tags while titles sync — a half-sync users read
  as data loss) and device-local trims with re-enrichment per device (a trim
  made on one device visibly vanishing on the next).

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
