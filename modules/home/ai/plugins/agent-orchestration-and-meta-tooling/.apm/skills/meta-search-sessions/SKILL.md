---
name: meta-search-sessions
description: >-
  Search previous Claude Code session transcripts for specific topics, terms, or conversations.
  Use when the user asks to find, recall, or locate a past session, conversation, or discussion
  by topic, keyword, or content. Handles multi-term AND searches, project scoping, and result
  ranking by match density.
---

# Session history search

Search Claude Code session JSONL transcripts stored in `~/.claude/projects/`.

## Workflow

### 1. Interpret the request

Extract from the user's query:

- **Search terms**: 2-5 key phrases that uniquely identify the target session.
  Prefer specific nouns and domain terms over generic words.
  Quoted multi-word phrases in rg are literal matches — use them for compound terms like "architecture diagram".
- **Project scope**: which project directories to restrict to.
  Map user references ("vanixiets", "planning", "sciops") to directory names under `~/.claude/projects/`.
  Common mappings for this user: `vanixiets` -> `-Users-crs58-projects-nix-workspace-vanixiets`, `planning` -> `-Users-crs58-projects-sciexp-planning`.
  Use `ls ~/.claude/projects/` to discover others.
  Omit scope to search all projects.
- **Case sensitivity**: default to case-insensitive (`-i`) unless the user specifies exact-case terms.

### 2. Run the search script

```bash
bash <skill-dir>/scripts/search_sessions.sh \
  -i \
  -d "-Users-crs58-projects-nix-workspace-vanixiets" \
  -d "-Users-crs58-projects-sciexp-planning" \
  "term1" "term2" "term3"
```

The script performs AND-intersection (all terms must appear in the same file) then ranks results by total match count across all terms.

Output columns: file path (relative to `~/.claude/projects/`), file size, per-term counts, and total.

### 3. Present results

Report the top-ranked session(s) with:

- Full path to the JSONL file
- Per-term match counts (indicates which terms dominate the session)
- File size (proxy for session length)
- Whether matches include subagent transcripts (paths containing `/subagents/`)

If the user wants to inspect content from a matched session, extract specific lines:

```bash
rg -i "term" /path/to/session.jsonl -C 0 | head -20
```

For readable extraction of conversation turns containing a term:

```bash
rg -i "term" /path/to/session.jsonl | jq -r '.message.content // empty' 2>/dev/null | head -40
```

### 4. Refinement

If too many results: add more specific terms or narrow project scope.
If zero results: broaden scope, try alternate phrasings, or drop the least-specific term.
