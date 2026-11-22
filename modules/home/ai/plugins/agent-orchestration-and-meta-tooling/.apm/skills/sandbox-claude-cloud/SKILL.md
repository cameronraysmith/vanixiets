---
name: sandbox-claude-cloud
description: Use when experimenting with sandboxed remote development in Claude Code cloud sessions, testing a cloud environment's setup script, or offloading work to the cloud from the CLI; covers claude --cloud, claude -p --cloud, --teleport, choosing the cloud environment, and reading a cloud session's transcript and the commits behind it.
---

# sandbox-claude-cloud

Claude Code cloud sessions (claude.ai/code) run in Anthropic-hosted containers built from a named cloud environment.
From the CLI you can create one and steer it with follow-up messages, without attaching a terminal to it.

**Transcript publishing is disabled.** vanixiets' claude-sandbox profile used to push each turn's transcript to a branch `claude/transcripts/<session>` of its repository, which is public, so every session's content was published, Linear data included.
gitleaks catches credentials, not confidential content, so scanning could not prevent that.
The hook is no longer installed; a replacement that publishes to private R2 storage is planned as `publish-claude-sandbox-transcripts-to-r2`.
Until then, never publish a session's transcript to a public repository, and observe a session by teleporting it (see the traps).

Core principle: drive the session with `claude --cloud` and `claude -p --cloud`; observe it with `claude --teleport`, which copies it rather than connecting to it.

In vanixiets, the app `nix run .#claude-cloud-session -- <command>` wraps create and send; `--help` lists its commands.
Read `modules/apps/claude-cloud-session.sh` for the exact mechanics, and `modules/home/users/claude-sandbox/README.md` (section "Observing a session") for the environments, the setup step and why publishing is off.

## The loop

| Step | Raw CLI | vanixiets app |
|---|---|---|
| create | `claude --cloud "<first message>" -n <name>` under a terminal | `create <name> <prompt-file> [--environment-id <env_id>]` (the first message comes from a file) |
| steer | `claude -p "<message>" --cloud <session_01…> --output-format json` | `send <session> <message>` |
| observe | `claude --teleport <session_01…>` from a scratch clone, never a jj working copy | none: `wait` and `fetch` read transcript branches, which are no longer published, and say so |

`<session>` is the `session_01…` id or the name `create` gave it; sessions created with the raw CLI are known only by id.
`prune` deletes leftover transcript branches: by default only those of the sessions in this machine's `index.tsv`, with `--all` every one; it is a dry run unless given `--yes`.

Query a teleported copy's transcript, which Claude Code writes under `~/.claude/projects/<cwd>/<new-id>.jsonl` after one local turn:

```bash
f=~/.claude/projects/<cwd>/<new-id>.jsonl
jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$f" | tail -n 20
duckdb -c "select type, count(*) from read_json('$f', format = 'newline_delimited', ignore_errors = true) group by type"
```

## Choosing the environment

- The CLI uses `remote.defaultEnvironmentId` from the settings, else the newest environment in the account's list; vanixiets sets it to Default for crs58 and cameron, once their home configuration is switched.
- For one session, pass `--settings '{"remote":{"defaultEnvironmentId":"env_…"}}'` (the app's `--environment-id`); `/remote-env` writes the same key. Claude Code's own `--environment` takes only self-hosted `ccpool_…` ids.

## Rolling out a profile change

A change on `main` reaches cloud sessions only at the environment's next snapshot rebuild.
To roll it out now, add, or replace, the refresh-trigger line before `exit 0` in the environment's setup script, the one sanctioned edit to its stored bootstrap (one approval card).
In vanixiets, print the line with `nix run .#claude-cloud-session -- refresh-line`; the README's refresh-trigger section shows where it goes.
An environment whose snapshot predates a change, including the one that disabled transcript publishing, keeps the old behaviour until that rebuild.

## Three commits, three questions

| Question | Answer | Where |
|---|---|---|
| (a) Which commit was the session's checkout on? | the checkout | `git rev-parse HEAD` in the session, or the teleported branch; `index.tsv` `start_commit` is what the CLI started it from |
| (b) Which commit built this environment, the profile closure? | the setup marker's `rev` | the last line of `/var/log/claude-sandbox-bootstrap/setup.log` in the session |
| (c) Which commit's setup app ran? | the setup marker's `tip` | the same marker line |

To answer "which commit built this environment", give (b) from the marker, not the sha7 in the session's name: that names the start commit, a prediction made before the session existed.
No marker means the environment ran no claude-sandbox setup, or a snapshot ran none of its own.

## Traps

| Trap | What happens | Do instead |
|---|---|---|
| No terminal | `claude --cloud` needs a TTY | run it under `script -q <log> claude …` (BSD) or `script -qec "…" <log>` (util-linux) |
| Untrusted or wrong cwd | the session can't start, or starts from another repository | run create from a trusted checkout of the repository |
| Positional argument | it is the session's first message, not a name or a flag | put the name in `-n` |
| Unpushed commits | the session starts from the newest pushed commit beneath HEAD; the CLI prints "starts from … (<sha12>)" | push first if the session needs your commits |
| Attaching | `claude --cloud <id>` without `-p` is "not enabled for your account" | steer with `-p --cloud <id> --output-format json`, which returns `{ok, session_id, url}` |
| `--teleport` | makes a local copy with a new session id and a derived-from record, checks out the session's branch, writes the JSONL only after one local turn, and can catch a turn mid-way ("Tool call result not in this copy") | teleport only from a scratch clone, never a jj working copy; expect a copy, not a live view, and read it after its first local turn |
| Publishing transcripts | gitleaks catches credentials, not confidential content: a transcript pushed to a public repository publishes everything the session read | never push a transcript to a public repository; wait for the private R2 channel |
| `/rename` | sent with `-p --cloud`, it renames the session internally and shows in its chat, but doesn't change the claude.ai title set by `-n` | choose the name at create time |
| Default environment | without the settings key (a Mac whose home configuration isn't switched yet, say), create without a pin lands on the newest environment in the list, not necessarily the one you mean | set `remote.defaultEnvironmentId` or pass `--settings`; the app's create refuses to run without one of them |
| Hook output | a Stop hook's output appears only after the turn ends; a turn still running shows nothing | wait for the turn to end before reading anything a hook writes |
| Stale snapshot | the session runs the snapshot's closure, which can predate `main` by days | check the setup marker and the staleness line; refresh the environment to roll out now |
