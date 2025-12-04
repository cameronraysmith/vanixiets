---
title: Contents
descripton: "AMDiRE requirements layer"
sidebar:
  order: 1
---

This section contains the Requirements layer of the AMDiRE (Artefact Model for Domain-independent Requirements Engineering) documentation framework.

## Overview

The Requirements layer specifies what the system should do from a black-box perspective - the user-visible functionality and quality attributes without constraining internal implementation.
This layer bridges the Context layer (problem space) and the System layer (solution space, when implemented).

All requirements support the dendritic flake-parts + clan-core architecture, which is now the current operational architecture as of November 2024.
This documentation reflects the complete migration from nixos-unified, with all eight machines in the fleet operating under the new architecture.

## AMDiRE Requirements layer purpose

According to the AMDiRE framework, the Requirements layer comprehends requirements on the system under consideration by taking a black-box view.
This means specifying requirements from a user's perspective without constraining or even understanding the internal realization of the system.

**Key characteristics**:
- **Black-box perspective**: What the system does, not how it does it
- **User-visible functionality**: Observable behaviors and interactions
- **Quality attributes**: Non-functional requirements (performance, security, etc.)
- **Platform-agnostic**: Requirements independent of specific technologies where possible
- **Deployment procedures**: How configurations reach target systems
- **Grey-box constraints**: Known architectural restrictions without full implementation details

The Requirements layer serves as the contract between stakeholders (Context layer) and the implementation (System layer, future work).

## Requirements documents

### System vision

**Purpose**: High-level overview of intended system capabilities and features.

**Key content**:
- Seven core use cases (UC-001 through UC-007)
- Feature overview and capabilities
- User groups and their needs
- Success criteria for migration

**Read this first**: Provides orientation to the entire Requirements layer.

**Document**: [System vision](/development/requirements/system-vision/)

### Usage model

**Purpose**: Detailed use case specifications with complete scenarios.

**Key content**:
- UC-001: Bootstrap new host with minimal configuration
- UC-002: Add feature module spanning multiple platforms
- UC-003: Manage secrets via declarative generators
- UC-004: Deploy coordinated service across hosts
- UC-005: Handle broken package with multi-channel fallback
- UC-006: Establish secure overlay network
- UC-007: Migrate host to dendritic + clan architecture

**For each use case**:
- Actors and their roles
- Preconditions and prerequisites
- Main flow (happy path)
- Alternate flows (error handling, variations)
- Postconditions and outcomes
- References and examples

**Use when**: Understanding user workflows, planning features, validating implementations.

**Document**: [Usage model](/development/requirements/usage-model/)

### Functional hierarchy

**Purpose**: User-visible functions organized hierarchically by category.

**Key content**:
- Configuration management functions (CM-001 through CM-004)
- Secrets management functions (SM-001 through SM-004)
- Package management functions (PM-001 through PM-006)
- Development environment functions (DE-001 through DE-003)
- Deployment functions (DF-001 through DF-007)
- Multi-host coordination functions (MC-001 through MC-004)
- Overlay networking functions (ON-001 through ON-004)
- CI/CD functions (CI-001 through CI-004)
- Migration functions (MF-001 through MF-004)

**For each function**:
- Purpose and description
- Inputs and outputs
- Invocation methods
- Related use cases

**Use when**: Understanding system capabilities, planning testing, documenting features.

**Document**: [Functional hierarchy](/development/requirements/functional-hierarchy/)

### Quality requirements

**Purpose**: Non-functional requirements defining system quality attributes.

**Key content**:
- QR-001: Reproducibility
- QR-002: Type safety
- QR-003: Maintainability
- QR-004: Modularity
- QR-005: Security
- QR-006: Performance
- QR-007: Reliability
- QR-008: Template duality

**For each requirement**:
- Definition and rationale
- Measurement criteria
- Current state assessment
- Target state objectives
- Validation approaches

**Use when**: Evaluating architectural decisions, planning quality assurance, measuring success.

**Document**: [Quality requirements](/development/requirements/quality-requirements/)

### Deployment requirements

**Purpose**: Requirements for deploying configurations to target systems.

**Key content**:
- DR-001: Darwin deployment (macOS)
- DR-002: NixOS deployment (Linux)
- DR-003: Home-manager deployment
- DR-004: Clan orchestration deployment
- DR-005: CI/CD deployment
- DR-006: Validation and testing requirements
- DR-007: Secrets deployment requirements
- DR-008: Platform-specific requirements
- DR-009: Rollback and recovery requirements
- DR-010: Environment-specific requirements

