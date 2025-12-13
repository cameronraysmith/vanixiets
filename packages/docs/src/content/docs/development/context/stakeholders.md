---
title: Stakeholders
---

## Primary stakeholder

### User/Maintainer (crs58)

**Role**: Primary developer, system administrator, daily user

**Responsibilities**:
- Define requirements and prioritize features
- Implement and maintain configuration code
- Manage hosts and deploy updates
- Monitor system stability and troubleshoot issues
- Make architectural decisions
- Evaluate and adopt new patterns and tools

**Interests**:
- Reliable personal infrastructure for daily workflows
- Type-safe, maintainable configurations
- Multi-host coordination and management
- Efficient development environment
- Learning and adopting modern Nix patterns

**Domain knowledge**: Deep understanding of Nix ecosystem, flake-parts, nixos-unified, sops-nix, darwin/NixOS configuration

**Decision authority**: Final authority on all technical and architectural decisions

## Secondary stakeholders

### Potential contributors

**Role**: Community members who might contribute improvements or report issues

**Responsibilities**:
- Follow contribution guidelines
- Report bugs and suggest enhancements
- Submit pull requests for improvements

**Interests**:
- Clear, understandable codebase structure
- Good documentation
- Consistent patterns and conventions

**Domain knowledge**: Variable (from Nix beginners to experts)

**Impact on design**:
- Code should be well-documented
- Patterns should be clear and idiomatic
- Architecture should follow community best practices

### Template users

**Role**: Developers who might fork this configuration as a starting point

**Responsibilities**:
- Adapt configuration to their own needs
- Understand architectural patterns used
- Follow licensing terms (MIT)

**Interests**:
- Working, production-ready configuration
- Clear separation of personal vs. reusable components
- Good documentation of patterns and decisions
- Examples of common configuration tasks

**Domain knowledge**: Variable Nix proficiency

**Impact on design**:
- ADR-0014 principle: template duality (works as both deployment and forkable template)
- Generic, purpose-based naming (not user-specific hardcoding)
- Documentation explains both template usage and customization
- Repository structure should be self-explanatory

## Reference stakeholders

### Upstream projects

These projects provide the foundation and influence architectural decisions:

**flake-parts** (hercules-ci/flake-parts):
- Provides modular flake composition
- Defines module system extensions for flakes
- Influences: Configuration structure, module organization patterns

**clan** (clan.lol/clan/clan-core):
- Provides multi-host coordination
- Defines inventory system, vars system, service instances
- Influences: Architecture, multi-host patterns, secrets management

**dendritic flake-parts pattern** (mightyiam/dendritic):
- Defines "every file is a flake-parts module" organizational pattern
- Eliminates specialArgs antipattern
- Influences: Directory structure, module composition patterns

**home-manager** (nix-community/home-manager):
- Provides user environment management
- Works across darwin and nixos platforms
- Influences: User-level configuration structure

**nix-darwin** (LnL7/nix-darwin):
- Provides macOS system management via Nix
- Influences: Darwin-specific configuration patterns

**sops-nix** (Mic92/sops-nix) [current]:
- Provides secrets management with SOPS
- Influences: Current secrets structure, age key management

## User groups and actors

### System administrator (crs58)

**Interaction with system**:
- Deploys configuration changes via `darwin-rebuild switch` or `nixos-rebuild switch`
- Manages secrets via `sops` command
- Monitors system logs and health
- Troubleshoots issues and performs rollbacks if needed

**Critical workflows**:
- Configuration development and testing
- Host onboarding and decommissioning
- Secret rotation and management
- System updates and maintenance
- Disaster recovery and backup management

### Developer (crs58)

**Interaction with system**:
- Uses development environment provided by configurations
- Accesses development tools (editors, language runtimes, CLI tools)
- Manages project repositories
- Runs builds and tests

**Critical workflows**:
- Daily development tasks across multiple projects
- Cross-platform development (macOS local, Linux remote/CI)
- Tool installation and version management
- Development environment customization

### End user (crs58)

**Interaction with system**:
- Uses GUI applications and system services
- Performs daily computing tasks
- Relies on stable, performant system

**Critical workflows**:
- Application usage (browsers, editors, communication tools)
- File management and data access
- Network connectivity
- System preferences and customizations

## Stakeholder communication

### Internal communication

All stakeholder roles are fulfilled by single person (crs58).
Communication occurs through:
- Documentation in repository (ADRs, guides, notes)
- Git commit messages and history
- Issue tracking (if using GitHub Issues)
- Planning documents in `docs/notes/` (not published to docs site)

### External communication

**With upstream projects**:
- Monitor project releases and changelogs
- Review documentation and examples
- Report bugs or contribute improvements when applicable
- Track breaking changes that affect configuration

**With potential contributors**:
- README provides project overview
- CONTRIBUTING.md (if created) outlines contribution process
- Documentation site provides usage guides
- GitHub Discussions for questions and collaboration

**With template users**:
- Documentation explains architectural patterns
- ADRs document decisions and rationale
- Repository structure is self-documenting
- License (MIT) clarifies usage terms

## Stakeholder needs summary

**Primary stakeholder (crs58) needs**:
- Reliable, stable system for daily use
- Type-safe, maintainable code
- Multi-host coordination capabilities
- Efficient development workflows
- Clear documentation for future reference

**Secondary stakeholder (contributors/template users) needs**:
- Clear codebase structure
- Good documentation
- Understandable patterns
- Working examples

**Reference stakeholder (upstream projects) needs**:
- Follow project conventions and best practices
- Report issues constructively
- Contribute improvements when beneficial
- Respect project architectures and patterns

## Decision-making authority

**Primary stakeholder (crs58)**:
- Final authority on all decisions
- Defines priorities and requirements
- Evaluates trade-offs
- Accepts or rejects changes

**Secondary stakeholders (contributors)**:
- Can propose changes via pull requests
- Can suggest improvements
- No direct decision authority
- Changes require primary stakeholder approval

**Reference stakeholders (upstream projects)**:
- Define patterns and conventions for their respective projects
- Influence architectural decisions through best practices
- No direct authority over this configuration
- Their architectural changes may necessitate updates to this configuration
