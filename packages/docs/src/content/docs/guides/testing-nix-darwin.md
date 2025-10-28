---
title: Testing Nix-Darwin Configuration
sidebar:
  order: 8
---

  For the agent to test each file before committing:

  # 1. Build configuration
  nix build .#darwinConfigurations.stibnite.config.system.build.toplevel --accept-flake-config

  # 2. Check for build errors (exit code 0 = success)
  echo $?

  # 3. See what changed (optional, informative)
  nix store diff-closures /run/current-system ./result
