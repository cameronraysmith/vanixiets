# Novel Pattern Designs

**Pattern 1: Auto-Merge Base Modules via Import-Tree**

**Problem**: Dendritic pattern requires explicit module exports, but system-wide configurations (nix settings, admin users, initrd networking) should be automatically available to all machines without manual imports.

**Solution**: Import-tree automatically merges all files in `modules/system/` into `flake.modules.nixos.base`:

```nix
# modules/system/nix-settings.nix
{ flake.modules.nixos.base.nix.settings = { experimental-features = ["nix-command" "flakes"]; }; }

# modules/system/admins.nix
{ flake.modules.nixos.base.users.users.crs58 = { extraGroups = ["wheel"]; }; }

# Result: Single merged base module
flake.modules.nixos.base = {
  nix.settings = { ... };
  users.users.crs58 = { ... };
  boot.initrd.network = { ... };
};
```

**Benefits**:
- Zero manual imports for base functionality
- Single reference in machine configs: `imports = [ config.flake.modules.nixos.base ];`
- Add new system-wide config: create file in `system/` → auto-merged
- Test-clan validated (Stories 1.1-1.7, 17 test cases passing)

**Pattern 2: Portable Home-Manager Modules with Dendritic Integration**

**Problem**: User home-manager configurations need to work across platforms (darwin + NixOS) and support three integration modes (darwin integrated, NixOS integrated, standalone) without duplication.

**Gap Identified (Story 1.8)**: blackphos implemented inline home configs, blocking cross-platform reuse. This is a feature regression from infra's proven modular pattern.

**Solution (Story 1.8A - COMPLETE)**: Extracted home configs into portable modules that export to dendritic namespace and support all three integration modes. Validated in test-clan with zero regression (270 packages preserved, 46 lines of duplication removed from blackphos).

**Module Structure:**
```nix
# modules/home/users/{username}/default.nix
{
  flake.modules.homeManager."users/{username}" = { config, pkgs, lib, ... }: {
    home.stateVersion = "23.11";
    programs.zsh.enable = true;
    programs.starship.enable = true;
    programs.git.enable = true;
    home.packages = with pkgs; [ git gh ... ];
  };
}
```

**Three Integration Modes:**

**Mode 1: Darwin Integrated** (blackphos example)
```nix
# In darwin machine module
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.crs58.imports = [
    config.flake.modules.homeManager."users/crs58"
  ];
}
```

**Mode 2: NixOS Integrated** (cinnabar Story 1.9)
```nix
# In NixOS machine module
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.crs58.imports = [
    config.flake.modules.homeManager."users/crs58"
  ];
}
```

**Mode 3: Standalone** (nh home CLI workflow)
```nix
# In modules/home/configurations.nix
{
  flake.homeConfigurations.crs58 = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs { system = "aarch64-darwin"; };
    modules = [
      config.flake.modules.homeManager."users/crs58"
    ];
  };
}

# Usage: nh home switch . -c crs58
```

**Benefits:**
- Single source of truth (DRY principle): User defined once, used on 6 machines
- Cross-platform portability: Same module works on darwin and NixOS
- Three deployment contexts: Integrated (system + home), standalone (home only)
- Dendritic auto-discovery: No manual imports in flake.nix
- Username-only naming: No @hostname for maximum portability
- Clan compatible: Users defined per machine, configs imported modularly

**Lesson from Story 1.8:**
Inline home configs are anti-pattern for multi-machine infrastructure. Always modularize user configs to enable cross-platform reuse.

**Implementation Status (Story 1.8A):**
- ✅ crs58 and raquel modules created in test-clan (`modules/home/users/{username}/default.nix`)
- ✅ Exported to dendritic namespace (`flake.modules.homeManager."users/{username}"`)
- ✅ Standalone homeConfigurations exposed (`flake.homeConfigurations.{crs58,raquel}`)
- ✅ blackphos refactored to import from namespace (zero regression validated)
- ✅ Standalone activation tested (`nh home switch . -c {username}`)
- ✅ Pattern ready for Story 1.9 (cinnabar NixOS needs crs58 module)

**Pattern 3: Darwin Multi-User with Per-User Vars Naming**

**Problem**: Clan vars generators are machine-scoped, not user-scoped. Multi-user darwin machines (blackphos: raquel + crs58) need separate secrets per user.

**Solution**: Use naming convention in generator names:

```nix
# Generate per-user secrets with naming convention
clan.core.vars.generators."ssh-key-crs58" = {
  files."id_ed25519".neededFor = "users";
  files."id_ed25519.pub".secret = false;
  script = ''ssh-keygen -t ed25519 -N "" -C "crs58@${config.networking.hostName}" -f "$out"/id_ed25519'';
};

clan.core.vars.generators."ssh-key-raquel" = {
  files."id_ed25519".neededFor = "users";
  files."id_ed25519.pub".secret = false;
  script = ''ssh-keygen -t ed25519 -N "" -C "raquel@${config.networking.hostName}" -f "$out"/id_ed25519'';
};

# Result storage
vars/per-machine/blackphos/ssh-key-crs58/id_ed25519
vars/per-machine/blackphos/ssh-key-raquel/id_ed25519
```

**Admin vs Non-Admin Differentiation**:
```nix
# modules/darwin/users.nix
users.users.crs58 = {
  uid = 550;
  extraGroups = [ "admin" ];  # Darwin equivalent of "wheel"
  home = "/Users/crs58";
};

users.users.raquel = {
  uid = 551;
  extraGroups = [ ];  # No admin group = no sudo
  home = "/Users/raquel";
};

# Security configuration
security.sudo.wheelNeedsPassword = false;  # Passwordless sudo for admins
```

