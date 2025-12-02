---
title: Contents
sidebar:
  order: 1
---

Task-oriented guides for common operations and workflows with this infrastructure.

## Setup and Onboarding

- [Getting started](getting-started) - Bootstrap Nix and activate your first configuration
- [Host onboarding](host-onboarding) - Add a new darwin (macOS) or NixOS host with platform-specific workflows
- [User onboarding](home-manager-onboarding) - Set up user environments with home-manager

## Customization

- [Adding custom packages](adding-custom-packages) - Create your own package derivations using the pkgs-by-name pattern

## Operations and Maintenance

- [Secrets management](secrets-management) - Manage encrypted secrets with the two-tier model (clan vars + sops-nix)
- [Handling broken packages](handling-broken-packages) - Fix broken packages from nixpkgs unstable with surgical hotfixes
- [MCP servers usage](mcp-servers-usage) - Configure and use Model Context Protocol servers

## Architecture References

For understanding the underlying patterns:
- [Dendritic Architecture](/concepts/dendritic-architecture) - Module organization pattern
- [Clan Integration](/concepts/clan-integration) - Multi-machine coordination and secrets