**For each requirement**:
- Build requirements
- Activation procedures
- Validation steps
- Rollback strategies
- Platform-specific considerations

**Use when**: Planning deployments, troubleshooting activation issues, designing rollback procedures.

**Document**: [Deployment requirements](/development/requirements/deployment-requirements/)

### System constraints

**Purpose**: Grey-box restrictions on system architecture and quality.

**Key content**:
- SC-001: Nix evaluation constraints
- SC-002: Module system constraints
- SC-003: Flake constraints
- SC-004: Platform-specific constraints (darwin, NixOS)
- SC-005: Dendritic pattern constraints
- SC-006: Clan-core constraints
- SC-007: Build system constraints
- SC-008: Secrets management constraints
- SC-009: Network and connectivity constraints
- SC-010: Migration-specific constraints

**For each constraint**:
- Description and rationale
- Implications for design
- Limitations and boundaries
- Mitigation strategies
- Traceability to quality requirements

**Use when**: Understanding system boundaries, troubleshooting limitations, planning workarounds.

**Document**: [System constraints](/development/requirements/system-constraints/)

### Risk list

**Purpose**: Migration risks with likelihood, impact, and mitigation strategies.

**Key content**:
- R-001: Dendritic + clan integration complexity
- R-002: VPS infrastructure costs and management overhead
- R-003: Darwin host migration breaking daily workflows
- R-004: Primary workstation (stibnite) migration risk
- R-005: Secrets migration from sops-nix to clan vars
- R-006: Breaking changes in upstream dependencies
- R-007: Initial validation revealing architectural incompatibility
- R-008: Zerotier network reliability and connectivity issues
- R-009: Multi-host synchronization failures
- R-010: Learning curve for dendritic + clan patterns

**For each risk**:
- Description and risk factors
- Likelihood and impact assessment
- Migration timeline relevance
- Mitigation strategies
- Current status

**Use when**: Planning migration phases, preparing contingencies, managing project risk.

**Document**: [Risk list](/development/requirements/risk-list/)

## Using Requirements documentation

### For migration planning

**Initial validation preparation**:
1. Review [system vision](/development/requirements/system-vision/) for overall goals
2. Study UC-001, UC-002, UC-003 in [usage model](/development/requirements/usage-model/) for basic patterns
3. Review R-001, R-007 in [risk list](/development/requirements/risk-list/) for validation objectives
4. Understand SC-005, SC-006 in [system constraints](/development/requirements/system-constraints/) for integration constraints

**VPS deployment preparation**:
1. Review UC-001, UC-006 in [usage model](/development/requirements/usage-model/) for bootstrap and networking
2. Study DR-002 in [deployment requirements](/development/requirements/deployment-requirements/) for NixOS deployment
3. Review R-002, R-008 in [risk list](/development/requirements/risk-list/) for VPS and network risks

**Darwin host migration preparation**:
1. Review UC-007 in [usage model](/development/requirements/usage-model/) for migration workflow
2. Study DR-001 in [deployment requirements](/development/requirements/deployment-requirements/) for darwin deployment
3. Review R-003, R-004 in [risk list](/development/requirements/risk-list/) for workflow and stibnite risks
4. Reference MF-* functions in [functional hierarchy](/development/requirements/functional-hierarchy/) for migration operations

### For feature development

**Adding new feature**:
1. Determine which use case the feature supports (usage model)
2. Identify relevant functions in functional hierarchy
3. Check quality requirements that apply (type safety, modularity, etc.)
4. Review relevant constraints (system constraints)
5. Implement following patterns from usage model examples

**Handling broken package**:
1. Follow UC-005 in [usage model](/development/requirements/usage-model/)
2. Reference PM-* functions in [functional hierarchy](/development/requirements/functional-hierarchy/)
3. Apply mitigation from R-006 in [risk list](/development/requirements/risk-list/)
4. Consult SC-007 in [system constraints](/development/requirements/system-constraints/) for build system limitations

### For validation and testing

**Pre-deployment validation**:
1. Check relevant deployment requirements (DR-*)
2. Verify quality requirements met (QR-*)
3. Review constraints respected (SC-*)
4. Follow validation procedures in deployment requirements

