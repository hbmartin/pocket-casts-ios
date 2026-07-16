# Profile visibility is a per-field three-tier enum, private by default

Pocket Casts' audience expects granular privacy, and the fork's stance is
**private by default**. Visibility must therefore be controllable per profile element
(avatar, bio, followed shows, top podcasts, stats/heatmap, listening history,
now-playing presence), not as a single profile-wide switch. The desired end state has
three tiers — **public / followers-only / private** — but `followers-only` is
meaningless until the follow graph ships in Phase 2, while identity ships in Phase 1.
We decided to **store the full three-tier enum from day one** and expose only two tiers
in the Phase-1 UI, so there is no data migration when the graph lands and no dead
control in the meantime.

## Consequences

- The schema stores a per-field enum `{public | followers-only | private}`
  (`SocialVisibility`, with `0 = unspecified` treated as private) from the first
  release; Phase 2 lights up `followers-only` with no schema change.
- **Phase-1 UI exposes only public/private** per field. `followers-only` auto-unlocks
  when the graph exists.
- **All fields default to private.** Display name is public once joined (it is the
  addressable identity). The Join flow nudges the user to choose what to expose so a
  freshly-joined profile isn't an empty public page.
- **Privacy prefs live in the profile service, not `NamedSettings`/`ChangeableSettings`.**
  They are server-authoritative access-control policy, enforced at the public read
  (`social/u/{handle}`), and keeping them off the shared settings messages avoids
  adding more hand-edited `_protobuf_nameMap` tripwire surface (see the wire-compat gate
  guarded by `ApiForkSettingsFieldsTests`).
- The public read applies both per-field visibility **and** the viewer's block
  relationship server-side: a blocked or unauthorized viewer never receives fields they
  may not see (a blocked viewer sees the same shape as not-found).
- The three device-local Share Profile toggles (`ShareProfileFollowedPodcasts`/
  `RecentEpisodes`/`Playlists`) default to share-**on** — the opposite of this stance —
  so they are **not** mapped onto server visibility; Join seeds content only.
