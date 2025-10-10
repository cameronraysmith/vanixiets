---
argument-hint: [session-uuid]
description: Generate annotated resume command for current session
---

Generate a resume session command for the current conversation in this exact format:

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

Implementation approach to avoid shell parse errors:
1. Extract UUID in separate bash command: `readlink ~/.claude/debug/latest | grep -oE '[pattern]'`
2. If user provided $ARGUMENTS, use that instead of extracted value
3. Build and output the formatted command string
4. Output only the command, nothing else

To avoid parse errors, use multiple sequential bash commands rather than complex one-liners with command substitution.
