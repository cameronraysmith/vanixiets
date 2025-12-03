---
title: "Contents"
description: "Learn to work with this infrastructure repository through tutorials."
sidebar:
  order: 1
---

These tutorials intend to explain how this infrastructure works through hands-on learning, building your understanding progressively from fundamentals to advanced topics. 

:::note
This repository pertains to a particular set of users and machines and is not directly structured as a template, but could relatively easily be treated as such via renaming.
:::

## About these tutorials

In accordance with the [diataxis](https://diataxis.fr/) user documentation framework, these tutorials are **learning-oriented**.
They guide you through exercises that build skills and understanding, explaining *why* things work the way they do, as opposed to only *how* to do them.

This differs from the [Guides](/guides/) section, which is **task-oriented**.
Guides help you accomplish specific goals when you already understand the system.
Tutorials build the understanding that makes guides useful.

| Tutorials (this section) | Guides |
|--------------------------|--------|
| Learning-oriented | Task-oriented |
| Teach concepts and skills | Accomplish specific goals |
| Progressive skill building | Step-by-step procedures |
| Include "why" explanations | Focus on "how" steps |
| For building understanding | For getting things done |

**Start with tutorials** when you're new to the system or a particular area.
**Switch to guides** when you need to accomplish something specific.

## Recommended learning path

If you're new to this infrastructure, follow this sequence:

### 1. Bootstrap to Activation

**[Bootstrap to Activation](/tutorials/bootstrap-to-activation)** — Start here.

Learn how to set up a machine from scratch.
You'll understand Nix flakes, the dendritic module pattern, direnv integration, and the activation process.

- **Prerequisites**: macOS or NixOS machine with admin access
- **Teaches**: Nix fundamentals, repository structure, first activation
- **Estimated time**: 45-60 minutes

### 2. Secrets Setup

**[Secrets Setup](/tutorials/secrets-setup)** — Essential for any real use.

Learn how secrets management works.
You'll understand the two-tier architecture, derive age keys from SSH keys, and set up encrypted secrets that deploy with your configuration.

- **Prerequisites**: Completed Bootstrap to Activation
- **Teaches**: Age encryption, sops-nix, Bitwarden integration
- **Estimated time**: 30-45 minutes

### 3. Platform-specific deployment

Choose based on your target platform:

#### For macOS users

**[Darwin Deployment](/tutorials/darwin-deployment)** — Complete macOS setup.

Learn the full darwin deployment workflow including zerotier mesh networking.
You'll understand how nix-darwin differs from NixOS and the practical implications.

- **Prerequisites**: Completed Bootstrap, Secrets Setup
- **Teaches**: nix-darwin, Homebrew integration, zerotier mesh
- **Estimated time**: 60-90 minutes

#### For server administrators

**[NixOS Deployment](/tutorials/nixos-deployment)** — Cloud server deployment.

Learn how to provision infrastructure and deploy NixOS servers.
You'll understand terranix, clan orchestration, and multi-cloud patterns.

- **Prerequisites**: Completed Bootstrap, Secrets Setup
- **Teaches**: Terranix, clan deployment, multi-cloud
- **Estimated time**: 90-120 minutes

## Tutorial catalog

### [Bootstrap to Activation](/tutorials/bootstrap-to-activation)

Your entry point into this infrastructure.

**What you'll learn:**
- How Nix flakes provide reproducible configuration
- The dendritic pattern for module organization
- Development shell activation with direnv
- Building and activating your first configuration

**Prerequisites:** macOS or NixOS machine, git, internet access

### [Secrets Setup](/tutorials/secrets-setup)

Secure credential management from first principles.

**What you'll learn:**
- Two-tier secrets architecture (clan vars vs sops-nix)
- Age key derivation from SSH keys
- Creating and managing encrypted secrets
- Platform differences (darwin vs NixOS)

**Prerequisites:** Completed Bootstrap to Activation, SSH key in Bitwarden

### [Darwin Deployment](/tutorials/darwin-deployment)

Complete macOS machine deployment.

**What you'll learn:**
- nix-darwin configuration and activation
- Homebrew integration for system extensions
- Zerotier mesh networking setup
- Darwin-specific secrets patterns

**Prerequisites:** Completed Bootstrap and Secrets tutorials, macOS machine

### [NixOS Deployment](/tutorials/nixos-deployment)

Cloud infrastructure and NixOS server deployment.

**What you'll learn:**
- Infrastructure provisioning with terranix
- Clan-based deployment orchestration
- Multi-cloud patterns (Hetzner, GCP)
- Both tiers of secrets on NixOS

**Prerequisites:** Completed Bootstrap and Secrets tutorials, cloud provider access

## After completing tutorials

Once you've worked through the relevant tutorials, you're ready to:

### Use the guides

The [Guides](/guides/) section provides task-oriented procedures:
- [Getting Started](/guides/getting-started) — Quick command reference
- [Host Onboarding](/guides/host-onboarding) — Adding new machines
- [Secrets Management](/guides/secrets-management) — Secret operations

### Deepen your understanding

The [Concepts](/concepts/) section explains the architecture:
- [Dendritic flake-parts Architecture](/concepts/dendritic-architecture) — Module organization pattern
- [Clan Machine Management](/concepts/clan-integration) — Multi-machine coordination
- [Multi-user Management](/concepts/multi-user-patterns) — User configuration approaches

### Reference the CLI

The [Reference](/reference/) section documents tools:
- [justfile recipes](/reference/justfile-recipes) — Task runner commands
- [nix flake apps](/reference/flake-apps) — Nix-wrapped activation commands
- [CI jobs](/reference/ci-jobs) — Continuous integration reference

## Getting help

If you get stuck:

1. **Check the troubleshooting section** at the end of each tutorial
2. **Search the guides** for specific error messages
3. **Review the concepts** if something doesn't make sense
4. **Ask for help** with specific details about what you tried and what happened
