# Project Structure

```
nix-config/  (infra repository)
├── flake.nix                                   # 65-line pure import-tree flake
├── flake.lock                                  # Dependency version lock
├── .pre-commit-config.yaml                     # Git hooks (gitleaks, nixfmt)
├── modules/                                    # Dendritic flake-parts modules (auto-discovered)
│   ├── clan/                                   # Clan-core integration (4 files)
│   │   ├── core.nix                            # Import clan-core + terranix flakeModules
│   │   ├── meta.nix                            # Clan metadata + specialArgs propagation
│   │   ├── machines.nix                        # Machine registration (reference dendritic modules)
│   │   └── inventory/                          # Clan inventory (machines + service instances)
│   │       └── machines.nix                    # 5 machines: cinnabar, blackphos, rosegold, argentum, stibnite
│   ├── system/                                 # System-wide NixOS configs (auto-merge to base)
│   │   ├── admins.nix                          # Admin users with SSH keys (crs58)
│   │   ├── nix-settings.nix                    # Nix daemon config (experimental-features, trusted-users)
│   │   └── initrd-networking.nix               # SSH in initrd for remote LUKS unlock (if needed)
│   ├── darwin/                                 # Darwin-specific modules
│   │   ├── base.nix                            # System-wide darwin config (nix settings, state version)
│   │   ├── users.nix                           # Darwin user management (UID 550+ range)
│   │   └── homebrew.nix                        # Homebrew integration (casks for GUI apps)
│   ├── home/                                   # Home-manager modules (dendritic namespace)
│   │   ├── core/                               # Shared home config (shell, git, editors)
│   │   │   ├── zsh.nix
│   │   │   ├── starship.nix
│   │   │   └── git.nix
│   │   └── users/                              # Per-user home configurations
│   │       ├── crs58/                          # Admin user (development tools)
│   │       │   ├── default.nix
│   │       │   └── dev-tools.nix
│   │       ├── raquel/                         # Non-admin user (blackphos)
│   │       │   └── default.nix
│   │       ├── christophersmith/               # Non-admin user (argentum)
│   │       │   └── default.nix
│   │       └── janettesmith/                   # Non-admin user (rosegold)
│   │           └── default.nix
│   ├── machines/                               # Machine-specific configurations
│   │   ├── nixos/                              # NixOS machines
│   │   │   ├── cinnabar/                       # Hetzner VPS (always-on)
│   │   │   │   ├── default.nix                 # Host config (imports base, users, disko)
│   │   │   │   ├── disko.nix                   # ZFS disk layout
│   │   │   │   └── hardware-configuration.nix  # Generated hardware config
│   │   │   └── electrum/                       # Hetzner VPS (togglable)
│   │   │       ├── default.nix
│   │   │       ├── disko.nix
│   │   │       └── hardware-configuration.nix
│   │   └── darwin/                             # Darwin machines
│   │       ├── blackphos/                      # Phase 2: First darwin (raquel + crs58)
│   │       │   └── default.nix
│   │       ├── rosegold/                       # Phase 3: Second darwin (janettesmith + crs58)
│   │       │   └── default.nix
│   │       ├── argentum/                       # Phase 4: Third darwin (christophersmith + crs58)
│   │       │   └── default.nix
│   │       └── stibnite/                       # Phase 5: Primary workstation (crs58 only)
│   │           └── default.nix
│   ├── terranix/                               # Terraform modules (perSystem.terranix)
│   │   ├── base.nix                            # Provider config (hcloud, google)
│   │   ├── config.nix                          # Global terraform config
│   │   └── hetzner.nix                         # Hetzner resources (servers, SSH keys)
│   └── checks/                                 # Test harness (nix-unit + integration)
│       ├── nix-unit.nix                        # Expression evaluation tests
│       ├── integration.nix                     # VM boot tests (runNixOSTest)
│       ├── validation.nix                      # Structural validation tests
│       └── performance.nix                     # Build performance tests
├── sops/                                       # Clan vars storage (encrypted secrets)
│   ├── machines/                               # Per-machine secrets
│   │   ├── cinnabar/
│   │   │   ├── secrets/                        # Encrypted (zerotier-identity-secret, sshd keys)
│   │   │   └── facts/                          # Public facts (zerotier-ip, network-id)
│   │   ├── blackphos/
│   │   ├── rosegold/
│   │   ├── argentum/
│   │   └── stibnite/
│   └── shared/                                 # Shared secrets (if share=true in generators)
├── terraform/                                  # Terraform working directory (git-ignored)
│   ├── .terraform/                             # Provider plugins
│   ├── terraform.tfstate                       # State file (git-ignored, sensitive)
│   └── .gitkeep
├── docs/notes/                                 # Migration documentation
│   ├── clan/
│   │   └── integration-plan.md                 # Phase 0-6 migration strategy
│   └── development/
│       ├── PRD.md                              # Product Requirements Document
│       ├── epics.md                            # Epic breakdown (7 epics, 34 stories)
│       ├── sprint-status.yaml                  # Current sprint status
│       ├── test-clan-validated-architecture.md # Validated patterns from test-clan
│       └── architecture.md                     # This document
└── .envrc                                      # Direnv integration (nix develop shell)
```

**Directory Organization Rationale**:
- **Flat feature categories** (clan/, system/, darwin/, home/, terranix/) not nested by platform (dendritic pattern)
- **Machine configs in machines/{nixos,darwin}/** for platform-specific hosts
- **Auto-merge base** (system/*.nix → flake.modules.nixos.base automatically)
- **Import-tree auto-discovery** (no manual imports, all .nix files discovered)
- **Clan integration via modules/clan/** (separate from application modules)
- **Test harness in modules/checks/** (validation as code)
