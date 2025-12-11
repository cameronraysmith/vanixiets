---
title: Glossary
---

This glossary contains important terms for the system under consideration, including abbreviations, synonyms, and descriptions.
Terms are organized alphabetically within categories for easier navigation.

## Nix ecosystem terms

**age**: Modern encryption tool used for secrets management, simpler than GPG.
Synonym: none.
Related: sops, sops-nix, encryption.

**derivation**: Build recipe in Nix describing how to produce outputs from inputs.
Synonym: drv.
Related: nix store, nixpkgs.

**flake**: Modern Nix feature providing hermetic, reproducible builds with lock files (`flake.lock`).
Synonym: none.
Related: flake.nix, inputs, outputs.

**flake.lock**: Lock file pinning exact versions of all flake inputs for reproducibility.
Synonym: lock file.
Related: flake, inputs.

**flake.nix**: File defining a Nix flake with its inputs and outputs.
Synonym: none.
Related: flake, inputs, outputs.

**home-manager**: Tool and NixOS/nix-darwin module for managing user environment declaratively.
Abbreviation: HM.
Related: user environment, dotfiles.

**input**: Flake dependency specified in `flake.nix` inputs section.
Synonym: dependency, flake input.
Related: flake, follows.

**module system**: Nix's configuration composition system (nixpkgs `lib.evalModules`) with options, types, and validation.
Core primitives: deferredModule (delays evaluation for fixpoint resolution), evalModules (computes configuration fixpoint), option merging (type-specific merge functions).
See [Module System Primitives](/concepts/module-system-primitives/).
Synonym: none.
Related: options, types, configuration, deferredModule, evalModules.

**deferredModule**: Module system type that delays evaluation until configuration is computed.
Enables modules to reference final merged configuration via fixpoint resolution.
Foundation of dendritic pattern and flake-parts module composition.
Synonym: none.
Related: evalModules, module system, flake-parts.

**evalModules**: Core function that evaluates modules via fixpoint computation.
Takes modules and specialArgs, returns configuration with options and type checking.
Used by NixOS, nix-darwin, home-manager, and flake-parts.
Synonym: none.
Related: deferredModule, module system.

**fixpoint**: Self-referential computation where config references resolve to final merged result.
The module system computes a least fixpoint via lazy evaluation.
Enables modules to reference each other's configuration without strict circular dependencies.
Synonym: none.
Related: evalModules, deferredModule.

**nix-darwin**: System configuration management for macOS using Nix.
Abbreviation: darwin.
Related: macOS, system configuration.

**Nix**: Functional package manager providing declarative, reproducible package management.
Synonym: none.
Related: nixpkgs, NixOS.

**NixOS**: Linux distribution built on Nix package manager.
Synonym: none.
Related: Nix, nixpkgs.

**nixpkgs**: Official Nix packages repository and standard library.
Synonym: none.
Related: Nix, package, channel.

**nixpkgs-stable**: Point releases of nixpkgs (24.05, 24.11, etc.) with backported security fixes.
Synonym: stable, stable channel.
Related: nixpkgs, nixpkgs-unstable, channel.

**nixpkgs-unstable**: Rolling release channel of nixpkgs with latest packages.
Synonym: unstable, unstable channel.
Related: nixpkgs, nixpkgs-stable, channel.

**overlay**: Mechanism to modify or extend nixpkgs package set.
Synonym: nixpkgs overlay.
Related: nixpkgs, package override.

**perSystem**: Flake-parts option for per-architecture module evaluation.
Evaluates deferred modules once for each system in the systems list.
Provides system, config, inputs' arguments specific to each architecture.
Synonym: none.
Related: flake-parts, deferredModule, system.

**SOPS**: Secrets OPerationS, tool for encrypting secrets in version control.
Abbreviation: SOPS (Secrets OPerationS).
Related: age, sops-nix, secrets.

**sops-nix**: Integration of SOPS with NixOS and nix-darwin for secrets management.
Synonym: none.
Related: SOPS, age, secrets.

