---
name: pr-digest
description: >-
  Launch a fresh omp session in a new herdr pane, name it "pr-digest: YYYY-MM-DD", and hand it a prompt that summarizes the GitHub PRs of the current repository over a time interval, grouped by theme.
  Use when asked for a daily PR digest, or to summarize PRs for today, yesterday, a date range, or the last 24 hours in a new pane, and when reviewing a past pr-digest session against its prompt.
  Requires running inside herdr (HERDR_ENV=1).
disable-model-invocation: true
---

# PR digest

This skill spawns a separate omp session that writes the digest; the invoking agent only launches, names, and checks that session.
Do not do the PR work yourself.
Check that `HERDR_ENV=1` before anything else; if it is unset, say so and stop.
Pane mechanics (split, run, read, get, id compaction) belong to the `herdr` skill; this file states only what the digest needs on top of them.

## Inputs

START and END bound the interval, as ISO 8601 with an offset; the default is the 24 hours ending now in America/New_York.
DATE is END's calendar date as `YYYY-MM-DD` (today by default), and the session title is `pr-digest: DATE`.
ROOT is the current repository root (`jj root 2>/dev/null || git rev-parse --show-toplevel`).
REPO is the GitHub repository to summarize; the default is the current one (`gh repo view --json nameWithOwner -q .nameWithOwner`, run in ROOT).

## Spawn procedure

1. Copy `references/inner-prompt.md` to `/tmp/pr-digest-DATE.md`.
   Replace `{{REPO}}` with REPO, and replace `{{START}}`/`{{END}}` only if the user gave an interval; otherwise leave them, and the spawned session uses the default.
2. Split `$HERDR_PANE_ID` to the right with `--no-focus` and take the new pane id from `result.pane.pane_id`.
3. In the new pane run `cd ROOT && omp --no-title`, with no positional message, so omp generates no title before the rename.
4. Poll `herdr pane read <pane> --source visible` every 2 s until the omp status line (model name and the repository directory name) appears; in testing this took about 2 s.
   Poll rather than use `herdr wait`, which the installed herdr does not provide.
5. Run `herdr pane run <pane> "/rename pr-digest: DATE"` and confirm the pane shows `Session renamed to`.
6. Run `herdr pane run <pane> "Follow the instructions in /tmp/pr-digest-DATE.md exactly."`.
   Keep this message on one line: a multi-line `herdr pane run` can submit before the text is complete, which is why the prompt travels in a file.
7. The session `.jsonl` exists only after the first message, so verify after step 6.
   Read `agent_session.value` from `herdr pane get <pane>` to get the session path, then check in that file that the title entry ends with `pr-digest: DATE` with source `"user"`, and that the agent's first tool call reads `/tmp/pr-digest-DATE.md`.
8. Report the pane id, session path, and title, then stop.

omp has no CLI flag that names a session (only `--no-title`), so `/rename` is the only way to set the title.
omp prefixes titles with an icon and short code, for example `PRS: pr-digest: 2026-11-24`, unless the `title.icons` setting is `boring`; search by `pr-digest: DATE` still matches, which is why step 7 checks the ending.
Pane ids are not durable, so refer to the session by its title after the report.

## Reviewing a past digest

Find the session by its title `pr-digest: DATE`.
While its pane is open, `herdr pane list` shows it, and `herdr pane get <pane>` gives the session path in `agent_session.value`.
After the pane has closed, run `archive.search("pr-digest: DATE")` in the eval tool and take the hit's session `file`.
Read that `.jsonl` and compare the digest against `references/inner-prompt.md`: the PR table printed verbatim, themes as numbered bold headings, PR numbers cited inline, dependency bumps on one Misc line, the merged/open/closed counts, and the closing line on what was read beyond titles.
