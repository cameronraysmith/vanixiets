---
title: Architecture
---

Architecture documentation for the vanixiets multi-machine infrastructure configuration.

This repository manages a heterogeneous fleet of 8 machines across 2 platforms using declarative Nix configuration.
The infrastructure coordinates 4 nix-darwin laptops and 4 nixos servers through dendritic flake-parts module organization, clan-core multi-machine orchestration, and terranix cloud provisioning.

## Overview

The architecture follows a feature-based organizational pattern where capabilities are defined once and consumed by machine configurations.
Infrastructure provisioning, system deployment, and secrets management are separated into distinct layers with clear boundaries.

Key architectural components:
- Dendritic flake-parts provides feature-based module organization with auto-discovery
- Clan-core orchestrates deployment across darwin and nixos machines
- Terranix provisions cloud infrastructure on Hetzner and GCP
- Five-layer overlay composition enables surgical package fixes without system-wide rollbacks
- Two-tier secrets architecture separates system-level generated secrets from user credentials

## System Specification

[Architecture](/development/architecture/architecture/) provides a comprehensive system specification following AMDiRE methodology with component models, function models, behavior models, interface models, and data models.

## Architecture Decision Records

[ADRs](/development/architecture/adrs/) documents all major technical and design decisions with context, alternatives considered, and consequences.

## Reference Documentation

- [Nixpkgs Hotfixes](/development/architecture/nixpkgs-hotfixes/) - Multi-channel nixpkgs resilience system with five-layer overlay composition
