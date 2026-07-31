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

- Designation on the live backend happens via the audited psql runbook below,
  at the same authorization tier as reserved-handle seeding.
- The badge renders from a plain boolean riding SocialProfile/PublicProfile;
  erasure needs no new handling (the flag dies with the profile row).
- Expectation management is copy's job: the directory is "Curators", the
  badge is a seal with no wording, and nothing anywhere says "verified".

## Live designation runbook and backend handoff

The production backend must provide the table and column names used by the
commands below before this runbook is executed. That backend change is outside
this repository; its deploy owner must replace the placeholders in the deploy
notes with the reviewed schema-qualified identifiers.

Only an operator with the production social-profile write role may designate
or revoke a curator. Every change requires an approved change ticket containing:

- ticket ID, requested action (`designate` or `revoke`), and justification;
- target immutable user ID and public handle at the time of the change;
- requester, approver, executing operator, and execution timestamp;
- environment, database cluster, command version, affected-row count, and the
  before/after value returned by verification;
- rollback result when rollback is used.

Resolve the immutable user ID from the reviewed ticket before opening the
transaction. Do not target a mutable handle in the write predicate. Pass it to
`psql` with `-v user_id="$CURATOR_USER_ID"`; `:'user_id'` below safely quotes the
client-side variable as a SQL literal. Record the returned row in the ticket:

```sql
BEGIN;
UPDATE <schema>.social_profiles
SET curator = TRUE
WHERE user_id = :'user_id'
  AND curator IS DISTINCT FROM TRUE
RETURNING user_id, handle, curator;
COMMIT;
```

Verify from a fresh read-only session that exactly one profile matches the
immutable ID and that `curator = TRUE`. Re-running the command must update zero
rows and leave the same verified state. Revocation and rollback use the same
procedure with `FALSE`:

```sql
BEGIN;
UPDATE <schema>.social_profiles
SET curator = FALSE
WHERE user_id = :'user_id'
  AND curator IS DISTINCT FROM FALSE
RETURNING user_id, handle, curator;
COMMIT;
```

If identity resolution is ambiguous, the target row is missing, more than one
row is affected, or post-commit verification differs, stop and escalate to the
backend owner. Do not guess or retry with a broader predicate. The backend
handoff is complete only when its deploy documentation names the authorized
role, real identifiers, ticket/audit sink, verification query, and rollback
owner and has exercised designation plus revocation in staging.
