# Style and Conventions

## Markdown and text formatting

- Write one sentence per line in markdown, text, and documentation files.
- Prefer prose over bullet lists when explaining concepts or providing narrative flow. Reserve bulleted lists for genuinely discrete items or enumerations, not for breaking up what should be continuous explanation.
- Keep section header nesting shallow. Avoid deeply nested subsections (###, ####) when flatter structure with clear prose transitions would be more readable. Most documents should rarely need headers beyond three levels.
- Use bold text (`**`) sparingly, primarily for critical emphasis within sentences. Avoid bolding section labels, definitions, or key terms when plain text suffices. Prefer italic (`*`) for subtle emphasis.
- Avoid using emojis in code, comments, documentation, markdown files, etc unless explicitly requested to do so.
- For documentation-specific markdown conventions (frontmatter titles, header levels), see "Markdown formatting conventions" in `~/.claude/commands/preferences/documentation.md`.

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

- Never pollute the repository root or other working directory with markdown files. Always place these types of working notes in suitable paths like: `./docs/notes/[category]/[lower-kebab-case-filename.md]` where you may need to create the directory if it doesn't exist before creating the file. See "Working notes" in `~/.claude/commands/preferences/documentation.md` for lifecycle management and integration with formal documentation.

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

- Always at least consider testing changes with the relevant framework like bash shell commands where you can validate output, `cargo test`, `pytest`, `vitest`, `nix eval` or `nix build`, a task runner like `just test` or `make test`, or `gh workflow run` before considering any work to be complete and correct.
- Be judicious about test execution. If a test might take a very long time, be resource-intensive, or require elevated security privileges but is important, pause to provide the proposed command and reason why it's an important test.
- Use performant CLI tools matched to task intent:
  - File search (by name/path): use `fd` instead of `find`
  - Content search (within files): use `rg` (ripgrep) instead of `grep`
  - Disk usage (directory sizes): use `diskus` instead of `du -sh`
- When given a GitHub file URL (e.g., `https://github.com/org/repo/blob/ref/path/to/file.ext#L119-L131`), check for a local copy before using web tools:
  1. Search for repo: `fd -t d '^repo$' ~/projects` (repo name may have variants)
  2. Verify remote: `cd candidate-dir && git remote -v` (confirm origin matches GitHub org/repo)
  3. Read the file with line range using the Read tool
  4. Only use WebFetch/WebSearch if no local copy exists
- When given a GitHub issue/PR URL (e.g., `https://github.com/org/repo/issues/2491`), use `gh issue view 2491 -R org/repo` or `gh pr view 2491 -R org/repo` to access discussion content and metadata.
