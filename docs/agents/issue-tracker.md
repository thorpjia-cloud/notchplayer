# Issue tracker

Engineering tasks and specs for notchplayer live in local Markdown under `.scratch/`.

- Put each feature in `.scratch/<feature-slug>/` and its spec in `spec.md`.
- Keep one ticket per file at `issues/<NN>-<slug>.md` within the feature directory.
- Record the triage role on a `Status` line using [triage-labels.md](triage-labels.md).
- Append updates under a `## Comments` heading. Use `Blocked by` followed by ticket numbers for local dependencies.

When a skill asks to publish a spec or ticket, write it to the corresponding local path. When it asks to fetch a ticket, read the specified Markdown file.
