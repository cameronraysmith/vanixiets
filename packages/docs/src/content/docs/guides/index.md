---
title: Contents
sidebar:
  order: 1
---

Task-oriented guides for common operations and workflows with this infrastructure.

## Setup and Onboarding

- [Getting started](/guides/getting-started/) - Bootstrap Nix and activate your first configuration
- [Host onboarding](/guides/host-onboarding/) - Add a new darwin (macOS) or NixOS host with platform-specific workflows
- [User onboarding](/guides/home-manager-onboarding/) - Set up user environments with home-manager

## Customization

- [Adding custom packages](/guides/adding-custom-packages/) - Create your own package derivations using the pkgs-by-name pattern

## Operations and Maintenance

- [Secrets management](/guides/secrets-management/) - Manage encrypted secrets with the two-tier model (clan vars + sops-nix)
- [Handling broken packages](/guides/handling-broken-packages/) - Fix broken packages from nixpkgs unstable with surgical stable fallbacks
- [MCP servers usage](/guides/mcp-server-usage/) - Configure and use Model Context Protocol servers

## Architecture References

For understanding the underlying patterns:
- [Deferred Module Composition](/concepts/deferred-module-composition) - Module organization pattern
- [Clan Integration](/concepts/clan-integration) - Multi-machine coordination and secrets
