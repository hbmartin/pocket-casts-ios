# Social avatar contract

Avatar upload is available only when the capability manifest reports it. The
client sends raw JPEG or PNG bytes (maximum 10 MiB) with Bearer authentication
and App Attest. Expected validation/moderation rejections arrive inside the
existing successful protobuf status envelope so the client can display them.

The backend capability **must remain disabled in every public environment**
until a real CSAM scan vendor is integrated as a hard pre-publication gate and
its outage behavior has been acceptance-tested. Capability support in the
client is not permission to enable the feature by itself.

The backend validates decoded dimensions and pixel count before allocation,
normalizes orientation, center-crops, strips metadata, and encodes a 1024×1024
JPEG at quality 85. Google Vision SafeSearch rejects `adult` or `racy` at
`LIKELY` or `VERY_LIKELY`. This is nudity/racy filtering, not CSAM detection.
Scanner outage returns 503 and preserves the previous avatar.

Objects remain private. The public value is a random, versioned backend
capability URL whose database lookup is invalidated on replacement or deletion.
`DELETE /social/avatar` returns 204 and the profile UI exposes removal. Cleanup
for replacement, deletion, account deletion, and social-data erasure runs from a
PostgreSQL outbox so failed object deletion can retry safely.
