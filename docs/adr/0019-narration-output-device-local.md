# Read Aloud narration output is device-local, never folder-backed

Since the local-first reversal, every `UserEpisode` in the Files library is
owned by the uploads folder: `UserEpisodeManager.addUserEpisode` copies the file
into `Uploads/` (iCloud Drive by default), stamps `folderRelativePath` and a
provisional identity, and `UploadsScanner` reconciles it from then on. Read
Aloud deliberately creates the one class of user episode that is *not* that. Its
rendered `.m4a` stays in the local download cache with `folderRelativePath ==
nil`, carrying `groupName = "Read Aloud"` for its Files-screen section, via a new
`UserEpisodeStorage` parameter whose `.syncFolder` default leaves every existing
call site behaving exactly as before.

Three reasons. **Quota**: narration audio is regenerable output derived from a
text file the user already has; pushing hours of synthesized speech into someone's
iCloud Drive spends a paid resource on something reproducible from a ~50 KB
document. **Half-provenance**: a Narration row and its source document are
device-local by design, so a synced episode would arrive on a second device as
audio with no way to view its text, re-narrate it, or explain where it came from —
worse than its absence. **Blast radius**: the scanner mints and deletes episode
rows from folder contents, and keeping generated files outside its view means a
scan can never re-key or remove a narration's episode behind the queue's back.

Rejected: writing into `Uploads/Read Aloud/` (cross-device audio, at the cost of
all three above), and a `.pcnarration` sidecar in the folder to carry provenance
(invents a sync format for a feature whose entire model is device-local).

## Consequences

- Narration audio does not follow the user to another device. Re-narrating there
  is the intended path, and it is cheap because the built-in engine is free.
- Deleting the episode is not deleting the document. `UserEpisodeDeleted`
  detaches the Narration (`episodeUuid` → NULL, state `detached`) and the source
  file survives, so a swipe on a crowded Files screen can never destroy user
  content. Only deleting the document itself removes both.
- `folderRelativePath == nil` means the existing "Delete from device" path
  applies and the "Delete Everywhere" / re-download affordances do not — correct,
  since there is no remote copy. Recovery is regeneration, which is why the
  source document is retained permanently.
- The Files screen needed no change: it lists `allUserEpisodes` grouped by
  `groupName`, while `UploadsScanner` only ever projects
  `allFolderBackedUserEpisodes()`.
- `groupName` stores the literal `"Read Aloud"` rather than a localized string,
  matching every other group name (which are literal folder names). Localizing it
  would split the section in two the first time a user changed their language.
