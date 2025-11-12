# API Contracts

## Dendritic Module Interface

**Module Export Pattern**:
```nix
# Every module contributes to flake.modules.* namespace
{
  flake.modules.<platform>.<feature-name> = { config, pkgs, lib, ... }: {
    # NixOS/darwin/home-manager module content
  };
}
```

**Module Import Pattern**:
```nix
# Machines reference modules via config.flake.modules
{
  imports = with config.flake.modules.<platform>; [
    base           # Auto-merged system-wide config
    feature1       # Explicit feature import
    feature2
  ];
}
```

**Contract**:
- **Input**: Standard NixOS module arguments (`config`, `pkgs`, `lib`, `inputs` via specialArgs)
- **Output**: Configuration merged into machine config
- **No side effects**: Pure configuration, no external state modification
- **Type-safe**: Options declared with explicit types

## Clan Vars Generator Interface

**Generator Definition**:
```nix
{
  clan.core.vars.generators.<generator-name> = {
    files = {
      "<filename>" = {
        secret = true | false;     # Encrypt file? (true = /run/secrets/, false = nix store)
        deploy = true | false;     # Deploy to target machine? (default: true)
        neededFor = [ "users" ];   # Deployment stage (users, boot, network, etc.)
      };
    };
    dependencies = [ "<other-generator>" ];  # Run after these generators
    share = true | false;          # Share across all machines? (default: false)
    prompts = {
      "<prompt-name>" = {
        type = "line" | "hidden" | "multiline";
        description = "User-facing prompt text";
      };
    };
    script = ''
      # Bash script with runtimeInputs available in PATH
      # Output files to $out/<filename>
      # Read prompts from $prompts/<prompt-name>
    '';
    runtimeInputs = [ pkgs.package1 pkgs.package2 ];  # Packages available in script
  };
}
```

**Generator Execution**:
```bash
# Generate vars for a machine
clan vars generate <machine-name>

# Regenerate specific generator
clan vars generate <machine-name> --generator <generator-name>

# View generated facts (public)
clan facts show <machine-name>
```

**Output Structure**:
- **Secrets**: `sops/machines/<machine>/secrets/<generator>.<filename>` (encrypted)
- **Facts**: `sops/machines/<machine>/facts/<generator>.<filename>` (unencrypted)
- **Deployment**: `/run/secrets/<generator>.<filename>` (on target machine)

**Contract**:
- **Idempotent**: Re-running generator produces same output (deterministic where possible)
- **Isolated**: Generators run in isolated environment with only declared runtimeInputs
- **Atomic**: All files generated or none (transaction-like)
- **Versioned**: Generated files tracked in git (sops/), encrypted via age

## Clan Service Instance Interface

**Service Module Contract**:
```nix
{
  _class = "clan.service";  # Required service class marker

  roles.<roleName> = {
    interface.options = {
      # Options available to this role (standard NixOS options)
    };

    perInstance = { lib, config, pkgs, name, value, ... }: {
      nixosModule | darwinModule = { config, ... }: {
        # Configuration applied to machines with this role
        # Access instance settings via value.settings
        # Access role settings via value.roles.<roleName>.settings
      };
    };
  };

  perMachine = { lib, config, pkgs, name, value, ... }: {
    nixosModule | darwinModule = { config, ... }: {
      # Configuration applied to all machines using this service
      # Access machine-specific settings
    };
  };
}
```

**Service Deployment**:
- **Inventory declaration**: Define service instance with roles in `clan.inventory.instances`
- **Machine assignment**: Assign machines to roles via explicit machines or tags
- **Configuration hierarchy**: Instance → Role → Machine settings
- **Module generation**: Clan generates nixosModule/darwinModule per machine

**Built-in Services** (clan-core):
- **zerotier**: Mesh VPN (controller/peer/moon roles)
- **sshd**: SSH daemon with CA certificates (server/client roles)
- **emergency-access**: Root password recovery (default role)
- **users**: User account management (default role)
- **tor**: Tor hidden services (default role)
