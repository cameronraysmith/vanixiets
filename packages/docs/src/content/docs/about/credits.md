---
title: Credits
description: Acknowledgments and project credits
---

This infrastructure configuration builds on work from the Nix community.

## Primary frameworks

### Flake-parts

- **[flake-parts](https://flake.parts)** by Robert Hensing (@roberth) and Hercules CI (@hercules-ci) - The modular flake framework that enables defining and integrating deferred modules to configure multiple systems

### Import-tree

- **[import-tree](https://github.com/vic/import-tree)** by Victor Borja (@vic) - Automatic module discovery mechanism from a given directory subtree

### Dendritic pattern documentation

The "dendritic" pattern is a community convention for aspect-based module organization using flake-parts and import-tree.

- **[dendrix](https://vic.github.io/dendrix/Dendritic.html)** by Victor Borja (@vic) - Community ecosystem, documentation, and dendritic module "distribution"
- **[dendritic](https://github.com/mightyiam/dendritic)** by Shahar "Dawn" Or (@mightyiam) - "Awesome" dendritic flake-parts

### Clan

- **[clan](https://clan.lol/)** - Multi-machine coordination and deployment framework

### Multi-channel resilience

- **[mirkolenz/nixos](https://github.com/mirkolenz/nixos)** by Mirko Lenz - Multi-channel nixpkgs patterns and overlay composition strategies

## Reference implementations

These implementations informed the architectural patterns:

### Dendritic pattern examples

- **[drupol/infra](https://github.com/drupol/infra)** by Pol Dellaiera (@drupol) - Uses flake-parts based deferred modules and illustrates the "aspect"-based factorization of dependencies
- **[GaetanLepage/nix-config](https://github.com/GaetanLepage/nix-config)** by Gaétan Lepage (@GaetanLepage) - Uses flake-parts based deferred modules and illustrates configuration of a host possessing a GPU

### Clan references

- **[clan-infra](https://git.clan.lol/clan/clan-infra)** - Production clan usage by clan team
- **[qubasa/nixos-configs](https://git.clan.lol/Qubasa/nixos-configs)** - Clan core developer reference
- **[mic92/dotfiles](https://github.com/Mic92/dotfiles)** - Clan core developer reference

### Other inspirations

- **[NickCao/flakes](https://github.com/NickCao/flakes)** - Advanced flake techniques
- **[Misterio77/nix-config](https://github.com/Misterio77/nix-config)** - Comprehensive nix-config reference

## Core technologies

- **[Nix](https://nixos.org/)** - Reproducible builds and deployments
- **[NixOS](https://nixos.org/)** - Linux distribution built on Nix
- **[nix-darwin](https://github.com/LnL7/nix-darwin)** - Nix-based macOS system configuration
- **[home-manager](https://github.com/nix-community/home-manager)** - User environment management with Nix
- **[sops-nix](https://github.com/Mic92/sops-nix)** - Secrets management for Nix
- **[terranix](https://terranix.org/)** - NixOS-native Terraform configuration
