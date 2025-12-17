---
description: Add process-compose integration with dual Nix/non-Nix support for local development
---

Add process-compose integration for local development with dual Nix/non-Nix support.

Read the CLAUDE.md files in these ecosystem repos for context and patterns:
- ~/projects/nix-workspace/process-compose (upstream Go tool, YAML format)
- ~/projects/nix-workspace/process-compose-flake (Nix module layer)
- ~/projects/nix-workspace/services-flake (pre-built service modules)
- ~/projects/nix-workspace/process-compose-flake-shell (devShell integration)

First analyze this project to identify needed services (database, cache, queue, dev server, etc.) based on existing dependencies and configuration.

Deliverables:

1. flake.nix:
   - Import process-compose-flake.flakeModule
   - Use services-flake modules for standard services when applicable
   - Custom processes use `lib.getExe pkgs.X` for reproducible commands
   - Include test process to generate flake checks

2. process-compose.yaml (repo root):
   - Standalone equivalent for non-Nix users
   - Matching process names, dependencies, health probes
   - Commands assume tools in PATH
   - Comments mapping commands to Nix package names

3. justfile recipes:
   - `services`: Nix-native via `nix run .#<name>`
   - `services-yaml`: Direct `process-compose up -f process-compose.yaml`

4. README.md section documenting both approaches with prerequisites

The two configs should be semantically equivalent - same services, same behavior - differing only in how commands are resolved (Nix store paths vs PATH lookup).

Optional: If unified devShell experience is valuable, consider the process-compose-flake-shell pattern where `nix develop` provides both tools and managed services.
