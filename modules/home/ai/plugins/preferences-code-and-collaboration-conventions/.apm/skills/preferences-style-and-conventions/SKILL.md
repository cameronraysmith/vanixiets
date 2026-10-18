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
- For documentation-specific markdown conventions (frontmatter titles, header levels), see "Markdown formatting conventions" in `preferences-documentation`.

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

## Code comments

Write code that explains itself through naming, structure, and types, and add a comment only when the code cannot carry the information on its own.
This extends the "Factual commentary" stance above: state what the code does through the code itself, and reserve comments for what the code genuinely cannot express.
Prefer docstrings and language-canonical doc comments over inline comments.
Doc comments are API-contract documentation and flow into generated `docs/reference/` material, so the language skills' requirements for them (Rust `///` and `//!`, Haskell Haddock, Python and TypeScript docstrings, nix module option descriptions) remain in force and are out of scope for the rule below.

An inline comment earns its place only when it records something a competent reader could not recover from the code itself.
Qualifying circumstances are narrow: a non-obvious *why* behind a choice that is true and not a speculative narrative; a surprising external constraint such as an API quirk, hardware limit, or protocol-mandated ordering not visible locally; a workaround for an external bug, paired with a link to the upstream issue or pull request; a correctness, security, concurrency, or numerical-stability footgun the next editor would plausibly reintroduce; or a deliberate, counterintuitive deviation from the obvious approach, stating why the obvious approach fails.
The operative test is whether deleting the comment would lose information that the code, its names, and its types do not already provide.
If nothing is lost, it does not qualify.

Comments that fail this bar are noise: restating the code in prose, narrating control flow the structure already shows, section-divider banners, commented-out code (delete it; version control retains the history), and TODO or FIXME notes without an issue reference or owner.
Treat removing such comments as a standing responsibility rather than one gated to the file or change you are currently working on: when you encounter noise comments in the project's own code, remove them, and a comment-only cleanup is a legitimate standalone change.
This breadth is bounded by safety rails that are never relaxed.
Never alter vendored, third-party, generated, upstream-mirrored, or otherwise externally-owned trees, including any path bearing a `DO NOT EDIT` marker or designated by the repository as a mirror.
Never remove any item in the load-bearing list below.
When uncertain whether a comment is load-bearing or whether a tree is externally owned, leave it and surface the question rather than deleting; the cost of deleting one rationale-bearing comment exceeds the cost of leaving several redundant ones.

Some comments are load-bearing and must never be removed or rewritten as incidental cleanup, regardless of the bar above:

- License and SPDX headers, and copyright banners required by license terms.
- Shebang lines (`#!/usr/bin/env bash`, `#!/usr/bin/env python3`).
- Source encoding declarations (`# -*- coding: utf-8 -*-`).
- Linter and type-checker pragmas: `# type: ignore`, `# noqa`, `# pyright: ignore`, `# ruff: noqa`, `# shellcheck disable=SCxxxx`, `// eslint-disable`, `// @ts-expect-error`, GHC `{-# ... #-}` pragmas.
- Formatter directives: `# fmt: off` and `# fmt: on`, `// prettier-ignore`, nix formatter control comments, `// rustfmt::skip`.
- Public-API docstrings and doc comments that generate published documentation. Preserve these even when terse; tighten wording only as a deliberate documentation edit.
- Rust `// SAFETY:` comments on unsafe blocks, and the per-exclusion "explain why" comments other skills require (for example nix-unit package exclusions); these are the canonical truly-exceptional cases.
- Code-generation markers (`// Code generated ... DO NOT EDIT.`, `# Generated by ...`, managed-block `BEGIN` and `END` sentinels) and any comment parsed by tooling as a directive (`//go:generate`, `// go:build` and cfg conditional-compilation comments, `cython:` directives, dependency-pin annotations).

This policy is intentionally strong because self-documenting code is the default expectation across the fleet (nix, python, rust, haskell, typescript, shell).
Ousterhout's calibration applies: comments exist to capture design intent and rationale that genuinely cannot live in the code, so the goal is eliminating redundant comments, not the rationale-bearing ones the qualifying list protects.

## File organization

- Never pollute the repository root or other working directory with markdown files. Always place these types of working notes in suitable paths like: `./docs/notes/[category]/[lower-kebab-case-filename.md]` where you may need to create the directory if it doesn't exist before writing the file. See "Working notes" in `preferences-documentation` for lifecycle management and integration with formal documentation.

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

### Log capture and scratch output