**Post-migration stability assessment**:
1. Validate use cases functional (UC-*)
2. Measure quality attributes (QR-*)
3. Monitor risks materialization (R-*)
4. Document issues encountered for future phases

### For decision-making

**Architectural decisions**:
1. Review quality requirements impacted
2. Check constraints that apply
3. Evaluate risk implications
4. Validate use cases still satisfied

**Trade-off analysis**:
1. Identify competing quality requirements
2. Review constraint limitations
3. Assess risk factors
4. Document decision rationale (ADR)

## Requirements review and updates

### Review frequency

- **During major changes**: Review before significant system modifications
- **Routine**: Annual review or on significant change
- **Continuous**: Update risks as status changes

### Update triggers

- Discovery of new requirements (user needs, technical needs)
- Change in constraints (upstream changes, platform updates)
- Risk materialization or mitigation success
- Quality requirement violations or achievements
- Use case modifications (workflow changes)

### Update process

1. Identify requirement document needing update
2. Review current content against reality
3. Update content preserving AMDiRE structure
4. Update cross-references if affected
5. Commit with clear rationale in message
6. Update related documents if needed

### Quality criteria for requirements

- **Testable**: Can validate requirement met
- **Unambiguous**: Clear single interpretation
- **Complete**: All necessary information included
- **Consistent**: No contradictions within or across documents
- **Traceable**: Clear relationships to context and architecture
- **Prioritized**: Relative importance clear (critical/high/medium/low)

## Navigation

### Previous: Context layer

The Context layer defines the problem space that Requirements address:
- [Context overview](../context/)
- [Project scope](../context/project-scope/)
- [Domain model](../context/domain-model/)
- [Goals and objectives](../context/goals-and-objectives/)

### Peer: Architecture documentation

Architecture documentation describes the solution space:
- [Architecture overview](../../architecture/)
- [ADRs](../../architecture/adrs/)
- [Nixpkgs hotfixes](../../architecture/nixpkgs-hotfixes/)

### Peer: Traceability documentation

Traceability links requirements to implementation:
- [Traceability overview](../../traceability/)
- [CI philosophy](../../traceability/ci-philosophy/)

## AMDiRE framework reference

The AMDiRE approach distinguishes three levels of abstraction:

1. **Context layer** (completed): Domain, stakeholders, constraints, goals
2. **Requirements layer** (this section): Black-box system specification
3. **System layer** (future work): Glass-box internal architecture

Each layer provides different views appropriate for different stakeholders and purposes.

**Benefits of artefact-based approach**:
- Process-agnostic (supports both plan-driven and agile)
- Focuses on results and their dependencies, not methods
- Provides flexible backbone for project execution
- Clear notion of responsibilities via roles
- Enables systematic requirements management

**References**:
- AMDiRE paper: [arxiv.org/abs/1611.10024](https://arxiv.org/abs/1611.10024)

## Document statistics

- **System vision**: 239 lines (existing, not modified)
- **Usage model**: 621 lines (7 detailed use cases)
- **Functional hierarchy**: 819 lines (52 functions across 9 categories)
- **Quality requirements**: 508 lines (8 quality attributes)
- **Deployment requirements**: 726 lines (10 deployment scenarios)
- **System constraints**: 634 lines (10 constraint categories)
- **Risk list**: 792 lines (10 risks with mitigation)
- **Index** (this document): Overview and navigation

**Total**: ~4,300 lines of comprehensive Requirements layer documentation

## Summary

The Requirements layer provides a complete black-box specification of infra under the dendritic + clan architecture that is now operational across an eight-machine fleet (as of November 2024).

**Key takeaways**:
- Seven core use cases capture all major workflows
- 52 user-visible functions organized by purpose
- Eight quality attributes define system excellence
- Ten deployment scenarios cover all platforms
- Ten constraints bound the design space
- Ten risks identified with mitigation strategies (legacy migration risks now closed)
- All requirements traceable to Context layer goals

**Current focus**:
1. Maintain Requirements layer accuracy as reference for ongoing operations
2. Ensure system behavior matches documented requirements
3. Monitor quality attributes in production
4. Update requirements when system capabilities evolve
5. Reference functional hierarchy for feature planning
6. Respect constraints in design decisions
7. Track and resolve any emerging operational risks

The Requirements layer serves as the authoritative specification for what the system must accomplish, guiding all implementation and validation efforts.
