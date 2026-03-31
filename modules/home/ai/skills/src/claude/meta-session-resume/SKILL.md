---
name: meta-session-resume
description: Generate annotated resume command and add to atuin history for session continuation. Triggered by requests to prepare, save, or checkpoint a session for resumption, or "prepare this session for resumption".
argument-hint: [session-uuid] [nohist]
disable-model-invocation: true
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

Implementation approach:
1. Resolve session UUID:
   - If $1 is provided and is not "nohist", use $1 as the UUID
   - Otherwise, auto-detect: `jaq -r '.sessionId' ~/.claude/sessions/$PPID.json`
   - If auto-detection fails, stop and ask the user to provide the session UUID
2. Determine if history addition should be skipped:
   - Check if $1 is "nohist" or $2 is "nohist"
   - Store this as a flag for later use
3. Get current date/time: `date +"%Y%m%d %I:%M%p" | tr 'APM' 'apm'`
4. Construct the full command string with session title
5. Determine if atuin history should be used:
   - If nohist flag is set, skip atuin history (go to step 7 for display only)
   - Otherwise, check if atuin is available: `command -v atuin >/dev/null 2>&1`
     - If atuin is NOT available, skip to step 7 (display only)
     - If atuin IS available, proceed to step 6
6. Add to atuin history using this EXACT pattern:

CRITICAL: The command MUST be wrapped in SINGLE QUOTES after the `--` to preserve the `#` comment character.

Execute these three bash commands sequentially (can use && or separate Bash tool calls):
```bash
id=$(atuin history start -- 'ccds -r <uuid> # <title> <date> <time>')
true
atuin history end --exit 0 $id
```

Step-by-step execution:
1. Resolve session UUID (auto-detect if not provided, see above)
2. Check for nohist flag ($1 or $2 is "nohist")
3. Construct the full command string (e.g., "ccds -r abc123 # My Session 20251010 01:04p")
4. If nohist flag is NOT set, check if atuin is available with: `command -v atuin >/dev/null 2>&1`
   - If atuin is available, execute the following three commands:
     a. Execute: `id=$(atuin history start -- '<full-command-string>')`
        - Note: Single quotes around the ENTIRE command after `--` are REQUIRED
        - The single quotes prevent the shell from treating `#` as a comment
     b. Execute: `true` (just returns exit code 0, do NOT run the actual ccds command)
     c. Execute: `atuin history end --exit 0 $id`
   - If atuin is NOT available OR nohist flag is set, skip the atuin commands
5. Display the command to the user with appropriate message

Example execution:
```bash
id=$(atuin history start -- 'ccds -r 4f44d71c-ab43-46f0-aed6-8fbe0d457a6a # Tmux Floax Debug and GitHub Browse Command 20251010 01:04p')
true
atuin history end --exit 0 $id
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
