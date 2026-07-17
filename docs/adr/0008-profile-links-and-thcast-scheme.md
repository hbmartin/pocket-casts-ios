# Profile links are backend-served, and thcast:// hard-replaces pktc://

ADR-0005 promised profile pages at `pca.st/u/<handle>`, but that domain belongs to
upstream Pocket Casts: its AASA file will never list this fork's team/bundle (so
universal links cannot open this app) and its server would 404 the path. Shipping
that URL means shipping dead links. We decided the **canonical Profile Link is
served by the fork's own backend** — `PUBLIC_BASE_URL/u/<handle>` (the backend
already carries `PUBLIC_BASE_URL` in config and serves the visibility-filtered
public read; it gains a minimal HTML page at that path). For app-to-app opening
the fork registers its own URL scheme, **`thcast`**, and **hard-replaces `pktc`**:
the upstream scheme is dropped from the Info.plist registration and every outbound
link (widgets, shortcuts, notifications, social) is rewritten.

## Consequences

- Share cards and share sheets print `PUBLIC_BASE_URL/u/<handle>` — reachable the
  day it ships (locally `http://127.0.0.1:8000/u/<handle>`), and upgrading to a
  real domain later is a config change, not a link-format change.
- `thcast://profile/<handle>` opens the profile in-app; the URL handler also
  recognizes `/u/<handle>` paths on the configured backend host.
- **Deliberate breakage:** anything already baked with `pktc://` — installed
  widgets, user Shortcuts, scheduled notification payloads — stops opening the
  app until re-created. Accepted as a one-time cost of fork identity; chosen over
  keeping `pktc` registered as a compatibility alias.
- ADR-0005's `pca.st/u/<handle>` is reclassified as aspirational upstream
  branding (see the Profile Link glossary entry); nothing prints it.