**specialArgs**: Module system mechanism to pass values into module evaluations.
Synonym: none.
Related: module system, extraSpecialArgs.

## Current architecture terms

**autowiring**: Automatic discovery and configuration of hosts from directory structure.
Synonym: auto-wiring, directory-based discovery.
Related: nixos-unified, configurations directory.

**configurations directory**: OBSOLETE (November 2024). Legacy directory structure replaced by `modules/{darwin,nixos,home}/` in dendritic migration.
Synonym: configs directory.
Related: nixos-unified, modules directory.

**darwin-rebuild**: Command-line tool for activating nix-darwin configurations.
Synonym: none.
Related: nix-darwin, activation.

**direnv**: Tool for automatic environment activation when entering directories.
Synonym: none.
Related: development environment, nix develop.

**just**: Command runner and task automation tool.
Synonym: none.
Related: justfile, task runner.

**justfile**: Configuration file for just task runner defining common operations.
Synonym: none.
Related: just, task automation.

**multi-channel fallback**: Pattern using multiple nixpkgs inputs to handle broken packages without system-wide rollback.
Synonym: nixpkgs stable fallbacks pattern.
Related: nixpkgs, overlay, stable fallback.

**nix develop**: Command to enter development shell defined by flake.
Synonym: dev shell.
Related: flake, devShell, development environment.

**nixos-rebuild**: Command-line tool for activating NixOS configurations.
Synonym: none.
Related: NixOS, activation.

**nixos-unified**: DEPRECATED (November 2024). Framework that provided directory-based autowiring for multi-platform Nix configurations, replaced by dendritic flake-parts + clan architecture.
Abbreviation: none.
Related: flake-parts, autowiring, specialArgs, dendritic flake-parts pattern.

## Target architecture terms

