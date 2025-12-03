<div align="center">

# infra

<a href="https://nix.dev/concepts/flakes" target="_blank">
  <img alt="Nix Flakes Ready" src="https://img.shields.io/static/v1?logo=nixos&logoColor=d8dee9&label=Nix%20Flakes&labelColor=5e81ac&message=infrastructure&color=d8dee9&style=for-the-badge">
</a>

[![CI][ci-badge]][ci-link] [![Docs][docs-badge]][docs-link] [![License][license-badge]][license-link]

**declarative, reproducible, type-safe infrastructure with nix flake modules**

> And all this to realize compositional algebras of graded effects, structured as indexed monad transformer stacks over effectful computations, from heterogeneous components to support experimentation, discovery, and understanding of the past in the present for the future.

[Documentation][docs-link] • [Getting Started](https://infra.cameronraysmith.net/guides/getting-started) • [Architecture](https://infra.cameronraysmith.net/concepts/nix-config-architecture) • [Discussions](https://github.com/cameronraysmith/infra/discussions)

</div>

---

## What This Provides

Nix flake-based system configurations for NixOS, nix-darwin, and home-manager using dendritic flake-parts pattern with clan-core integration for multi-machine coordination and multi-channel overlay composition.

## Quick Start

> [!WARNING]
> These commands install the Nix package manager system-wide (multi-user daemon), modify shell initialization files, and apply system configurations. You almost surely don't want to execute them without reading the relevant source.

```bash
# Clone repository
git clone https://github.com/cameronraysmith/infra.git
cd infra

# Bootstrap nix and essential tools
make bootstrap && exec $SHELL

# Activate direnv
direnv allow

# Activate configuration
just activate
```

See the [Getting Started guide](https://infra.cameronraysmith.net/guides/getting-started) for complete setup instructions.

## Features

⊕ **Dendritic module organization** - import-tree auto-discovers Nix files organized by aspect (feature) rather than host, with every file being a flake-parts module that exports to dendritic namespaces (flake.modules.darwin.*, flake.modules.home.*, flake.modules.nixos.*)

⋈ **Per-package nixpkgs channel selection** - Multi-channel overlay architecture enables unstable default with selective stable fallbacks via modules/nixpkgs/overlays/hotfixes.nix without requiring full flake.lock rollback

⊛ **Cross-platform deployment targets** - NixOS, nix-darwin, or home-manager configurations

⊎ **Multi-user configuration patterns** - Admin users with integrated system/home-manager configurations and non-admin users with standalone home-manager deployments

⊢ **Declarative secrets management** - sops-nix integration with age encryption for managing encrypted secrets

⊠ **Composable package overlays** - layered overlay composition (multi-channel access → hotfixes → custom packages → build overrides → flake input overlays) for package customization and dependency management

↯ **Reproducible development environments** - Nix development shell with direnv activation and just task runner

## Documentation

**Getting Started:**
[Bootstrap Guide](https://infra.cameronraysmith.net/guides/getting-started) • [Host Onboarding](https://infra.cameronraysmith.net/guides/host-onboarding) • [Home Manager Onboarding](https://infra.cameronraysmith.net/guides/home-manager-onboarding)

**Architecture:**
[Nix-Config Architecture](https://infra.cameronraysmith.net/concepts/nix-config-architecture) • [Dendritic Architecture](https://infra.cameronraysmith.net/concepts/dendritic-architecture) • [Multi-User Patterns](https://infra.cameronraysmith.net/concepts/multi-user-patterns) • [Repository Structure](https://infra.cameronraysmith.net/reference/repository-structure)

**Operations:**
[Secrets Management](https://infra.cameronraysmith.net/guides/secrets-management) • [Nixpkgs Hotfixes](https://infra.cameronraysmith.net/development/architecture/nixpkgs-hotfixes) • [Handling Broken Packages](https://infra.cameronraysmith.net/guides/handling-broken-packages)

📘 **Full documentation:** <https://infra.cameronraysmith.net/>

## License

[MIT](LICENSE)

## Credits

Built with [flake-parts](https://github.com/hercules-ci/flake-parts), [import-tree](https://github.com/vic/import-tree), [clan-core](https://clan.lol), and overlay patterns from [mirkolenz/nixos](https://github.com/mirkolenz/nixos).

See [complete credits](https://infra.cameronraysmith.net/about/credits) for full acknowledgments.

[ci-badge]: https://github.com/cameronraysmith/infra/actions/workflows/ci.yaml/badge.svg
[ci-link]: https://github.com/cameronraysmith/infra/actions/workflows/ci.yaml
[docs-badge]: https://img.shields.io/badge/docs-infra.cameronraysmith.net-blue
[docs-link]: https://infra.cameronraysmith.net
[license-badge]: https://img.shields.io/badge/license-MIT-blue
[license-link]: https://spdx.org/licenses/MIT.html
