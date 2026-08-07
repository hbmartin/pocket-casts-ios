# The document, not the narration, is Read Aloud's durable unit

Read Aloud stores two device-local tables (migration 91). A `ReadAloudDocument`
owns the retained `.txt`/`.md` file under `Documents/read_aloud/sources/<uuid>`
and everything derived from reading it — title, character count, detected
language, source kind. A `Narration` is one attempt to render that document in
one voice: engine, voice, pipeline state, checkpoint, and the episode it
produced. A document may carry any number of narrations over its life, and they
all read the same source file.

The obvious simpler design — one table, where the file *is* the row and
`sourcePath` hangs off the narration — is what this feature was first built as,
and it fails on the operation users reach for immediately: **"read this again,
but with a better voice."** With one table that is a fresh import, so the same
document arrives twice with two copies of the file, two rows with identical
titles, and no relationship between them. Renaming one leaves the other alone.
Deleting one leaves an orphan the user thinks they already dealt with. The
duplication is cheap in bytes and expensive in meaning: the model asserts these
are unrelated documents, and every screen then has to pretend otherwise.

Separating them also gives "no audio right now" somewhere to live. Under the
one-table design the only way to express a document whose episode had been
deleted was a `detached` narration — a row in state *completed, but the output is
gone*, which every query and list row had to special-case. With a document table
the state disappears: deleting the episode deletes its narration, and a document
with no narrations is an ordinary resting state that needs no explanation.

Rejected: a `documentUuid` grouping column on a single table (shares the file,
but leaves title and metadata duplicated per row with no answer for which copy
wins on rename), and keeping one table with per-narration file copies (accepts
permanent duplication to avoid a join).

## Consequences

- Deleting a document is the only cascade: it removes every narration against it,
  their episodes and workspaces, and the source file. `deleteDocument` returns
  the narrations it removed so the caller can do the filesystem and episode work,
  since the data manager owns neither.
- Deleting an episode removes only its narration (ADR-0019). The two directions
  are deliberately asymmetric.
- One source file per document means re-narration is free and a partially
  written import cannot strand a file: the document and its first narration are
  inserted in one transaction, and the file is removed if that insert fails.
- Renaming is a document-level operation, so every narration of it re-titles at
  once. The episode title is captured at materialization and does not follow a
  later rename — an episode is an artifact, not a live view.
- A document with no narrations is expected, not exceptional: it is what episode
  deletion leaves, and what the library screen offers a "Narrate" button on.
