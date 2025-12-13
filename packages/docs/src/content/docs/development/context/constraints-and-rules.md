---
title: Constraints and rules
---

This document distinguishes **constraints** (non-negotiable restrictions) from **rules** (conditional standard procedures).

## Constraints

Constraints are non-negotiable restrictions arising from business context, laws, or system operational environment.

### Platform constraints

**Nix ecosystem requirement**:
- All configuration must use Nix for reproducibility
- Cannot use imperative configuration management tools
- Reason: Declarative, reproducible infrastructure is core requirement

**Flake-based architecture**:
- Must use Nix flakes (not channels or traditional Nix)
- Configuration defined in `flake.nix` with locked inputs
- Reason: Reproducibility, composition, explicit dependency management

**Target platforms**:
- Must support macOS (darwin, aarch64-darwin specifically for Apple Silicon)
- Must support NixOS (x86_64-linux for VPS infrastructure)
- Must support home-manager for user environment
- Reason: Current hardware and infrastructure requirements

**Module system usage**:
- Must use Nix module system for configuration
- Cannot bypass module system type checking for core configuration
- Reason: Type safety and validation at evaluation time

### Operational constraints

**Development environment**:
- Must provide development shell via `nix develop`
- Must support direnv for automatic environment activation
- Must include just task runner for common operations
- Reason: Developer experience and workflow requirements

**Secret management**:
- Secrets must be encrypted at rest in version control
- Secrets must use age encryption (not GPG)
- Secrets must be decrypted only on target hosts
- Private keys must never be committed to repository
- Reason: Security requirements

**Multi-channel stable fallbacks** (current architecture):
- Must maintain ability to use stable channel for individual packages while staying on unstable
- Cannot require system-wide channel rollback for single package issues
- Reason: Operational stability without sacrificing access to latest packages

### Hardware constraints

**Existing hosts**:
- Four darwin hosts: stibnite, blackphos, rosegold, argentum (all aarch64-darwin)
- Four NixOS VPS hosts: cinnabar, electrum (Hetzner), galena, scheelite (GCP) (all x86_64-linux)
- Cannot change existing hardware architecture
- Reason: Physical hardware availability

**Resource limitations**:
- VPS budget constraint: ~€24/month for Hetzner CX53 (migration plan)
- Storage limits on darwin hosts (SSD capacity)
- Network bandwidth (home internet, VPS provider limits)
- Reason: Cost and infrastructure constraints

### Security constraints

**Access control**:
- Only authorized age keys can decrypt secrets
- Only authorized users can deploy configuration changes
- SSH access requires authorized keys (no password authentication)
- Reason: Security best practices

**Encryption requirements**:
- All secrets must be encrypted with strong encryption (age, 256-bit)
- Disk encryption required for VPS (LUKS)
- No secrets in nix store (must use runtime paths like /run/secrets/)
- Reason: Data protection and security compliance

### Licensing constraints

**Open source requirement**:
- Repository licensed under MIT
- All dependencies must have compatible open source licenses
- Cannot use proprietary tools in core configuration
- Reason: License compliance and open source principles

### Compatibility constraints

**Breaking changes**:
- Cannot break existing host functionality during configuration changes
- Must maintain rollback capability for all configuration deployments
- Historical note: nixos-unified configurations were preserved until migration completed in November 2024
- Reason: Operational continuity and risk management

**Upstream compatibility**:
- Must follow upstream project conventions (flake-parts, clan, nix-darwin, home-manager)
- Cannot fork or heavily patch upstream projects without strong justification
- Must track upstream changes and update accordingly
- Reason: Maintainability and community support

## Rules

Rules are conditional standard procedures that guide implementation but can be adapted when necessary with proper justification.

### Development workflow rules

**Git version control** (from `~/.claude/commands/preferences/git-version-control.md`):
- Create atomic commits after each file edit
- One logical change per file, one file per commit
- Use conventional commit message format
- Never use `git add .` or `git add -A`
- Document breaking changes in commit messages
- Condition: Unless rapid experimentation requires looser workflow

**Branch workflow**:
- Branch naming: N-descriptor where N is issue/PR number
- Create new branch when work doesn't match current branch's descriptor
- Merge via fast-forward when unit of work complete
- Condition: Flexible for personal experiments or quick fixes

**Commit message format**:
- Succinct conventional commit messages for semantic versioning
- No emojis or multiple authors
- Use "fixup! " prefix for fixup commits (exactly once)
- Condition: Can be relaxed for WIP commits on feature branches

### Code style rules

**Markdown formatting** (from `~/.claude/commands/preferences/style-and-conventions.md`):
- Write one sentence per line
- Prefer prose over bullet lists for concepts and narrative
- Keep section header nesting shallow (rarely beyond three levels)
- Use bold sparingly for critical emphasis
- Avoid emojis unless explicitly requested
- Capitalize first word of complete sentences and headings
- Condition: Template/generated files may have different conventions

**Naming conventions**:
- Prefer lowercase except for PascalCase/camelCase code conventions
- Do not use all-caps for file names
- Use kebab-case for markdown filenames
- Avoid uppercase for emphasis (no "IMPORTANT:", "WARNING:")
- Condition: Code follows language-specific conventions

