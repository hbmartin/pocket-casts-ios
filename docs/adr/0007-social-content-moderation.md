# Social user-generated content is post-moderated with automated pre-filters and community flags

The fork hosts public, user-generated social content (display names, bios, avatars, and
later reviews, comments and clips) with **no premium tier to fund moderation** and a
small operations team. We weighed three models: pre-moderation (approve before public —
safest but doesn't scale and kills the real-time feel), report-and-remove only (cheapest
but vulnerable to brigading), and post-moderation with automated pre-filters plus
community flagging. We chose **post-moderation**: content goes live immediately *after*
passing automated pre-filters, users flag what slips through, and flags feed an
asynchronous triage queue. Mandatory image scanning is non-negotiable once we host
public user images. App Attest (ADR-0003) gates the write paths as first-party abuse
resistance.

## Consequences

- **Every UGC write passes automated pre-filters before publish**: a text classifier on
  names/bios (and later reviews/comments), and a **mandatory CSAM hash-match + nudity
  classifier on every uploaded avatar/thumbnail**. A flagged avatar is never published;
  a CSAM hit additionally enters the mandatory-reporting path.
- Content is **live immediately** after pre-filters. Community flags and automated
  pre-filter hits share **one triage queue**, distinguished by `source`
  (`community_flag` / `auto_text` / `auto_image`). Launch triage is manual (admin view /
  DB); dashboards, trust-weighting, shadow-limiting and appeals are deferred until
  volume justifies them.
- **Anti-spam reuses the existing listen-gate** (`RatePodcastViewModel.swift`,
  `numberOfEpisodesListenedRequiredToRate`) for reviews/comments/reactions — you must
  have listened before you can post.
- **block / mute / report ship with the first UGC surface.** `block` = mutual
  invisibility (cannot follow, mention-resolve or interact); `mute` = one-way hide, the
  muted party is not notified; `report` = a flag into the triage queue.
- **GDPR erasure** clears profile PII and the CDN avatar but tombstones the handle
  (ADR-0005), so erasure and impersonation-resistance coexist.
- Write endpoints (join, avatar, report) carry an **App Attest assertion** over the
  request body, reusing the module built for transcript contributions.
