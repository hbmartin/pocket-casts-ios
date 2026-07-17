# 9. Activity feed is derived at read time (fan-out-on-read)

Date: 2026-07-17

## Status

Accepted

## Context

The Phase-2 activity feed (Slice 5) shows followees' activity: joined, followed a
person, followed a show, finished an episode, reviewed, reacted. Most social feeds
are **fan-out-on-write**: every action appends immutable event rows (often one copy
per follower), and the feed is a read of that materialized timeline. That shape
scales to millions of users and preserves history exactly as it happened — but it
adds an events table, write amplification on every sync, retention/GDPR surface for
a second copy of user activity, and a hard question this fork's privacy model makes
worse: a stored event was emitted under the visibility settings of *that moment*,
so later privacy changes either leak (events keep showing) or require retroactive
event rewriting.

This fork runs at hobby scale (one Postgres, one app container) and already stores
every fact the feed needs: `social_profiles.created_at`, `social_follows`,
`user_podcasts.date_added`, `user_episodes` playing status, `podcast_reviews`,
`episode_reactions`.

## Decision

The feed is **derived entirely at read time**: one SQL query (`GetFeedItems`) takes
the viewer's active followees minus muted/blocked actors, UNIONs the six event
sources out of their existing tables, applies the actor's **current** per-field
visibility per source (history → finished-episode, followed-shows → followed-show),
orders by event time, and paginates with a before-cursor. No events table, no
queue, no per-follower copies — nothing new is written when someone acts.

## Consequences

- Privacy is always current: flipping a field to private instantly removes the
  derived items everywhere, with no retroactive event scrubbing. This is the
  behavior ADR-0006's "server-authoritative access control" implies.
- GDPR erasure stays trivial — deleting source rows deletes the feed items.
- The trade-off is a scalability ceiling: feed reads cost a multi-table UNION per
  request, and event kinds are limited to what source tables can reconstruct
  (e.g. "followed a show" uses `date_added`, which a resubscribe overwrites).
  At fork scale this is well within one Postgres; if reads ever dominate, a cache
  or materialization can be added *behind* the same wire contract.
- Reversing later (to fan-out-on-write) changes history semantics — materialized
  events freeze the visibility of their emission moment — so any future migration
  must re-derive from sources, not replay stored events. This is the "surprising
  without context" part this ADR exists to explain.