**File organization**:
- Never pollute repository root with markdown files
- Place working notes in `./docs/notes/[category]/[filename.md]`
- Create directories as needed
- Condition: Exception for standard files (README.md, LICENSE, etc.)

### Architecture rules

**Design principles** (from ADR-0014):
- **Framework independence**: Avoid framework-specific naming in core identifiers
- **Template duality**: Design works as both deployment and forkable template
- **Type safety**: Follow functional programming principles, emphasize type safety
- **Bias toward removal**: Remove content when no longer valuable, git preserves history
- Condition: Pragmatic exceptions when benefits clear

**Module organization** (current → target):
- Current: Directory-based autowire (`modules/{darwin,home,nixos}/`)
- Target: Deferred module composition flat categories (`modules/{base,shell,dev,hosts}/`)
- Feature-based organization, not platform-based
- Cross-cutting concerns enabled (one module, multiple targets)
- Condition: Migration in progress, both patterns temporarily coexist

**Dependency management**:
- Pin all flake inputs with `follows` where appropriate
- Use multi-channel pattern for stable fallbacks
- Prefer stable packages when possible, unstable when needed
- Document reasons for unstable channel usage
- Condition: Can use unpinned for rapid testing, must pin before commit

### Testing rules

**CI/CD testing philosophy** (from `docs/development/traceability/ci-philosophy.md`):
- Tests mirror user workflows described in README
- Discover resources dynamically (no hardcoded lists that drift)
- Fail fast and clearly (errors point to exact problem)
- Scale efficiently as project grows
- Condition: Some manual testing acceptable for complex scenarios

**Testing before commits**:
- Always consider testing changes with relevant framework
- Examples: `cargo test`, `pytest`, `vitest`, `nix build`
- Use task runner when available: `just test`
- Condition: Can skip for documentation-only changes

**Performant CLI tools** (from style guide):
- File search: use `fd` instead of `find`
- Content search: use `rg` instead of `grep`
- Disk usage: use `diskus` instead of `du -sh`
- Condition: Can use standard tools in contexts where Nix tools unavailable

### Historical: Migration rules

These rules governed the nixos-unified → clan+dendritic migration (Phases 0-6) completed in November 2024.
They remain documented for historical context and potential future migrations.

**Progressive migration order** (completed):
- Phase 0: Validated in test-clan (required before infrastructure commitment)
- Phase 1: Deployed VPS infrastructure (cinnabar)
- Phases 2-5: Migrated darwin hosts (blackphos → rosegold → argentum → stibnite)
- Phase 6: Cleanup (removed nixos-unified)

**Stability gates** (applied during migration):
- Each host was stable for 1-2 weeks before proceeding to next
- Primary workstation (stibnite) migrated last
- Rollback capability maintained until migration complete

**Priority hierarchy for pattern conflicts** (remains current):
1. Clan functionality (non-negotiable)
2. Deferred module composition (best-effort)
3. Pattern purity (flexible)
- Rule: When conflicts arise, preserve clan functionality, optimize with deferred module composition where possible
- Condition: Can deviate from pure deferred module composition if necessary for clan compatibility

### Documentation rules

**Architecture Decision Records**:
- Document significant architectural decisions as ADRs
- Include context, decision, consequences, alternatives considered
- Number sequentially (ADR-0001, ADR-0002, etc.)
- Condition: Minor tweaks don't require ADRs

**Working notes lifecycle** (from style guide):
- Create in `docs/notes/[category]/` during development
- Integrate valuable content into formal docs
- Remove or archive when no longer relevant
- Condition: Can keep notes longer if actively referenced

**Bias toward removal**:
- Remove code/docs when no longer valuable
- Preserve history in git, not in active codebase
- Don't keep "just in case" code or docs
- Delete completed one-time implementation prompts
- Condition: Historical context may warrant keeping with explicit justification

## Rule exceptions and justifications

When rules must be broken, document:
- Which rule was violated
- Why violation was necessary
- What alternatives were considered
- Whether violation is temporary or permanent
- How violation affects system maintainability

**Example format for documenting exceptions**:
```nix
# EXCEPTION: Using specialArgs for inputs pass-through
# Reason: Clan flakeModules integration requires minimal specialArgs
# Justification: This is framework-level passing (inputs, self),
#                not extensive application value passing
# Alternative considered: Pure deferred module composition (not compatible with clan)
# Status: Permanent acceptable exception
# References: deferred module composition anti-pattern discussion
```

## Constraints and rules review

**Review frequency**:
- Constraints: Review when significant platform or infrastructure changes occur
- Rules: Review quarterly or when patterns prove ineffective

**Review process**:
- Evaluate whether constraints still apply
- Assess whether rules improve or hinder development
- Document changes as ADRs when rules modified significantly
- Update this document to reflect current state

## References

- Global preferences: `~/.claude/commands/preferences/`
- ADR-0014: Design principles
- Migration plan: `docs/notes/clan/integration-plan.md` (internal reference, not published)
- Git workflow: `~/.claude/commands/preferences/git-version-control.md`
- Style conventions: `~/.claude/commands/preferences/style-and-conventions.md`
