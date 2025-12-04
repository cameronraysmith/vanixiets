---
title: "ADR-0014: Design principles"
---

## Status

Accepted

## Context

Architectural consistency requires establishing high-level design principles that guide decision-making across the codebase.

These principles should:
- Apply broadly across multiple domains (naming, architecture, dependencies, etc.)
- Be memorable and actionable
- Reflect team values and priorities
- Guide future architectural decisions

## Decision

Establish four core design principles for this template.

## Principles

### 1. Framework independence

**Principle:** Avoid framework-specific naming in core identifiers.

**Example:**
- ● Package name: `@infra/docs`
- ⊘ Package name: `@infra/starlight` or `@infra/astro-docs`

**Rationale:**
- Astro/Starlight are implementation details that may change
- Package purpose (`docs`) is stable, framework choice is not
- Reduces coupling to specific technologies
- Makes migration easier if framework needs to change

**Application:**
- Package names reflect purpose, not technology
- Directory structure reflects domain, not tools
- Public APIs avoid framework-specific types where possible

### 2. Template duality

**Principle:** This repository serves dual purposes: working deployment AND forkable template.

**Context:** Many templates are either:
- Examples that don't actually run (toy projects)
- Working projects that are hard to fork (too specific)

**Decision:** Design works for both purposes simultaneously.

**Application:**
- Use generic, purpose-based naming (works as both demo and template)
- Package structure works for both single-package and multi-package projects
- Documentation explains both template usage and customization
- Keep template-specific content in `notes/` (excluded from build)

**Benefits:**
- Template users see a working system
- Forces us to actually use what we build
- Reduces drift between template and reality

### 3. Type safety and functional patterns

**Principle:** Follow functional programming principles and emphasize type safety.

**Context:** Aligns with user preferences from global CLAUDE.md.

**Application:**
- Type-safe patterns throughout
- Functional programming where feasible in TypeScript/JavaScript
- No `any` types
- Explicit side effects in type signatures where possible
- Prefer pure functions over stateful objects
- Use algebraic data types when appropriate

**Rationale:**
- Reduces bugs through compiler enforcement
- Makes code easier to reason about
- Aligns with modern TypeScript best practices
- Composability through pure functions

**Trade-offs:**
- May be more verbose than dynamic alternatives
- Steeper learning curve for developers unfamiliar with FP
- Not always possible in JavaScript ecosystem

### 4. Bias toward removal

**Principle:** Documentation and code should serve current needs, not speculative future ones.

**Decision:**
- Remove content when no longer valuable
- Preserve historical content only in git history
- Don't keep "just in case" code or docs
- Delete completed one-time implementation prompts
- Move obsolete patterns to notes or remove entirely

**Rationale:**
- Reduces maintenance burden (less to update)
- Keeps codebase focused on actual problems
- Prevents decision paralysis from too many options
- Git history preserves complete audit trail when needed
- Forces explicit decision about value

**Application:**
- Regular cleanup of unused code
- Remove completed one-time prompts after implementation
- Archive superseded documentation to notes/
- Delete notes that are no longer relevant

**Examples:**
- Deleted `semantic-release.md` implementation prompt after completion
- Moved `git-dual-remote.md` personal workflow to `notes/workflows/`
- Will remove template instructions after forking

## Consequences

**Positive:**
- Consistent architectural decisions
- Clear guidance for contributors
- Reduced bikeshedding (principles provide answer)
- Code stays maintainable over time

**Negative:**
- Requires discipline to follow principles
- May conflict with framework conventions
- Bias toward removal can be aggressive

**Neutral:**
- Principles evolve as we learn
- Not all decisions fit neatly into principles
- Need to document exceptions when they occur

## Application

When making architectural decisions, ask:
1. Does this name reveal implementation details that might change? (Framework independence)
2. Does this work as both template and real deployment? (Template duality)
3. Can we make this more type-safe or functional? (Type safety)
4. Do we actually need this or is it speculative? (Bias toward removal)
