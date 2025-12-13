---
title: Contents
sidebar:
  order: 1
---

Conceptual documentation to help you understand the architecture and design patterns used in this infrastructure.

## Overview

- [Architecture overview](/concepts/architecture-overview/) - Understanding the architecture combining deferred module composition, clan, and multi-channel overlay composition

## Module system foundations

- [Module system primitives](/concepts/module-system-primitives/) - Understanding deferredModule, evalModules, and fixpoint computation - the foundations that enable Nix configuration composition
- [Flake-parts and the module system](/concepts/flake-parts-module-system/) - How flake-parts wraps nixpkgs evalModules to provide flake composition, perSystem evaluation, and namespace conventions

## Configuration patterns

- [Deferred module composition](/concepts/deferred-module-composition/) - Understanding deferred module composition where every Nix file is a module organized by aspect
- [Clan Integration](/concepts/clan-integration/) - Multi-machine coordination with clan and clear boundaries with other tools
- [System-user integration](/concepts/system-user-integration/) - Understanding admin users with integrated home-manager vs non-admin standalone users