**Home-Manager Per-User**:
```nix
home-manager.users.crs58.imports = with config.flake.modules.homeManager; [
  core.zsh
  users.crs58.dev-tools  # Admin user gets full dev environment
];

home-manager.users.raquel.imports = with config.flake.modules.homeManager; [
  core.zsh  # Non-admin gets minimal shell config only
];
```

**Benefits**:
- Standard NixOS user management (no clan-specific patterns)
- Per-user secrets via generator naming convention
- Clear admin/non-admin separation via `extraGroups`
- Home-manager configs scale independently
- Validated in production examples (clan-infra admins.nix, mic92 bernie machine)

**Pattern 3: Darwin Networking Options (Zerotier Workaround)**

**Problem**: Clan zerotier service is NixOS-only (systemd dependencies, no darwin support). Darwin hosts need mesh networking but clan service doesn't work.

**Solution**: Multiple validated options with trade-offs:

**Option A: Homebrew Zerotier** (maintains zerotier consistency):
```nix
# modules/darwin/homebrew.nix
homebrew.enable = true;
homebrew.casks = [ "zerotier-one" ];  # GUI app via homebrew

# Manual network join after installation
# Use clan-generated network-id: /run/secrets/zerotier-network-id
# Command: zerotier-cli join $(cat /run/secrets/zerotier-network-id)
```

**Option B: Custom Launchd Service** (nix-managed zerotier):
```nix
# modules/darwin/zerotier-custom.nix
launchd.daemons.zerotierone = {
  serviceConfig = {
    Program = "${pkgs.zerotierone}/bin/zerotier-one";
    ProgramArguments = [ "${pkgs.zerotierone}/bin/zerotier-one" ];
    KeepAlive = true;
    RunAtLoad = true;
  };
};

# Reference identity from clan vars
environment.etc."zerotier-one/identity.secret".source =
  config.clan.core.vars.generators.zerotier.files.zerotier-identity-secret.path;
```

**Hybrid Approach** (recommended for Story 1.8):
- Use clan vars generators for identity/network-id (platform-agnostic Python scripts)
- Manual zerotier setup on darwin (homebrew or custom launchd)
- Cinnabar controller auto-accepts peers using clan-generated zerotier-ip

**Benefits**:
- Maintains clan vars for identity management (reusable patterns)
- Defers darwin networking implementation to Story 1.8 (experimental validation)
- Multiple proven alternatives (tailscale, homebrew, custom launchd)
- No blocking unknowns for architecture documentation

**Pattern 4: Terranix Toggle-Based Deployment**

**Problem**: Multiple cloud VMs (cinnabar always-on, electrum togglable) need declarative deployment control without destroying terraform state.

**Solution**: Per-machine `enabled` flag in terranix configuration:

```nix
# modules/terranix/hetzner.nix
{ config, lib, ... }:
let
  machines = {
    hetzner-ccx23 = {
      enabled = false;  # Destroy this VM
      server_type = "ccx23";
      location = "nbg1";
    };
    hetzner-cx43 = {
      enabled = true;   # Deploy this VM
      server_type = "cx43";
      location = "fsn1";
    };
  };

  enabledMachines = lib.filterAttrs (_: m: m.enabled) machines;
in
{
  perSystem = { config, pkgs, ... }: {
    terranix.terraform.resource.hcloud_server = lib.mapAttrs (name: cfg: {
      name = name;
      server_type = cfg.server_type;
      location = cfg.location;
      # ...
    }) enabledMachines;
  };
}
```

**Terraform Operations**:
```bash
# Deploy enabled machines only
nix run .#terraform.terraform -- apply

# Toggle machine: set enabled = false → terraform apply → VM destroyed
# Toggle back: set enabled = true → terraform apply → VM recreated
```

**Benefits**:
- Declarative VM lifecycle management
- Toggle without manual terraform destroy commands
- Preserves terraform state for both machines
- Test-clan validated (hetzner-ccx23 toggled off, hetzner-cx43 deployed)

**Pattern 5: Test Harness with Multiple Categories**

**Problem**: Complex infrastructure requires different validation types (fast expression tests, slow VM integration tests, structural validation, performance benchmarks).

**Solution**: Multi-category test harness with selective execution:

```nix
# modules/checks/nix-unit.nix
flake.checks."${system}".test-nix-unit-all = pkgs.stdenv.mkDerivation {
  name = "test-nix-unit-all";
  buildCommand = ''
    export HOME=$TMPDIR
    ${nix-unit}/bin/nix-unit \
      --flake "${self}#checks.${system}.nix-unit-tests" \
      --eval-store "$HOME"
  '';
};

# modules/checks/integration.nix (runNixOSTest)
flake.checks."${system}".test-vm-boot-hetzner-ccx23 =
  self.nixosConfigurations.hetzner-ccx23.config.system.build.vmWithBootLoaderTest or null;
```

**Test Execution Matrix**:
| Category | Tool | Tests | Duration | Systems | Purpose |
|----------|------|-------|----------|---------|---------|
| nix-unit | nix-unit | 11 | ~1s | all (x86_64-linux, aarch64-linux, aarch64-darwin) | Fast expression evaluation |
| integration | runNixOSTest | 2 | ~2-5min | Linux only | VM boot validation |
| validation | runCommand | 4 | ~4s | all | Structural invariants |
| performance | runCommand | 0 | ~0s | all | Build time benchmarks (future) |

**Selective Execution**:
```bash
# Fast tests only (< 5s)
nix flake check --no-build

# Full validation (includes VM tests)
nix flake check

# Specific category
nix build .#checks.x86_64-linux.test-nix-unit-all
```

**Benefits**:
- Fast feedback loop (nix-unit tests ~1s)
- Comprehensive validation (17 test cases across 4 categories)
- Platform-aware (VM tests skip on darwin)
- Test-clan validated (all 17 tests passing)
