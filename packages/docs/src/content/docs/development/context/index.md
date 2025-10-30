---
title: Context
sidebar:
  order: 1
---

Context documentation for the nix-config system following AMDiRE (Artefact Model for Domain-independent Requirements Engineering) principles.

The context layer considers the context of the system under consideration, including the domain in which it operates, stakeholders, goals, constraints, and business processes.

## Overview

This documentation captures the problem space for migrating from flake-parts + nixos-unified architecture to dendritic flake-parts pattern with clan-core integration.

**Current state**: Working flake-parts + nixos-unified configuration managing four darwin hosts with manual per-host coordination.

**Target state**: Dendritic flake-parts pattern maximizing type safety through module system, with clan-core enabling multi-host coordination, declarative secrets, and overlay networking.

**Migration approach**: Validation-first (test-clan) → VPS infrastructure (cinnabar) → progressive darwin host migration (blackphos → rosegold → argentum → stibnite).

## Context documents

### [Project scope](project-scope/)

Problem description and statement of intent for the migration from nixos-unified to dendritic + clan.

**Key topics**:
- Current architecture limitations (type safety, multi-host coordination)
- Target architecture benefits (maximized module system usage, clan capabilities)
- Migration strategy and risk mitigation
- Architectural compatibility analysis

### [Stakeholders](stakeholders/)

Individuals, groups, and institutions with interest in the project.

**Key stakeholders**:
- Primary: User/maintainer (crs58) - all roles
- Secondary: Potential contributors, template users
- Reference: Upstream projects (flake-parts, clan-core, dendritic pattern, nixos-unified, home-manager, nix-darwin)

### [Constraints and rules](constraints-and-rules/)

Restrictions influencing the system, distinguishing non-negotiable constraints from conditional rules.

**Constraints** (non-negotiable):
- Nix ecosystem requirement
- Platform support (macOS aarch64, NixOS x86_64)
- Security requirements (encrypted secrets, age encryption)
- Licensing (AGPL-3.0)

**Rules** (conditional procedures):
- Git workflow (atomic commits, conventional messages)
- Code style (markdown formatting, naming conventions)
- Architecture principles (framework independence, type safety, bias toward removal)
- Migration stability gates (1-2 weeks between hosts)

### [Goals and objectives](goals-and-objectives/)

Goals issued by stakeholders organized by business, usage, and system categories.

**Business goals**:
- G-B01: Reliable personal infrastructure
- G-B02: Sustainable maintenance burden
- G-B03: Template value for community

**Usage goals**:
- G-U01: Efficient development workflows
- G-U02: Multi-host coordination (target)
- G-U03: Declarative secrets management (target)
- G-U04: Cross-platform module composition (target)
- G-U05: Surgical package fixes (preserve)
- G-U06: Secure overlay networking (target)
- G-U07: Fast, cached builds

**System goals**:
- G-S01: Maintainable codebase structure
- G-S02: Clear, idiomatic patterns
- G-S03: Maximum type safety through module system (target)
- G-S04: Dendritic flake-parts pattern adoption (target)
- G-S05: Comprehensive development environment (achieved)
- G-S06: Clan-core integration (target)
- G-S07: Clan vars system adoption (target)
- G-S08: Multi-channel resilience preservation (preserve)

### [Domain model](domain-model/)

Description of the Nix ecosystem domain, current architecture components, and target architecture components.

**Key domains**:
- Nix ecosystem overview (core concepts, package channels)
- Current architecture (flake-parts, nixos-unified, multi-channel resilience, sops-nix)
- Target architecture (dendritic pattern, clan-core, inventory, vars, zerotier)
- Domain processes (workflows for configuration, secrets, multi-host coordination)

### [Glossary](glossary/)

Important terms, abbreviations, synonyms, and descriptions.

**Term categories**:
- Nix ecosystem terms (flake, derivation, module system, nixpkgs)
- Current architecture terms (autowiring, nixos-unified, multi-channel resilience)
- Target architecture terms (dendritic, clan, inventory, vars, zerotier)
- Host names (stibnite, blackphos, rosegold, argentum, cinnabar)
- Migration terms (phases 0-6, stability gates, test-clan)
- Architectural terms (AMDiRE, atomic commit, type safety)

## Navigation

**Next**: [Requirements](../requirements/) - System vision, usage model, and quality requirements

**Related**:
- [Architecture](../architecture/) - Architectural decisions and technical design
- [Traceability](../traceability/) - Requirements traceability and CI philosophy
- [Work items](../work-items/) - Project task tracking

## AMDiRE context layer purpose

The context layer serves to:
1. Define the problem domain and scope
2. Identify stakeholders and their interests
3. Capture goals that requirements will satisfy
4. Document constraints limiting solution space
5. Model the domain in which the system operates

This provides the foundation for the requirements layer, which specifies what the system should do (black-box view) without constraining internal implementation.

## Using context documentation

**For migration planning**:
- Review project scope to understand current limitations and target benefits
- Check constraints to identify non-negotiable requirements
- Validate goals alignment with migration phases
- Reference domain model for architectural understanding

**For decision-making**:
- Consult constraints when evaluating technical approaches
- Review rules for guidance (can be adapted with justification)
- Check goal hierarchy for priority conflicts
- Reference stakeholder needs for perspective

**For onboarding**:
- Start with project scope for high-level overview
- Read glossary for terminology
- Review domain model for architectural context
- Understand stakeholders and their roles

**For maintenance**:
- Update as system evolves (especially during migration)
- Document new terms in glossary
- Revise goals as priorities change
- Keep constraints current with platform requirements

## Context review and updates

**Review frequency**:
- During each migration phase completion
- When significant architectural changes occur
- Quarterly for general maintenance
- As needed when context changes

**Update process**:
1. Identify changed context (new tools, constraints, goals)
2. Update relevant documents
3. Ensure consistency across context documents
4. Update references in requirements and architecture docs
5. Commit with clear description of context changes

## References

**Internal**:
- Migration plan: `docs/notes/clan/integration-plan.md` (internal planning, not published)
- Migration phases: `docs/notes/clan/phase-*.md` (internal planning, not published)
- Global preferences: `~/.claude/commands/preferences/` (development guidelines)

**Architecture**:
- ADRs: `docs/development/architecture/adrs/`
- Nixpkgs hotfixes: `docs/development/architecture/nixpkgs-hotfixes.md`

**External**:
- AMDiRE framework: Research paper on artefact-based requirements engineering
- dendritic pattern: <https://github.com/mightyiam/dendritic>
- clan-core: <https://docs.clan.lol/>
- flake-parts: <https://flake.parts/>
