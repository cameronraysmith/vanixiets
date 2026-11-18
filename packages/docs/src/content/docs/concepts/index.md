---
title: Contents
sidebar:
  order: 1
---

Conceptual documentation to help you understand the architecture and design patterns used in this infrastructure.

## Overview

- [Architecture overview](/concepts/architecture-overview/) - Understanding the architecture combining deferred module composition, clan, and multi-channel overlay composition
- [Fleet topology](/concepts/fleet-topology/) - Where each service runs, which fleet networks each host joins, and which host answers each public hostname, generated from the clan inventory

## Module system foundations

- [Module system primitives](/concepts/module-system-primitives/) - Understanding deferredModule, evalModules, and fixpoint computation - the foundations that enable Nix configuration composition
- [Flake-parts and the module system](/concepts/flake-parts-module-system/) - How flake-parts wraps nixpkgs evalModules to provide flake composition, perSystem evaluation, and namespace conventions

## Configuration patterns

- [Deferred module composition](/concepts/deferred-module-composition/) - Understanding deferred module composition where every Nix file is a module organized by aspect
- [Clan Integration](/concepts/clan-integration/) - Multi-machine coordination with clan and clear boundaries with other tools
- [System-user integration](/concepts/system-user-integration/) - Understanding admin users with integrated home-manager vs non-admin standalone users

## Build and CI

- [Build service topology](/concepts/build-service-topology/) - nixbot, the one CI build service on magnetite, and the boundaries that scope what it builds
- [Darwin build access](/concepts/darwin-build-access/) - How the fleet reaches stibnite's aarch64-darwin store, and why the remote builder and the remote store are two mechanisms
