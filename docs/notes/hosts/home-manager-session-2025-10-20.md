# Session Summary: Home-Manager-Only User Configuration

**Date**: 2025-10-20
**Branch**: beta  
**Status**: ✅ Complete - Ready for activation

## Objective

Set up home-manager-only configurations for non-admin users (runner, raquel) on blackphos and stibnite, where admin user (crs58) already has nix-darwin configured.

## What was accomplished

### 1. Secrets Architecture Refactoring

**Problem identified**: The shared `secrets/radicle.yaml` was encrypted only for admin-user, preventing raquel from decrypting signing keys.

**Solution implemented**: Per-user signing keys with proper isolation.

**Changes**:
- Added `sopsIdentifier` field to user configs in `config.nix`
  - `admin-user`: cameron, crs58, runner, jovyan
  - `raquel-user`: raquel
- Restructured secrets directory:
  ```
  secrets/users/
  ├── admin-user/
  │   ├── signing-key.yaml
  │   ├── llm-api-keys.yaml
  │   ├── mcp-api-keys.yaml
  │   └── NP3W1uaSSCXgMAJGatirTtTsHWnnxJNp-config.yaml
  └── raquel-user/
      ├── signing-key.yaml
      ├── llm-api-keys.yaml  (placeholder)
      └── mcp-api-keys.yaml  (placeholder)
  ```
- Updated `.sops.yaml` with granular per-user encryption rules
- Removed shared `secrets/radicle.yaml`

### 2. Module Updates

**Fixed dynamic user lookup** in all development modules:
- `modules/home/all/development/git.nix`
- `modules/home/all/development/jujutsu.nix`
- `modules/home/all/development/radicle.nix`
- `modules/home/all/tools/claude-code-wrappers.nix`
- `modules/home/all/tools/claude-code/mcp-servers.nix`

**Pattern used**:
```nix
let
  # Look up user config based on home.username (set by each home configuration)
  user = flake.config.${config.home.username};
in
{
  sops.secrets."${user.sopsIdentifier}/signing-key" = {
    sopsFile = flake.inputs.self + "/secrets/users/${user.sopsIdentifier}/signing-key.yaml";
    mode = "0400";
  };
}
```

This ensures:
- `runner@blackphos` → `home.username = "runner"` → `flake.config.runner.sopsIdentifier = "admin-user"` ✓
- `raquel@blackphos` → `home.username = "raquel"` → `flake.config.raquel.sopsIdentifier = "raquel-user"` ✓

### 3. Configurations Created

**Successfully built and verified**:
- ✅ `raquel@blackphos` (home-manager-only on darwin)
- ✅ `raquel@stibnite` (home-manager-only on darwin)

**Configuration pattern**:
```nix
# configurations/home/raquel@blackphos.nix
{
  flake,
  pkgs,
  lib,
  ...
}:
let
  inherit (flake) config inputs;
  inherit (inputs) self;
  user = config.raquel;
in
{
  imports = [
    self.homeModules.default
    self.homeModules.darwin-only
    self.homeModules.standalone
  ];

  home.username = user.username;
  home.homeDirectory = "/Users/${user.username}";
  home.stateVersion = "23.11";

  # User-specific overrides
  programs.git = {
    userName = lib.mkForce user.fullname;
    userEmail = lib.mkForce user.email;
  };

  # Disable heavy tools
  programs.lazyvim.enable = lib.mkForce false;
}
```

### 4. Documentation

Created comprehensive guide: `docs/notes/hosts/home-manager-only-onboarding.md`

**Covers**:
- Architecture: admin nix-darwin vs non-admin home-manager-only
- Step-by-step onboarding procedure
- SOPS secrets management for non-admin users
- How configurations coexist without conflicts
- Troubleshooting guide

## Commits made

Session commits (efae6dd..e12767a):

1. **efae6dd** - `feat(sops): implement per-user signing keys architecture`
   - Restructure secrets to per-user directories
   - Add sopsIdentifier to config.nix
   - Update .sops.yaml with granular rules

2. **f95a306** - `fix(sops): use sopsIdentifier in claude-code modules`
   - Fix claude-code-wrappers.nix and mcp-servers.nix
   - Use user.sopsIdentifier instead of config.home.username

3. **9c185e4** - `feat(secrets): add placeholder API keys for raquel-user`
   - Create minimal llm-api-keys.yaml and mcp-api-keys.yaml for raquel

4. **662a0b1** - `feat(home): add raquel@stibnite configuration`
   - Create raquel@stibnite.nix (matches raquel@blackphos pattern)

5. **e12767a** - `docs(hosts): add home-manager-only onboarding guide`
   - Comprehensive documentation for non-admin user setup

## Key architectural insights

### How nixos-unified autowiring works

```nix
# modules/flake-parts/nixos-flake.nix
imports = [
  inputs.nixos-unified.flakeModules.autoWire
];
```

Autodiscovery rules:
- `configurations/darwin/<hostname>.nix` → `darwinConfigurations.<hostname>`
- `configurations/nixos/<hostname>.nix` → `nixosConfigurations.<hostname>`
- `configurations/home/<user>@<host>.nix` → `homeConfigurations."<user>@<host>"`

### How admin and non-admin configs coexist

```
/nix/store/                    # Shared (admin manages via daemon)
└── Packages dedupl icated across all users

/nix/var/nix/profiles/
├── system/                    # nix-darwin (admin only)
└── per-user/
    ├── crs58/                 # Admin's home-manager (via nix-darwin integration)
    ├── runner/                # Non-admin home-manager (standalone)
    └── raquel/                # Non-admin home-manager (standalone)
```

**No conflicts** because:
- Admin controls system-level via nix-darwin
- Each user has independent home-manager generation
- Shared `/nix/store` provides deduplication
- SOPS secrets properly isolated by user

### Secrets encryption model

**Per-user isolation**:
- Each user has separate signing key in `secrets/users/<sopsIdentifier>/signing-key.yaml`
- Encrypted only for that user's age key + admin + dev
- Modules dynamically look up correct path via `user.sopsIdentifier`

**Result**:
- runner/jovyan/cameron/crs58 all use `admin-user` signing key (same person)
- raquel uses `raquel-user` signing key (different person)
- Proper isolation without secret sharing

## What's ready for activation

**On blackphos** (admin should test as each user):
1. As runner: `just activate` → activates `runner@blackphos`
2. As raquel: `just activate` → activates `raquel@blackphos`

**On stibnite**:
1. As raquel: `just activate` → activates `raquel@stibnite`

**Pre-activation checklist** (for each user):
```bash
cd ~/projects/nix-config
nix develop
export BW_SESSION=$(bw unlock --raw)
just sops-sync-keys  # Creates ~/.config/sops/age/keys.txt
bw lock

# Test decryption
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops -d secrets/users/<sopsIdentifier>/signing-key.yaml | head -5

# Activate
just activate
```

## Future improvements

**Template user directory** (noted for implementation):
- Create `secrets/users/template-user/` with placeholder files
- New user setup: `cp -r secrets/users/template-user secrets/users/<new-sopsIdentifier>`
- Run `just update-all-keys` to re-encrypt for correct age keys
- Makes adding new users straightforward

**Update needed**: Document this pattern in onboarding guide.

## Success criteria

- ✅ Per-user signing keys implemented
- ✅ Modules use dynamic user lookup via config.home.username
- ✅ raquel@blackphos builds successfully
- ✅ raquel@stibnite builds successfully
- ✅ Comprehensive documentation created
- ✅ Secrets properly isolated by user
- ⏳ Template user directory (documented, implementation deferred)
- ⏳ Actual activation on blackphos/stibnite (user will do interactively)

