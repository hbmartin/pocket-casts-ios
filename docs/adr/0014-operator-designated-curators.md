# ADR-0014: Curators are operator-designated, not self-serve

Date: 2026-07-19 (Slice 15 grill)

## Decision

The Curator flag — a badge plus placement in the Curators directory — is set
only by the operator (a DB/admin act, the same tier as handle reclaim in
ADR-0005). There is no self-serve toggle, no application flow, and no
"verified" language anywhere. Curation content is the account's existing
public Shared Lists and Reviews; designation adds discovery, not powers.

## Why

- A user-visible badge is an editorial signal. Self-designation (the
  considered default) makes the directory a vanity list and the badge
  meaningless; full creator verification is a system the program has
  deliberately deferred. Operator judgment is the smallest honest middle:
  the operator vouches for taste, not identity — hence no "verified".
- Directed at fork scale: the operator personally knows the accounts worth
  listing. An application queue can be added later without schema change
  (the flag is the flag).
- Deliberately NOT auto-gated on content volume: operator judgment owns
  inclusion outright, so the rule stays legible ("the operator listed them").

## Consequences

- Designation on the live backend happens via psql this slice, documented in
  the deploy notes — acceptable at the same tier as reserved-handle seeding.
- The badge renders from a plain boolean riding SocialProfile/PublicProfile;
  erasure needs no new handling (the flag dies with the profile row).
- Expectation management is copy's job: the directory is "Curators", the
  badge is a seal with no wording, and nothing anywhere says "verified".
