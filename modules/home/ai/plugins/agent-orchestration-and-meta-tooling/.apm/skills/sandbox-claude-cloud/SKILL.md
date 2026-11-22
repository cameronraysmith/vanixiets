---
name: sandbox-claude-cloud
description: Use when experimenting with sandboxed remote development in Claude Code cloud sessions, testing a cloud environment's setup script, or offloading work to the cloud from the CLI; covers claude --cloud, claude -p --cloud, --teleport, choosing the cloud environment, and reading a cloud session's transcript and the commits behind it.
---

# sandbox-claude-cloud

Claude Code cloud sessions (claude.ai/code) run in Anthropic-hosted containers built from a named cloud environment.
From the CLI you can create one, steer it with follow-up messages, and observe it, without attaching a terminal to it.

Core principle: drive the session with `claude --cloud` and `claude -p --cloud`, and observe it through its transcript branch.
Don't use `--teleport` to observe a session: it copies the session, it doesn't connect to it.

In vanixiets, the app `nix run .#claude-cloud-session -- <command>` wraps every step below; `--help` lists its commands.
Read `modules/apps/claude-cloud-session.sh` for the exact mechanics, and `modules/home/users/claude-sandbox/README.md` for the environments, the setup step and the transcript hook.

## The loop

| Step | Raw CLI | vanixiets app |
|---|---|---|
| create | `claude --cloud "<first message>" -n <name>` under a terminal | `create <name> <prompt-file> [--environment-id <env_id>]` (the first message comes from a file) |
| wait | (no CLI command) | `wait <session> [--timeout S]` |
| fetch | (no CLI command) | `fetch <session> [<out>]` |
| query | `jq`, `duckdb` on the JSONL | same |
| steer | `claude -p "<message>" --cloud <session_01…> --output-format json` | `send <session> <message>` |

Repeat wait, fetch, query and steer until done; `prune --older-than <days> [--yes]` removes old transcript branches.
Steer through the app's `send` when you will `wait`: it records how many prompts the next finished turn must hold, and a raw `claude -p` doesn't.
`<session>` is the `session_01…` id or the name `create` gave it; sessions created with the raw CLI are known only by id.

Query a fetched transcript:

```bash
f=logs/claude-sandbox/sessions/session_01….jsonl
jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$f" | tail -n 20
duckdb -c "select type, count(*) from read_json('$f', format = 'newline_delimited', ignore_errors = true) group by type"
```

Read `session.json` without touching the working copy, in a scratch repository:

```bash
g=$(mktemp -d); git init -q --bare "$g"
git --git-dir="$g" fetch -q --depth 1 "$(git remote get-url origin)" claude/transcripts/<session_01…>
git --git-dir="$g" show FETCH_HEAD:session.json | jq .
```

## Choosing the environment

- The CLI uses `remote.defaultEnvironmentId` from the settings, else the newest environment in the account's list; vanixiets sets it to Default for crs58 and cameron, once their home configuration is switched.
- For one session, pass `--settings '{"remote":{"defaultEnvironmentId":"env_…"}}'` (the app's `--environment-id`); `/remote-env` writes the same key. Claude Code's own `--environment` takes only self-hosted `ccpool_…` ids.
- Pick an environment whose setup activates the claude-sandbox profile when you need the transcript branch: elsewhere there is no Stop hook, so `wait` and `fetch` find nothing.

## Rolling out a profile change

A change on `main` reaches cloud sessions only at the environment's next snapshot rebuild.
To roll it out now, add, or replace, the refresh-trigger line before `exit 0` in the environment's setup script, the one sanctioned edit to its stored bootstrap (one approval card).
In vanixiets, print the line with `nix run .#claude-cloud-session -- refresh-line`; the README's refresh-trigger section shows where it goes.

## The transcript branch

After each turn, the profile's Stop hook pushes the session's transcript to `claude/transcripts/<session_01…>`: an orphan branch on the first turn, then one fast-forward commit per turn, holding `<session>.jsonl` and `session.json`.
A gitleaks finding pushes nothing for that turn; vanixiets' hook scans with its own config that allowlists the harness's metadata. A turn has finished when the last user or assistant record is the assistant's, with no `tool_use` waiting for a result.
If the transcript lacks the cloud id, the branch is keyed by the cloud-local uuid and found through `session.json`'s first prompt.

## Three commits, three questions

| Question | Answer | Where |
|---|---|---|
| (a) Which commit was the session's checkout on? | the checkout | `session.json` `.checkout`; `index.tsv` `start_commit` is what the CLI started it from |
| (b) Which commit built this environment, the profile closure? | the setup marker's `rev` | `session.json` `.marker.rev` |
| (c) Which commit's setup app ran? | the setup marker's `tip` | `session.json` `.marker.tip` |

To answer "which commit built this environment", give (b) from `session.json`, not the sha7 in the session's name: that names the start commit, a prediction made before the session existed.
A null marker means the environment ran no claude-sandbox setup, or a snapshot ran none of its own.

## Traps

| Trap | What happens | Do instead |
|---|---|---|
| No terminal | `claude --cloud` needs a TTY | run it under `script -q <log> claude …` (BSD) or `script -qec "…" <log>` (util-linux) |
| Untrusted or wrong cwd | the session can't start, or starts from another repository | run create from a trusted checkout of the repository |
| Positional argument | it is the session's first message, not a name or a flag | put the name in `-n` |
| Unpushed commits | the session starts from the newest pushed commit beneath HEAD; the CLI prints "starts from … (<sha12>)" | push first if the session needs your commits |
| Attaching | `claude --cloud <id>` without `-p` is "not enabled for your account" | steer with `-p --cloud <id> --output-format json`, which returns `{ok, session_id, url}` |
| `--teleport` | makes a local copy with a new session id and a derived-from record, checks out the session's branch, writes the JSONL only after one local turn, and can catch a turn mid-way ("Tool call result not in this copy") | read the transcript branch instead; never teleport into a jj working copy |
| `/rename` | sent with `-p --cloud`, it renames the session internally and shows in its chat, but doesn't change the claude.ai title set by `-n` | choose the name at create time |
| Default environment | without the settings key (a Mac whose home configuration isn't switched yet, say), create without a pin lands on the newest environment in the list, not necessarily the one you mean | set `remote.defaultEnvironmentId` or pass `--settings`; the app's create refuses to run without one of them |
| Hook logs | a Stop hook's log line, and its transcript push, appear only after the turn ends; a turn still running shows nothing | wait for the turn, then read `transcripts.log` or the branch |
| Stale snapshot | the session runs the snapshot's closure, which can predate `main` by days | check `session.json`'s marker and the staleness line; refresh the environment to roll out now |