Log files captured with `tee` during long-running commands live in a repository's `logs/` directory, named with a lower-kebab-case identifier and a timestamp suffix, matching the command form given for long-running commands:

```bash
<command> 2>&1 | tee logs/<lower-kebab-identifier>-$(date +%Y%m%d-%H%M%S).log
```

Before writing there, verify that `logs/` is actually ignored by that repository.
If it is not ignored, write to `$XDG_STATE_HOME/agent-logs/<repo>/` instead and report the missing ignore entry rather than adding it silently.
Never leave an untracked, unignored file inside a jj working copy; see the `jj-version-control` skill's `hazards.md` for why a tracked log file is harmful once jj has begun snapshotting it.
Never delete logs within a session.
Pruning anything older than fourteen days is an explicit maintenance action only, never a side effect of other work.
When writing code, follow the XDG Base Directory specification for config, cache, and data paths.
Keep a scratch directory for agent working output rather than scattering it across the working tree.

## Development workflow and tooling

### Pre-implementation checkpoint

Before transitioning from planning to implementation, materialize the plan into concrete commitments.
Determine precisely which files and directories will be modified, created, or removed.
Define the grouping and sequence of commits with draft commit messages.
Specify how each commit or collection of changes will be verified as useful progress: passing new or existing tests, producing observable output, improving conceptual clarity, or satisfying other criteria appropriate to the change.
This checkpoint converts abstract plans into auditable intentions, reducing rework from misaligned assumptions.
For each proposed change, identify the confidence level the verification plan is expected to achieve and whether the verification would be severe — would it fail under plausible incorrect implementations?
See `preferences-validation-assurance` for the severity criterion and confidence promotion chain.

- Always at least consider testing changes with the relevant framework like bash shell commands where you can validate output, `shellcheck` for shell scripts, `cargo test`, `pytest`, `vitest`, `nix eval` or `nix build`, a task runner like `just test` or `make test`, or `gh workflow run` before considering any work to be complete and correct.
- Be judicious about test execution. If a test might take a very long time, be resource-intensive, or require elevated security privileges but is important, pause to provide the proposed command and reason why it's an important test.
- Local test execution is the primary feedback loop during development.
  Run tests iteratively as you work, fixing issues before committing.
  CI workflow verification is a distinct stage that occurs when validating a branch for merge/pull request, not during routine local development.
- Choose the narrowest verification that could actually falsify the change at hand.
  An evaluation-only change — documentation, skill text, prose, a module option description, anything that alters no derivation — is verified by `nix eval` on the affected attribute, and a build adds nothing.
  A change affecting one check is verified by `nix build .#checks.<name>` for that check.
  The full parallel run over every check belongs to pre-pull-request validation, or to a change whose blast radius is genuinely repository-wide, and is not a routine iteration step.
  The reason is cost against information: a full run takes minutes to hours and, for a one-file change, tells you almost nothing the targeted check does not, and spending it wantonly trains the habit of not knowing which check actually covers your change.
  This is about scope for the moment rather than building individual tests instead of the check set — the parallel runner exists so that coverage never has to be traded for speed.

### CI workflow log verification

When validating changes for merge, retrieve and analyze complete workflow logs across both CI backends (GitHub Actions and buildbot-nix) via the recipes in the `ci-log-verification` skill: wait with `gh run watch`, download full log archives, and use `PAGER=cat gh pr checks <N>` to route each check to its backend before analysis.

### CLI tools and repository lookup
- Use performant CLI tools matched to task intent:
  - File search (by name/path): use `fd` instead of `find`
  - Content search (within files): use `rg` (ripgrep) instead of `grep`
  - Disk usage (directory sizes): use `diskus` instead of `du -sh`
  - Clipboard (copy to system clipboard): use `cb copy` (`clipboard-jh`) instead of platform-specific `pbcopy` (macOS) or `xclip`/`xsel` (Linux)
  - Notification (push alert to user): use `ntfy-send "<message>"` where `<message>` includes the repo name and summarizes the completed task (default topic is the local hostname; override with `ntfy-send "<message>" <topic>`; `fleet-*` topics need the `alerter` token through `NTFY_TOKEN_FILE`, host topics stay anonymous)
- When a repository is named, or a substantive technical claim is about to rest on a project's source, options, defaults, API, or upstream documentation, resolve it to a local copy before reasoning about it; see `dependency-source-acquisition` for both lookup kinds, the `(see local)` marker directive, and GitHub file, issue, and PR URL handling.
