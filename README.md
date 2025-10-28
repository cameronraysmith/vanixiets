<div align="center">

# infra

<a href="https://nix.dev/concepts/flakes" target="_blank">
  <img alt="Nix Flakes Ready" src="https://img.shields.io/static/v1?logo=nixos&logoColor=d8dee9&label=Nix%20Flakes&labelColor=5e81ac&message=Personal%20Config&color=d8dee9&style=for-the-badge">
</a>

[![CI][ci-badge]][ci-link] [![Docs][docs-badge]][docs-link] [![License][license-badge]][license-link]

**Personal nix-config with multi-channel resilience and directory-based autowiring**

[Documentation][docs-link] • [Getting Started](https://infra.cameronraysmith.net/guides/getting-started) • [Architecture](https://infra.cameronraysmith.net/concepts/nix-config-architecture) • [Discussions](https://github.com/cameronraysmith/infra/discussions)

</div>

---

## What This Provides

Personal nix-config for macOS (nix-darwin) and NixOS systems using a three-layer architecture that combines flake-parts modular composition, nixos-unified directory-based autowiring, and proven multi-channel nixpkgs resilience patterns.
When nixpkgs unstable breaks, apply surgical fixes (stable fallback, upstream patch, or build override) without rolling back your entire system.

## Quick Start

```bash
# Bootstrap nix and essential tools
make bootstrap && exec $SHELL

# Clone repository
git clone https://github.com/cameronraysmith/infra.git
cd infra

# Activate direnv
direnv allow

# Activate configuration
just activate
```

See the [Getting Started guide](https://infra.cameronraysmith.net/guides/getting-started) for complete setup instructions.

## Features

- 🏗️ **Directory-based autowiring** - Add a file, get a flake output (nixos-unified)
- 🛡️ **Multi-channel resilience** - Surgical fixes without full rollbacks
- 🔧 **Platform support** - macOS (nix-darwin), Linux (NixOS), standalone home-manager
- 🔑 **Secrets management** - sops-nix with age encryption
- 👥 **Multi-user patterns** - Admin (integrated) and non-admin (standalone) configurations
- 📦 **Custom packages** - starship-jj, claude-code-bin, cc-statusline-rs, and more
- 🔄 **Automated workflows** - nixpkgs bisecting, incident response, systematic troubleshooting
- ⚡ **Development shell** - Complete with direnv integration and justfile automation

## Documentation

**Getting Started:**
[Bootstrap Guide](https://infra.cameronraysmith.net/guides/getting-started) • [Host Onboarding](https://infra.cameronraysmith.net/guides/host-onboarding) • [Home Manager Onboarding](https://infra.cameronraysmith.net/guides/home-manager-onboarding)

**Architecture:**
[Nix-Config Architecture](https://infra.cameronraysmith.net/concepts/nix-config-architecture) • [Understanding Autowiring](https://infra.cameronraysmith.net/concepts/understanding-autowiring) • [Multi-User Patterns](https://infra.cameronraysmith.net/concepts/multi-user-patterns) • [Repository Structure](https://infra.cameronraysmith.net/reference/repository-structure)

**Operations:**
[Secrets Management](https://infra.cameronraysmith.net/guides/secrets-management) • [Nixpkgs Hotfixes](https://infra.cameronraysmith.net/development/architecture/nixpkgs-hotfixes) • [Incident Response](https://infra.cameronraysmith.net/guides/nixpkgs-incident-response)

📘 **Full documentation:** https://infra.cameronraysmith.net/

## License

[AGPL-3.0](LICENSE)

## Credits

Built with [flake-parts](https://github.com/hercules-ci/flake-parts), [nixos-unified](https://github.com/srid/nixos-unified), and resilience patterns from [mirkolenz/nixos](https://github.com/mirkolenz/nixos).

See [complete credits](https://infra.cameronraysmith.net/about/credits) for full acknowledgments.

[ci-badge]: https://github.com/cameronraysmith/infra/actions/workflows/ci.yaml/badge.svg
[ci-link]: https://github.com/cameronraysmith/infra/actions/workflows/ci.yaml
[docs-badge]: https://img.shields.io/badge/docs-infra.cameronraysmith.net-blue
[docs-link]: https://infra.cameronraysmith.net
[license-badge]: https://img.shields.io/badge/license-AGPL--3.0-blue
[license-link]: https://spdx.org/licenses/AGPL-3.0-only.html
