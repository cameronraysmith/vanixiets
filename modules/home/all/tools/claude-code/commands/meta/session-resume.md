---
argument-hint: [session-uuid]
description: Generate annotated resume command and add to atuin history
---

Generate a resume session command and automatically add it to atuin shell history.

Command format:
```bash
ccds -r [session-uuid] # Session Title YYYYMMDD HH:MM[a/p]
```

Requirements for session UUID:
- If user provides $ARGUMENTS (session UUID as argument), use that value
- Otherwise, extract from `~/.claude/debug/latest` symlink using: `readlink ~/.claude/debug/latest | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'`
- If extraction fails and no argument provided, use placeholder `<session-uuid>`
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
1. Get current date/time: `date +"%Y%m%d %I:%M%p" | tr 'APM' 'apm'`
2. Extract UUID from $ARGUMENTS or `readlink ~/.claude/debug/latest | grep -oE '[pattern]'`
3. Construct the full command string with session title
4. Add to atuin history using this EXACT pattern:

CRITICAL: The command MUST be wrapped in SINGLE QUOTES after the `--` to preserve the `#` comment character.

Execute these three bash commands sequentially (can use && or separate Bash tool calls):
```bash
id=$(atuin history start -- 'ccds -r <uuid> # <title> <date> <time>')
true
atuin history end --exit 0 $id
```

Step-by-step execution:
1. First, construct the full command string (e.g., "ccds -r abc123 # My Session 20251010 01:04p")
2. Execute: `id=$(atuin history start -- '<full-command-string>')`
   - Note: Single quotes around the ENTIRE command after `--` are REQUIRED
   - The single quotes prevent the shell from treating `#` as a comment
3. Execute: `true` (just returns exit code 0, do NOT run the actual ccds command)
4. Execute: `atuin history end --exit 0 $id`

Example execution:
```bash
id=$(atuin history start -- 'ccds -r 4f44d71c-ab43-46f0-aed6-8fbe0d457a6a # Tmux Floax Debug and GitHub Browse Command 20251010 01:04p')
true
atuin history end --exit 0 $id
```

Output for user:
- Show a brief message confirming the command was added to atuin history
- Display the command that was added (the full ccds -r ... line)

IMPORTANT: Do NOT actually execute `ccds -r` as it would create a recursive Claude session. Use `true` as a placeholder.