**aspect**: Cross-cutting concern or feature spanning multiple configuration classes (NixOS, nix-darwin, home-manager).
Terminology from [Aspect-Oriented Programming (AOP)](https://en.wikipedia.org/wiki/Aspect-oriented_programming) where aspects are program functionalities cutting across multiple modules.
In deferred module composition: the organizational dimension where each file configures one capability across all relevant platforms.
Synonym: feature, cross-cutting concern.
See [Understanding "aspect"](/concepts/deferred-module-composition/#understanding-aspect).

**clan**: Framework for multi-host NixOS/nix-darwin management providing coordination, inventory system, vars, and service instances. Repository name: clan-core.
Synonym: none (clan-core is the repository name, not an alternative term).
Related: inventory, vars, zerotier, clan vars, service instance.

**clan vars**: Secrets system in clan with centralized generators creating machine-specific outputs.
Target for all secrets with ongoing migration from legacy sops-nix.
Synonym: vars system.
Related: clan, vars generator, secrets, sops.

**controller**: Zerotier role managing network and authorizing peers.
Synonym: zerotier controller.
Related: zerotier, peer, overlay network.

**dendritic flake-parts pattern**: Organizational pattern where every file is a deferred module.
Foundation: nixpkgs module system (deferredModule type, evalModules fixpoint).
Implementation: flake-parts evaluation + import-tree auto-discovery.
Convention: directory-based namespace merging via flake.modules.*.
See [Deferred Module Composition](/concepts/deferred-module-composition/).
Synonym: dendritic pattern, deferred module composition, aspect-based pattern, every-file-is-module.
Related: flake-parts, import-tree, flake.modules, deferredModule, evalModules.

**disko**: Tool for declarative disk partitioning and formatting.
Synonym: none.
Related: partitioning, LUKS, installation.

**flake.modules**: Flake-parts namespace for publishing deferred modules by class.
Type: `lazyAttrsOf (lazyAttrsOf deferredModule)` - attribute sets of deferred modules organized by class (nixos, darwin, homeManager).
Delays evaluation until consumer imports the module into their evalModules call.
Synonym: modules namespace.
Related: deferredModule, dendritic pattern, flake-parts.

**import-tree**: Auto-discovery mechanism recursively importing all `.nix` files from a directory.
Synonym: none.
Related: dendritic pattern, auto-discovery.

**instance**: Clan service instance, potentially spanning multiple machines with different roles.
Synonym: service instance.
Related: clan inventory, role, service.

**inventory**: Clan system for centralized definition of machines, services, and their relationships.
Synonym: clan inventory.
Related: machines, tags, instances, roles.

**LUKS**: Linux Unified Key Setup, disk encryption standard.
Abbreviation: LUKS (Linux Unified Key Setup).
Related: encryption, disko, VPS.

**machine**: Host system in clan inventory (`inventory.machines.<name>`).
Synonym: host.
Related: clan inventory, tag, machineClass.

**machineClass**: Platform type in clan inventory ("nixos" or "darwin").
Synonym: platform type.
Related: clan inventory, machine.

**peer**: Zerotier role for network member (not controller or moon).
Synonym: zerotier peer.
Related: zerotier, controller, overlay network.

**role**: Function within clan service instance (server, client, peer, controller, etc.).
Synonym: service role.
Related: clan inventory, instance.

**srvos**: NixOS modules providing server hardening and best practices.
Abbreviation: srvos (server os).
Related: NixOS, hardening, VPS.

**tag**: Label for grouping machines in clan inventory (e.g., "workstation", "server", "nixos").
Synonym: machine tag.
Related: clan inventory, machine.

**terranix**: Nix-based Terraform configuration generator.
Synonym: none.
Related: terraform, infrastructure provisioning, Hetzner.

**terraform**: Infrastructure-as-code tool for cloud provisioning.
Synonym: none.
Related: terranix, Hetzner Cloud, VPS.

**vars**: Clan system for declarative secret and file generation.
Synonym: clan vars.
Related: generator, secrets, deployment.

**vars generator**: Function defining how to generate secrets or files in clan vars system.
Synonym: generator.
Related: clan vars, script, prompts.

**zerotier**: Overlay VPN solution providing secure private network between hosts.
Synonym: ZT.
Related: overlay network, controller, peer, VPN.

## Host names

**argentum**: Darwin host (aarch64), testing and backup environment.
Meaning: Silver (element Ag), continuing precious metal naming theme.

**blackphos**: Darwin host (aarch64), secondary development environment, first darwin migration in November 2024.
Meaning: Black phosphorus (allotrope of element P), continuing element naming theme.

**cinnabar**: NixOS VPS (x86_64), Hetzner Cloud CX53, zerotier controller, foundation infrastructure.
Meaning: Mercury sulfide mineral (HgS), red color, continuing mineral/element naming theme.

**electrum**: NixOS VPS (x86_64), Hetzner Cloud secondary infrastructure host for distributed services.
Meaning: Natural alloy of gold and silver (Au+Ag), continuing metal/element naming theme.

**galena**: NixOS VPS (x86_64), GCP compute instance for CPU-based compute workloads.
Meaning: Lead sulfide mineral (PbS), primary ore of lead, continuing mineral/element naming theme.

**rosegold**: Darwin host (aarch64), testing and experimental environment.
Meaning: Gold-copper alloy, continuing metal/element naming theme.

**scheelite**: NixOS VPS (x86_64), GCP compute instance for GPU-based compute workloads.
Meaning: Calcium tungstate mineral (CaWO4), ore of tungsten, continuing mineral/element naming theme.

**stibnite**: Darwin host (aarch64), primary daily workstation, migrated last after all others proven stable.
Meaning: Antimony sulfide mineral (Sb2S3), continuing element/mineral naming theme.

## Acronyms and abbreviations

- **ADR**: Architecture Decision Record.
- **API**: Application Programming Interface.
- **CI/CD**: Continuous Integration / Continuous Deployment.
- **CLI**: Command-Line Interface.
- **DAG**: Directed Acyclic Graph.
- **GPG**: GNU Privacy Guard (encryption tool, predecessor to age).
- **GPT**: GUID Partition Table.
- **HM**: home-manager.
- **LUKS**: Linux Unified Key Setup.
- **SOPS**: Secrets OPerationS.
- **SSH**: Secure Shell.
- **VPN**: Virtual Private Network.
- **VPS**: Virtual Private Server.
- **ZT**: Zerotier.

## Architectural terms

**AMDiRE**: Artefact Model for Domain-independent Requirements Engineering.
Description: Framework for artefact-based requirements engineering with context, requirements, and system layers.
Related: context layer, requirements layer, system layer.

**atomic commit**: Single commit containing one logical change to one file.
Related: git workflow, version control.

**bias toward removal**: Design principle of removing code/docs when no longer valuable, relying on git history for preservation.
Related: design principles, ADR-0014.

**context layer**: AMDiRE layer considering system context (domain, stakeholders, goals, constraints).
Related: AMDiRE, requirements layer.

**conventional commit**: Commit message format for semantic versioning (feat:, fix:, docs:, etc.).
Related: git workflow, semantic versioning.

**cross-cutting concern**: Feature spanning multiple configuration classes (darwin + nixos + home-manager).
Related: dendritic pattern, module composition.

**framework independence**: Design principle avoiding framework-specific naming in core identifiers.
Related: design principles, ADR-0014.

**requirements layer**: AMDiRE layer specifying requirements from black-box perspective (system vision, usage model, quality requirements).
Related: AMDiRE, context layer.

**stable fallback**: Multi-channel resilience pattern using stable channel version when unstable broken.
Related: multi-channel fallback, nixpkgs.

**template duality**: Design principle where repository serves as both working deployment and forkable template.
Related: design principles, ADR-0014.

**type safety**: Property of having configuration errors caught through module system type checking.
Related: module system, dendritic pattern.

## Migration terms

**progressive migration**: Strategy of migrating hosts one at a time with validation between each.
Related: stability gate, risk mitigation.

**stability gate**: Requirement for each migrated host to remain stable for 1-2 weeks before proceeding to next.
Related: progressive migration, risk mitigation.

**test-clan**: Experimental repository for validating dendritic + clan integration before production deployment.
Related: validation.

## Workflow terms

**activation**: Process of applying configuration to system (darwin-rebuild switch, nixos-rebuild switch).
Related: deployment, configuration.

**bootstrap**: Initial setup process installing Nix and essential tools.
Related: installation, getting started.

**dry-run**: Testing operation without actually making changes.
Related: activation, validation.

**rollback**: Reverting to previous configuration after issues discovered.
Related: activation, recovery.

**specialArgs antipattern**: Extensive use of specialArgs for passing application values, bypassing module system type checking.
Related: specialArgs, dendritic pattern.

## Provider and service terms

**cachix**: Binary cache service for Nix storing pre-built derivations.
Related: CI/CD, caching.

**Hetzner Cloud**: VPS hosting provider used for cinnabar infrastructure.
Related: VPS, terraform, cinnabar.

**GitHub Actions**: CI/CD platform integrated with GitHub.
Related: CI/CD, workflows.

## File and directory terms

**flake-parts directory**: `modules/flake-parts/` containing flake-level configuration modules.
Related: flake-parts, modules.

**secrets directory**: `secrets/` containing encrypted secrets (current) or `sops/` (clan vars target).
Related: sops-nix, clan vars, encryption.

**modules directory**: Current `modules/{darwin,home,nixos}/` or target `modules/{base,shell,dev,hosts}/`.
Related: module organization, dendritic pattern.

**packages directory**: `packages/` containing custom package definitions.
Related: derivation, overlay.

**overlays directory**: `overlays/` containing nixpkgs overlays for package modifications.
Related: overlay, multi-channel fallback.

## Glossary maintenance

This glossary should be updated when:
- New architectural terms introduced during migration
- Upstream projects add significant new concepts
- Terminology evolves or requires clarification
- Team members request term definitions

Terms should be added, modified, or removed as the system evolves.
Git history preserves removed terms if needed for historical reference.
