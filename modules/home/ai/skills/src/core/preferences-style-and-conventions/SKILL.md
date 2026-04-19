---
name: preferences-style-and-conventions
description: Style and formatting conventions for code, documentation, naming, and file organization. Load when reviewing style consistency or setting up new files.
---

# Style and Conventions

## Markdown and text formatting

- Write one sentence per line in markdown, text, and documentation files.
- Prefer prose over bullet lists when explaining concepts or providing narrative flow. Reserve bulleted lists for genuinely discrete items or enumerations, not for breaking up what should be continuous explanation.
- Keep section header nesting shallow. Avoid deeply nested subsections (###, ####) when flatter structure with clear prose transitions would be more readable. Most documents should rarely need headers beyond three levels.
- Use bold text (`**`) sparingly, primarily for critical emphasis within sentences. Avoid bolding section labels, definitions, or key terms when plain text suffices. Prefer italic (`*`) for subtle emphasis.
- Avoid using emojis in code, comments, documentation, markdown files, etc unless explicitly requested to do so.
- For documentation-specific markdown conventions (frontmatter titles, header levels), see "Markdown formatting conventions" in `~/.claude/skills/preferences-documentation/SKILL.md`.

## Naming and case conventions

- Prefer lowercase except when replicating code conventions like PascalCase or camelCase, in acronyms, or in proper nouns.
- Do prefer to capitalize the first letter of the first word and use Chicago Manual sentence-style capitalization for
    - complete sentences that end with punctuation marks
    - markdown file title frontmatter, section headings, and any level of subsection heading
- Do not use uppercase words for emphasis or notification purposes like "IMPORTANT", "URGENT", "WARNING", etc except in relevant situations like error handling, logging, or quoting usage by other sources.
- Do not name files with all uppercase letters. Use lowercase kebab-case specifically for markdown filenames or if there is no specific convention for the programming language or filetype (e.g. python uses snake_case).

## Factual commentary

Avoid presumptive, negatively judgmental, or editorializing language in code comments, documentation, and commit messages.
State what code does, not speculative narratives about why.

- Do not speculate about causes, motivations, or intent when you only observed an effect.
- Do not attribute habits or patterns from single observations ("often", "always", "usually", "tends to").
- Do not add evaluative judgment where factual description suffices.
- Reference relevant sources like documentation rather than inventing explanations.

## File organization

- Never pollute the repository root or other working directory with markdown files. Always place these types of working notes in suitable paths like: `./docs/notes/[category]/[lower-kebab-case-filename.md]` where you may need to create the directory if it doesn't exist before creating the file. See "Working notes" in `~/.claude/skills/preferences-documentation/SKILL.md` for lifecycle management and integration with formal documentation.

### File length and modularization

Files should remain comprehensible as cohesive units.
As files grow, split along responsibility boundaries rather than at arbitrary line counts.

Soft guidance thresholds:
- Under 500 lines: generally appropriate
- 500-800 lines: consider extracting distinct sections
- Beyond 800 lines: likely needs splitting unless genuinely single-purpose

For code, extract modules with clear interfaces using the language's import mechanism.
For documentation, create index files linking to subpages or organize into subdirectories.

Create subdirectories when extractions form natural hierarchies or exceed 4-5 related files; otherwise sibling files with cross-references suffice.

Avoid splitting when it would fragment a genuinely cohesive unit or create excessive coupling through circular references.

## Development workflow and tooling

### Pre-implementation checkpoint

Before transitioning from planning to implementation, materialize the plan into concrete commitments.
Determine precisely which files and directories will be modified, created, or removed.
Define the grouping and sequence of commits with draft commit messages.
Specify how each commit or collection of changes will be verified as useful progress: passing new or existing tests, producing observable output, improving conceptual clarity, or satisfying other criteria appropriate to the change.
This checkpoint converts abstract plans into auditable intentions, reducing rework from misaligned assumptions.
For each proposed change, identify the confidence level the verification plan is expected to achieve and whether the verification would be severe — would it fail under plausible incorrect implementations?
See `preferences-validation-assurance` for the severity criterion and confidence promotion chain.
When working within a beads issue graph, map each proposed file change to the issue it addresses and confirm the change will satisfy that issue's acceptance criteria.

- Always at least consider testing changes with the relevant framework like bash shell commands where you can validate output, `shellcheck` for shell scripts, `cargo test`, `pytest`, `vitest`, `nix eval` or `nix build`, a task runner like `just test` or `make test`, or `gh workflow run` before considering any work to be complete and correct.
- Be judicious about test execution. If a test might take a very long time, be resource-intensive, or require elevated security privileges but is important, pause to provide the proposed command and reason why it's an important test.
- Local test execution is the primary feedback loop during development.
  Run tests iteratively as you work, fixing issues before committing.
  CI workflow verification is a distinct stage that occurs when validating a branch for merge/pull request, not during routine local development.

### CI workflow log verification

When validating changes for merge, verify CI results by downloading and analyzing complete workflow logs rather than piecing together fragments via repeated API calls.

Wait for relevant workflows to complete:
```bash
gh run watch <run_id>
# or poll with: gh run list --branch <branch> --status completed
```

Download the complete logs archive:
```bash
run_id=<run_id>
mkdir -p logs
gh api "repos/<owner>/<repo>/actions/runs/${run_id}/logs" > "logs/gha-${run_id}.zip"
unzip -d "logs/gha-${run_id}" "logs/gha-${run_id}.zip"
```

Survey available jobs and steps:
```bash
tree --du -ah "logs/gha-${run_id}"
```

#### Unified PR check log retrieval

Given only a pull request number, the unified entry point for discovering which checks ran and where their logs live is `PAGER=cat gh pr checks <N>`.
This command emits one row per check with a direct link, spanning both CI backends used by repositories in this workspace.
GitHub Actions rows link to `https://github.com/<owner>/<repo>/actions/runs/<run_id>/job/<job_id>`.
Buildbot-nix rows link to `https://buildbot.scientistexperience.net/#/builders/<builder_id>/builds/<build_number>` and correspond to the `buildbot/nix-eval` and `buildbot/nix-build` status checks described in `preferences-nix-ci-cd-integration`.

Use the JSON output to separate the two categories and drive automation:
```bash
gh pr checks <N> --json name,link \
  | jq -r '.[] | select(.name | test("^buildbot/")) | .link'
gh pr checks <N> --json name,link \
  | jq -r '.[] | select(.link | test("/actions/runs/")) | .link'
```

Route each link to its backend-specific log-download recipe, writing artifacts under a single `logs/` directory (already gitignored):
```bash
mkdir -p logs

# GitHub Actions — extract <run_id> from the /runs/<run_id>/job/... URL path
run_id=<run_id>
gh api "repos/<owner>/<repo>/actions/runs/${run_id}/logs" > "logs/gha-${run_id}.zip"
unzip -d "logs/gha-${run_id}" "logs/gha-${run_id}.zip"

# Buildbot-nix — extract <builder_id> and <build_number> from the fragment
# /#/builders/<builder_id>/builds/<build_number>
builder_id=<builder_id>
build_number=<build_number>
buildbot-logs "${builder_id}" "${build_number}" > "logs/buildbot-${builder_id}-${build_number}.log"
```

The `buildbot-logs` shell application is defined in this repository; see `preferences-nix-ci-cd-integration` for its interface, ssh transport, and authentication model.
After download, survey each artifact before dispatching subagents for targeted analysis:
```bash
tree --du -ah "logs/gha-${run_id}"
rg "error:" "logs/buildbot-${builder_id}-${build_number}.log"
```

Dispatch subagent Tasks to analyze specific log files for the problem at hand rather than manually reading large logs inline.
This approach provides a complete, well-organized view of CI results and avoids the antipattern of fragmented API-based log retrieval that never yields a clear picture of what happened.
- Use performant CLI tools matched to task intent:
  - File search (by name/path): use `fd` instead of `find`
  - Content search (within files): use `rg` (ripgrep) instead of `grep`
  - Disk usage (directory sizes): use `diskus` instead of `du -sh`
  - Clipboard (copy to system clipboard): use `cb copy` (`clipboard-jh`) instead of platform-specific `pbcopy` (macOS) or `xclip`/`xsel` (Linux)
  - Notification (push alert to user): use `ntfy-send "<message>"` where `<message>` includes the repo name and summarizes the completed task (default topic is the local hostname; override with `ntfy-send "<message>" <topic>`)
- When given a GitHub file URL (e.g., `https://github.com/org/repo/blob/ref/path/to/file.ext#L119-L131`), check for a local copy before using web tools:
  1. Search for repo: `fd -t d '^repo$' ~/projects` (repo name may have variants)
  2. Verify remote: `cd candidate-dir && git remote -v` (confirm origin matches GitHub org/repo)
  3. Read the file with line range using the Read tool
  4. Only use WebFetch/WebSearch if no local copy exists
- When given a GitHub issue/PR URL (e.g., `https://github.com/org/repo/issues/2491`), use `gh issue view 2491 -R org/repo` or `gh pr view 2491 -R org/repo` to access discussion content and metadata.
