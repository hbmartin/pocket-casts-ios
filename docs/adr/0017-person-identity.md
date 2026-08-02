# Key person identity on a numeric id with aliases and external references, not on the name

Person follows (catalog-wide, server-matched) need an identity that survives what
names cannot: merges when one human appears under spelling variants, splits when
two humans share a name, and future enrichment from external identity systems.
`<podcast:person>` tags carry a display name and only sometimes an `href`, so no
publisher-supplied key is reliable.

The backend stores `person(id, canonical_name, display_name)` with
`canonical_name` **deliberately not unique**, plus `person_alias(person_id,
alias_folded, source)` and `person_external_ref(person_id, scheme, value)` with
`UNIQUE(scheme, value)` — schemes like `wikidata`, `url`, or future semantic-web
vocabularies. `person_follow(account_id, person_id)` references the numeric id,
so identity corrections (merge, split, alias addition, external-ref attachment)
never rewrite follow edges. The v1 resolution heuristic at feed ingest is one
person per folded name (the same case- and diacritic-insensitive folding rule
the iOS client uses for Mentioned Entities); the schema, not the heuristic, is
the commitment. Rejected: name-string keys (every future identity correction
becomes a migration of user follow data) and href-first identity (most feeds
carry no href, leaving a two-tier lookup that still falls back to names).

The iOS client keeps its v1 name-keyed presentation (two same-named humans merge
into one directory entry — a documented limitation) but all server interactions
use `person.id`.

## Consequences

- Backend milestone B2 (schema, `<podcast:person>` ingest extraction, alias
  resolution, follow endpoints on the App Attest route matrix, APNs fan-out,
  `person_follows` capabilities flag) must be live in production before the
  `personFollows` iOS flag is enabled.
- "Catalog-wide" factually means feeds the fork backend ingests — not the
  entire podcast universe; product copy must not overpromise.
- A person split leaves existing follows attached to the surviving entity;
  followers of a split person are not re-asked. Accepted as the cost of
  never rewriting user data.
- Wikidata (or similar) imports later are additive rows in
  `person_external_ref` — no schema change, no follow migration.
- This ADR is mirrored in `hbmartin/podcast-backend`; the folding rule is
  documented in both repos and must stay identical.
