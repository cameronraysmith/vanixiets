---
title: Credits
description: Acknowledgments and project credits
---

This infrastructure configuration builds on work from the Nix community.

## Primary frameworks

### Dendritic flake-parts pattern

The dendritic pattern provides aspect-based module organization where every Nix file is a flake-parts module.

- **[dendritic](https://github.com/mightyiam/dendritic)** by Shahar "Dawn" Or (@mightyiam) - Pattern definition and reference implementation
- **[dendrix](https://vic.github.io/dendrix/Dendritic.html)** by Victor Borja (@vic) - Community ecosystem and comprehensive documentation
- **[import-tree](https://github.com/vic/import-tree)** by Victor Borja (@vic) - Automatic module discovery mechanism

### Flake-parts ecosystem

- **[hercules-ci/flake-parts](https://flake.parts)** by Robert Hensing and Hercules CI - Modular flake composition framework

### Clan-core

- **[clan-core](https://clan.lol/)** - Multi-machine coordination and deployment framework

### Multi-channel resilience

- **[mirkolenz/nixos](https://github.com/mirkolenz/nixos)** by Mirko Lenz - Multi-channel nixpkgs patterns and overlay composition strategies

## Reference implementations

These implementations informed the architectural patterns:

### Dendritic pattern references

- **[drupol/infra](https://github.com/drupol/infra)** by Pol Dellaiera (@drupol) - Comprehensive dendritic implementation
- **[mightyiam/infra](https://github.com/mightyiam/infra)** by Shahar "Dawn" Or - Original dendritic reference
- **[gaetanlepage/nix-config](https://github.com/gaetanlepage/nix-config)** by Gaétan Lepage - Dendritic pattern at scale

### Clan-core references

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
