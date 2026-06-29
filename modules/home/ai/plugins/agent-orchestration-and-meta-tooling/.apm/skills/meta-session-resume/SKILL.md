---
name: meta-session-resume
description: Generate annotated resume command and add to atuin history for session continuation. Triggered by requests to prepare, save, or checkpoint a session for resumption, or "prepare this session for resumption".
argument-hint: [session-uuid] [nohist]
disable-model-invocation: false
---
Generate a resume session command and automatically add it to atuin shell history.

Command format:

```bash
ccds -r <session-uuid> # Session Title YYYYMMDD HH:MM[a/p]
```

Requirements for session UUID:

- The shell uses `$1` as the uuid when it is provided and is not "nohist", otherwise it auto-detects via `jaq -r '.sessionId' ~/.claude/sessions/$PPID.json`
- When auto-detection yields nothing, the command emits `AUTODETECT_FAILED`; stop and ask the user for the session UUID

Requirements for history addition:

- When "nohist" is passed as `$1` or `$2`, or atuin is unavailable, the command displays without recording (`DISPLAY_ONLY`)
- Otherwise it records the command in atuin history (`ADDED`)

Session title requirements:

- Create concise title (max 80 chars) summarizing the session's key topics and outcomes
- Use current date in YYYYMMDD format (today's date)
- Use 12-hour time format with 'a' or 'p' suffix (e.g., "09:37a", "02:15p")
- Title should match the style of `claude -r` output: noun-focused, action-oriented, covering major topics
- Include all significant topics discussed, prioritizing outcomes over process
- If session covered multiple distinct areas, use "and" to join them concisely
- Avoid single quotes, `$`, backtick, and backslash in the title, since it is interpolated into the double-quoted shell variable `"$cmd"`

Examples of well-formed titles:

- "Performant CLI Tools Evaluation and Git Commit Workflow Improvements"
- "Nix Package Configuration and TypeScript Migration Strategy"
- "Python Type System Refactor with Pydantic v2 Integration"
- "Docker Multi-arch Build Setup and CI Pipeline Optimization"

Execution (single command):

The agent runs exactly one bash command, not a sequence of separate tool calls.
The session title is the only value the model supplies.
The session uuid, the timestamp, atuin availability, and the nohist flag are all derived inside the shell.
The `ccds -r` command itself is never executed; it is only recorded or displayed.

```bash
title='<SESSION TITLE — no single quote, $, backtick, or backslash>'   # the only model-supplied value
case "$1 $2" in *nohist*) nohist=1 ;; *) nohist= ;; esac
uuid="$1"; [ "$uuid" = nohist ] && uuid=
[ -n "$uuid" ] || uuid=$(jaq -r '.sessionId' ~/.claude/sessions/$PPID.json 2>/dev/null)
[ -n "$uuid" ] && [ "$uuid" != null ] || { echo "AUTODETECT_FAILED"; exit 1; }
dt=$(date +"%Y%m%d %I:%M%p" | tr 'APM' 'apm')
cmd="ccds -r $uuid # $title $dt"
if [ -n "$nohist" ] || ! command -v atuin >/dev/null 2>&1; then
  echo "DISPLAY_ONLY: $cmd"
else
  id=$(atuin history start -- "$cmd") && atuin history end --exit 0 "$id" >/dev/null && echo "ADDED: $cmd"
fi
```

Quoting:

Passing the command as a double-quoted variable `"$cmd"` keeps the `#` literal, because the shell does not re-scan the contents of an expanded variable for comments.
This is why the old "wrap in single quotes" rule is no longer needed and has been removed.

Output for user:

The command prints exactly one line; map its sentinel to an action.

- `ADDED: <cmd>` — confirm the command was added to atuin history and show `<cmd>`
- `DISPLAY_ONLY: <cmd>` — history was skipped (nohist was passed or atuin is absent); show `<cmd>` so the user can copy it
- `AUTODETECT_FAILED` — stop and ask the user for the session UUID

Examples:

- `/meta-session-resume` - Auto-detects UUID, generates command, adds to atuin history
- `/meta-session-resume abc123` - Uses provided UUID, generates command, adds to atuin history
- `/meta-session-resume nohist` - Auto-detects UUID, generates command, skips atuin history
- `/meta-session-resume abc123 nohist` - Uses provided UUID, generates command, skips atuin history
- "Prepare this session for resumption" - Natural language trigger, same as `/meta-session-resume`

IMPORTANT: never run `ccds -r` yourself — the command only records or displays the resume string; executing it would spawn a recursive Claude session.
