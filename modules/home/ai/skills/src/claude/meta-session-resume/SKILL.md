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

- If $1 is provided and is a valid UUID, use $1 as the session UUID
- If $1 is "nohist" or blank, auto-detect the UUID via: `jaq -r '.sessionId' ~/.claude/sessions/$PPID.json`
- If auto-detection fails (file missing or jaq unavailable), stop and ask the user to provide the session UUID

Requirements for history addition:

- If $1 is "nohist" or $2 is "nohist", skip atuin history addition and just display the command
- Otherwise, attempt to add to atuin history (if available)

Session title requirements:

- Create concise title (max 80 chars) summarizing the session's key topics and outcomes
- Use current date in YYYYMMDD format (today's date)
- Use 12-hour time format with 'a' or 'p' suffix (e.g., "09:37a", "02:15p")
- Title should match the style of `claude -r` output: noun-focused, action-oriented, covering major topics
- Include all significant topics discussed, prioritizing outcomes over process
- If session covered multiple distinct areas, use "and" to join them concisely

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

Output for user:

- If auto-detection fails and no UUID provided:
  - Stop and ask the user to provide the session UUID
- If nohist flag is set:
  - Show a message that history addition was skipped per user request
  - Display the command (the full ccds -r ... line)
- If nohist flag is NOT set and atuin is available:
  - Show a brief message confirming the command was added to atuin history
  - Display the command that was added (the full ccds -r ... line)
- If nohist flag is NOT set and atuin is NOT available:
  - Show a message that atuin is not available
  - Display the command (the full ccds -r ... line) that would have been added
  - Suggest the user can copy and paste it manually

Examples:

- `/meta-session-resume` - Auto-detects UUID, generates command, adds to atuin history
- `/meta-session-resume abc123` - Uses provided UUID, generates command, adds to atuin history
- `/meta-session-resume nohist` - Auto-detects UUID, generates command, skips atuin history
- `/meta-session-resume abc123 nohist` - Uses provided UUID, generates command, skips atuin history
- "Prepare this session for resumption" - Natural language trigger, same as `/meta-session-resume`

IMPORTANT: Do NOT actually execute `ccds -r` as it would create a recursive Claude session. Use `true` as a placeholder.
