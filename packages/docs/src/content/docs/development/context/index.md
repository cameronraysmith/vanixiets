---
title: Contents
description: "AMDiRE context layer"
sidebar:
  order: 1
---

Context documentation for infra following AMDiRE (Artefact Model for Domain-independent Requirements Engineering) principles.

The context layer considers the context of the system under consideration, including the domain in which it operates, stakeholders, goals, constraints, and business processes.

## Overview

This documentation captures the architecture and operational context for the dendritic flake-parts + clan infrastructure.

**Current state**: Dendritic flake-parts pattern with clan integration managing 8 hosts (4 darwin, 4 nixos) with multi-machine coordination, declarative secrets, and overlay networking.

**Architecture migration complete**: The migration from nixos-unified to dendritic + clan completed. All documentation reflects current state.

## Context documents

### [Project scope](/development/context/project-scope/)

Description of the infrastructure scope and capabilities.

**Key topics**:
- Current architecture (dendritic flake-parts, clan, multi-channel overlays)
- Multi-machine coordination capabilities
- Cross-platform deployment (darwin + nixos)
- Future expansion areas

### [Stakeholders](/development/context/stakeholders/)

Individuals, groups, and institutions with interest in the project.

**Key stakeholders**:
- Primary: User/maintainer (crs58/cameron) - all roles
- Secondary: Family users (raquel, janettesmith, christophersmith)
- Reference: Upstream projects (flake-parts, clan, dendritic pattern, home-manager, nix-darwin)

### [Constraints and rules](/development/context/constraints-and-rules/)

Restrictions influencing the system, distinguishing non-negotiable constraints from conditional rules.

**Constraints** (non-negotiable):
- Nix ecosystem requirement
- Platform support (macOS aarch64, NixOS x86_64)
- Security requirements (encrypted secrets, age encryption)
- Licensing (MIT)

**Rules** (conditional procedures):
- Git workflow (atomic commits, conventional messages)
- Code style (markdown formatting, naming conventions)
- Architecture principles (dendritic organization, type safety)

### [Goals and objectives](/development/context/goals-and-objectives/)

Goals issued by stakeholders organized by business, usage, and system categories.

**Business goals**:
- G-B01: Reliable personal infrastructure
- G-B02: Sustainable maintenance burden
- G-B03: Template value for community

**Usage goals**:
- G-U01: Efficient development workflows
- G-U02: Multi-host coordination (achieved via clan)
- G-U03: Declarative secrets management (achieved with clan vars, migrating from legacy sops-nix)
- G-U04: Cross-platform module composition (achieved via dendritic)
- G-U05: Surgical package fixes (preserved via multi-channel)
- G-U06: Secure overlay networking (achieved via zerotier)
- G-U07: Fast, cached builds

**System goals**:
- G-S01: Maintainable codebase structure
- G-S02: Clear, idiomatic patterns
- G-S03: Maximum type safety through module system (achieved)
- G-S04: Dendritic flake-parts pattern (adopted)
- G-S05: Comprehensive development environment (achieved)
- G-S06: Clan-core integration (achieved)
- G-S07: Secrets with clan vars and legacy sops-nix migration (achieved)
- G-S08: Stable fallbacks (preserved)

### [Domain model](/development/context/domain-model/)

Description of the Nix ecosystem domain and current architecture components.

**Key domains**:
- Nix ecosystem overview (core concepts, package channels)
- Current architecture (dendritic flake-parts, clan, multi-channel fallback, sops-nix)
- Domain processes (workflows for configuration, secrets, multi-host coordination)

### [Glossary](/development/context/glossary/)

Important terms, abbreviations, synonyms, and descriptions.

**Term categories**:
- Nix ecosystem terms (flake, derivation, module system, nixpkgs)
- Architecture terms (dendritic, clan, inventory, vars, zerotier)
- Host names (stibnite, blackphos, rosegold, argentum, cinnabar, electrum, galena, scheelite)

## Navigation

**Next**: [Requirements](../requirements/) - System vision, usage model, and quality requirements

**Related**:
- [Architecture](../architecture/) - Architectural decisions and technical design
- [Traceability](../traceability/) - Requirements traceability and CI philosophy

## AMDiRE context layer purpose

The context layer serves to:
1. Define the problem domain and scope
2. Identify stakeholders and their interests
3. Capture goals that requirements will satisfy
4. Document constraints limiting solution space
5. Model the domain in which the system operates

This provides the foundation for the requirements layer, which specifies what the system should do (black-box view) without constraining internal implementation.

## Using context documentation

**For system understanding**:
- Review project scope for architecture overview
- Check constraints to identify non-negotiable requirements
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
- Update as system evolves
- Document new terms in glossary
- Revise goals as priorities change
- Keep constraints current with platform requirements

## Context review and updates

**Review frequency**:
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

**Architecture**:
- ADRs: `packages/docs/src/content/docs/development/architecture/adrs/`
- [Handling broken packages](/guides/handling-broken-packages): Multi-channel stable fallbacks guide

**External**:
- AMDiRE framework: Research paper on artefact-based requirements engineering
- dendritic pattern: <https://github.com/mightyiam/dendritic>
- clan: <https://clan.lol/>
- flake-parts: <https://flake.parts/>
