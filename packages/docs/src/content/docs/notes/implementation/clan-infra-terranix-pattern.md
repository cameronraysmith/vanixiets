---
title: Clan-infra terranix pattern extraction
---

Complete guide for implementing terranix with flake-parts in test-clan, based on clan-infra's proven patterns.

## Architecture overview

### Key components

1. **Terranix flake module** - Imported from terranix input, provides `perSystem.terranix` interface
2. **Terranix modules** - Exported as `flake.modules.terranix.*`, consumed by terranixConfigurations
3. **Machine-specific terraform configs** - Per-machine terraform configuration files
4. **State encryption** - OpenTofu state encryption via passphrase from clan secrets
5. **Clan secrets integration** - Provider credentials fetched via `clan secrets get`

### File structure in clan-infra

```
clan-infra/
├── flake.nix                           # Imports terranix.flakeModule
├── machines/
│   ├── flake-module.nix               # perSystem.terranix configurations
│   ├── build01/
│   │   └── terraform-configuration.nix # Machine-specific terraform
│   ├── web01/
│   │   └── terraform-configuration.nix
│   └── ...
├── modules/
│   ├── flake-module.nix               # Exports flake.modules.terranix.*
│   └── terranix/
│       ├── base.nix                   # Base config (providers, secrets)
│       ├── dns.nix                    # DNS resources
│       ├── with-dns.nix               # DNS module reference
│       ├── vultr.nix                  # Vultr resources
│       ├── cache.nix                  # Fastly CDN config
│       └── cache-new.nix
└── sops/
    └── secrets/
        ├── tf-passphrase/             # State encryption passphrase
        ├── hetznerdns-token/          # Provider credentials
        └── vultr-api-key/
```

## Step-by-step implementation for test-clan

### Step 1: flake.nix changes

The terranix flake module must be imported into flake-parts.

#### Add terranix input (if not already present)

```nix
{
  inputs = {
    # ... existing inputs ...

    terranix.url = "github:terranix/terranix";
    terranix.inputs.flake-parts.follows = "flake-parts";
    terranix.inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

#### Import terranix.flakeModule in machines/flake-module.nix

**Exact pattern from clan-infra:**

```nix
# machines/flake-module.nix
{ self, inputs, ... }:
{
  imports = [
    inputs.terranix.flakeModule  # This is the key import
  ];

  # clan configuration...
  clan = {
    # ... clan config ...
  };

  # terranix configuration...
  perSystem = { inputs', pkgs, ... }: {
    terranix = {
      # configurations go here...
    };
  };
}
```

### Step 2: Create modules/flake-module.nix structure

This file exports terranix modules to `flake.modules.terranix.*` for reuse.

**Create `/Users/crs58/projects/nix-workspace/infra/modules/flake-module.nix`:**

```nix
{
  moduleWithSystem,
  flake-parts-lib,
  self,
  inputs,
  ...
}:
{
  # Export terranix modules for use in terranixConfigurations
  flake.modules.terranix.base = ./terranix/base.nix;

  # Advanced pattern: moduleWithSystem for cross-referencing terranixConfigurations
  # This allows the main terraform config to reference the dns config as a module
  flake.modules.terranix.with-dns = moduleWithSystem (
    { config }: flake-parts-lib.importApply ./terranix/with-dns.nix { config' = config; }
  );

  flake.modules.terranix.dns = flake-parts-lib.importApply ./terranix/dns.nix { inherit self; };

  # Add more modules as needed
  # flake.modules.terranix.provider-xyz = ./terranix/provider-xyz.nix;
}
```

### Step 3: Create terranix modules directory

**Directory structure:**

```
modules/
├── flake-module.nix
└── terranix/
    ├── base.nix         # Base terraform config
    ├── dns.nix          # DNS resources
    └── with-dns.nix     # DNS module reference
```

#### modules/terranix/base.nix

This module sets up terraform providers and fetches credentials from clan secrets.

**Pattern from clan-infra:**

```nix
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Passphrase variable for state encryption
  variable.passphrase = { };

  # Required providers
  terraform.required_providers.external.source = "hashicorp/external";
  terraform.required_providers.hetznerdns.source = "timohirt/hetznerdns";
  # Add more providers as needed

  # Fetch hetznerdns token from clan secrets
  data.external.hetznerdns-token = {
    program = [
      (lib.getExe (
        pkgs.writeShellApplication {
          name = "get-clan-secret";
          text = ''
            jq -n --arg secret "$(clan secrets get hetznerdns-token)" '{"secret":$secret}'
          '';
        }
      ))
    ];
  };

  # Configure provider with secret
  provider.hetznerdns.apitoken = config.data.external.hetznerdns-token "result.secret";
}
```

**Key patterns:**

- `variable.passphrase = { };` - Declares variable for state encryption
- `data.external.*` - Executes shell script to fetch clan secrets at terraform runtime
- `pkgs.writeShellApplication` - Creates executable script
- `lib.getExe` - Gets executable path
- `provider.*.* = config.data.external.* "result.secret"` - References secret value

#### modules/terranix/dns.nix

DNS-specific resources.

```nix
{ self }:
{ config, ... }:
{
  # DNS zones
  resource.hetznerdns_zone.example_com = {
    name = "example.com";
    ttl = 3600;
  };

  # DNS records
  resource.hetznerdns_record = {
    machine01_vpn = {
      zone_id = config.resource.hetznerdns_zone.example_com "id";
      name = "machine01.vpn";
      type = "AAAA";
      # This references zerotier IP from clan machine config
      inherit
        (self.nixosConfigurations.machine01.config.clan.core.vars.generators.zerotier.files.zerotier-ip)
        value
        ;
    };
  };

  # Output zone ID for use in other configs
  output.example_com_zone_id = {
    value = config.resource.hetznerdns_zone.example_com "id";
  };
}
```

**Key patterns:**

- `{ self }:` - Access to flake self for referencing nixosConfigurations
- `inherit (self.nixosConfigurations.*.config.clan.core.vars.generators.zerotier.files.zerotier-ip) value;` - Pull generated clan facts into terraform
- `output.*` - Export values for cross-config references

#### modules/terranix/with-dns.nix

References the dns terranixConfiguration as a terraform module.

```nix
{ config' }:
{
  pkgs,
  lib,
  ...
}:
{
  # Import dns configuration as a terraform module
  module.dns = {
    source = toString (
      pkgs.linkFarm "dns-module" [
        {
          name = "config.tf.json";
          path = config'.terranix.terranixConfigurations.dns.result.terraformConfiguration;
        }
      ]
    );
    passphrase = lib.tf.ref "var.passphrase";
  };
}
```

**Key patterns:**

- `{ config' }:` - Receives perSystem config from moduleWithSystem
- `config'.terranix.terranixConfigurations.dns.result.terraformConfiguration` - References another terranixConfiguration
- `pkgs.linkFarm` - Creates directory with terraform config for module import
- `module.dns = { source = ...; }` - Standard terraform module syntax

### Step 4: Configure perSystem.terranix

This is where terranixConfigurations are declared.

**Add to machines/flake-module.nix:**

```nix
{ self, inputs, ... }:
{
  imports = [
    inputs.terranix.flakeModule
  ];

  clan = {
    # ... existing clan config ...
  };

  perSystem = {
    inputs',
    pkgs,
    ...
  }: {
    terranix =
      let
        # OpenTofu with required providers
        package = pkgs.opentofu.withPlugins (p: [
          p.hashicorp_external
          p.hashicorp_local
          p.timohirt_hetznerdns
          p.hashicorp_null
          p.hashicorp_tls
        ]);
      in
      {
        # DNS-only configuration (used as module by terraform config)
        terranixConfigurations.dns = {
          workdir = "terraform";  # Where terraform state lives
          modules = [
            self.modules.terranix.base
            self.modules.terranix.dns
          ];
          terraformWrapper.package = package;
          terraformWrapper.extraRuntimeInputs = [ inputs'.clan-core.packages.default ];
          terraformWrapper.prefixText = ''
            TF_VAR_passphrase=$(clan secrets get tf-passphrase)
            export TF_VAR_passphrase
          '';
        };

        # Main terraform configuration
        terranixConfigurations.terraform = {
          workdir = "terraform";
          modules = [
            self.modules.terranix.base
            self.modules.terranix.with-dns  # Import dns as module
            # Machine-specific configs
            ./machine01/terraform-configuration.nix
            ./machine02/terraform-configuration.nix
          ];
          terraformWrapper.package = package;
          terraformWrapper.extraRuntimeInputs = [ inputs'.clan-core.packages.default ];
          terraformWrapper.prefixText = ''
            # Fetch passphrase from clan secrets
            TF_VAR_passphrase=$(clan secrets get tf-passphrase)
            export TF_VAR_passphrase

            # Configure state encryption
            TF_ENCRYPTION=$(cat <<'EOF'
            key_provider "pbkdf2" "state_encryption_password" {
              passphrase = var.passphrase
            }
            method "aes_gcm" "encryption_method" {
              keys = key_provider.pbkdf2.state_encryption_password
            }
            state {
              enforced = true
              method = method.aes_gcm.encryption_method
            }
            EOF
            )

            # shellcheck disable=SC2090
            export TF_ENCRYPTION
          '';
        };
      };
  };
}
```

**Key patterns:**

- `let package = pkgs.opentofu.withPlugins (p: [ ... ]); in` - Define terraform/opentofu package with providers
- `workdir = "terraform"` - Both dns and terraform use same workdir
- `modules = [ self.modules.terranix.* ]` - Reference exported modules
- `terraformWrapper.package` - Which terraform/opentofu binary to use
- `terraformWrapper.extraRuntimeInputs = [ inputs'.clan-core.packages.default ]` - Make `clan` CLI available
- `terraformWrapper.prefixText` - Shell script run before terraform commands
- `TF_VAR_passphrase=$(clan secrets get tf-passphrase)` - Fetch secret and export as terraform variable
- `TF_ENCRYPTION` - OpenTofu state encryption configuration

### Step 5: Machine-specific terraform configurations

Each machine can have its own terraform resources.

**Create machines/machine01/terraform-configuration.nix:**

```nix
{
  lib,
  ...
}:
let
  base_ipv4 = "1.2.3.4";
  base_ipv6 = "2001:db8::1";
in
{
  terraform.required_providers.hetznerdns.source = "timohirt/hetznerdns";

  resource.hetznerdns_record = {
    machine01_a = {
      zone_id = lib.tf.ref "module.dns.example_com_zone_id";
      name = "machine01";
      type = "A";
      value = base_ipv4;
    };

    machine01_aaaa = {
      zone_id = lib.tf.ref "module.dns.example_com_zone_id";
      name = "machine01";
      type = "AAAA";
      value = base_ipv6;
    };
  };
}
```

**Key patterns:**

- `lib.tf.ref "module.dns.example_com_zone_id"` - Reference output from dns module
- Machine-specific resources in dedicated files
- No special imports needed, just define resources

### Step 6: Setup clan secrets

#### Create tf-passphrase secret

```bash
# Generate random passphrase
openssl rand -base64 32 > /tmp/tf-passphrase

# Create clan secret
clan secrets set tf-passphrase < /tmp/tf-passphrase

# Clean up
rm /tmp/tf-passphrase
```

#### Create provider secrets

```bash
# Hetzner DNS token
clan secrets set hetznerdns-token
# Paste token, press Ctrl+D

# Other provider credentials as needed
clan secrets set provider-api-key
```

### Step 7: Usage commands

#### Initialize terraform

```bash
nix run .#terraform -- init
```

#### Plan changes

```bash
nix run .#terraform -- plan
```

#### Apply changes

```bash
nix run .#terraform -- apply
```

#### Access DNS configuration directly (if needed)

```bash
nix run .#dns -- plan
```

## Important patterns explained

### Why separate dns and terraform configs?

**Pattern from clan-infra:**

- `dns` terranixConfiguration defines DNS zones and core records
- `terraform` terranixConfiguration imports dns as a terraform module via `with-dns.nix`
- This allows terraform config to reference DNS outputs: `lib.tf.ref "module.dns.example_com_zone_id"`
- Avoids circular dependencies and enables modular terraform organization

### State encryption with OpenTofu

**Pattern:**

```bash
TF_ENCRYPTION=$(cat <<'EOF'
key_provider "pbkdf2" "state_encryption_password" {
  passphrase = var.passphrase
}
method "aes_gcm" "encryption_method" {
  keys = key_provider.pbkdf2.state_encryption_password
}
state {
  enforced = true
  method = method.aes_gcm.encryption_method
}
EOF
)
export TF_ENCRYPTION
```

**Why:**

- OpenTofu native state encryption (terraform doesn't have this)
- Passphrase-based encryption using PBKDF2 + AES-GCM
- `enforced = true` prevents accidentally creating unencrypted state
- Passphrase stored in clan secrets, fetched at runtime

### Clan secrets in terraform

**Pattern:**

```nix
data.external.hetznerdns-token = {
  program = [
    (lib.getExe (
      pkgs.writeShellApplication {
        name = "get-clan-secret";
        text = ''
          jq -n --arg secret "$(clan secrets get hetznerdns-token)" '{"secret":$secret}'
        '';
      }
    ))
  ];
};

provider.hetznerdns.apitoken = config.data.external.hetznerdns-token "result.secret";
```

**Why:**

- Terraform data.external runs shell script and captures JSON output
- Script calls `clan secrets get` to fetch encrypted secret
- Secret only exists in memory during terraform run
- No plaintext secrets in git or terraform state

### Machine deployment automation

**Pattern from clan-infra (build01):**

```nix
{ config, ... }:
{
  terraform.required_providers.local.source = "hashicorp/local";

  resource.null_resource.install-build01 = {
    provisioner.local-exec = {
      command = "clan machines install build01 --update-hardware-config nixos-facter --target-host root@157.90.137.201 -i '${config.resource.local_sensitive_file.ssh_deploy_key "filename"}' --yes --debug";
    };
  };
}
```

**Why:**

- `null_resource` with `local-exec` provisioner runs `clan machines install`
- References terraform-generated SSH key: `config.resource.local_sensitive_file.ssh_deploy_key "filename"`
- Enables fully automated machine provisioning from terraform

### Referencing clan facts in terraform

**Pattern from dns.nix:**

```nix
resource.hetznerdns_record.machine01_vpn = {
  zone_id = config.resource.hetznerdns_zone.example_com "id";
  name = "machine01.vpn";
  type = "AAAA";
  inherit
    (self.nixosConfigurations.machine01.config.clan.core.vars.generators.zerotier.files.zerotier-ip)
    value
    ;
};
```

**Why:**

- Zerotier IP is generated by clan facts
- Terraform can read from nixosConfigurations to get generated values
- Creates DNS records automatically from clan-managed infrastructure

## Minimal test-clan implementation checklist

### Required files

1. **flake.nix**
   - Add terranix input with follows
   - No direct terranix imports here

2. **modules/flake-module.nix** (new file)
   - Export `flake.modules.terranix.base`
   - Export `flake.modules.terranix.dns`
   - Export `flake.modules.terranix.with-dns` using moduleWithSystem

3. **modules/terranix/base.nix** (new file)
   - `variable.passphrase = { };`
   - Provider declarations
   - Clan secrets fetching via data.external

4. **modules/terranix/dns.nix** (new file)
   - DNS zones
   - DNS records
   - Outputs for zone IDs

5. **modules/terranix/with-dns.nix** (new file)
   - `module.dns` reference via linkFarm

6. **machines/flake-module.nix** (modify)
   - `imports = [ inputs.terranix.flakeModule ];`
   - Add `perSystem.terranix` configuration
   - Define terranixConfigurations.dns
   - Define terranixConfigurations.terraform

7. **machines/machine01/terraform-configuration.nix** (new file)
   - Machine-specific terraform resources

### Required secrets

```bash
clan secrets set tf-passphrase
clan secrets set hetznerdns-token
# Add more provider secrets as needed
```

### Import modules/flake-module.nix in flake.nix

**Add to flake.nix imports:**

```nix
{
  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        # ... existing imports ...
        ./modules/flake-module.nix  # Add this
      ];
    };
}
```

## Differences from dendritic patterns

### What clan-infra does NOT use

- No dendritic namespacing (bmad, crs, etc.)
- No dendritic-specific directory structures
- Standard flake-parts patterns only
- Flat module structure in modules/terranix/

### What to copy directly

- Exact terranix.flakeModule import pattern
- Exact perSystem.terranix structure
- Exact terraformWrapper configuration
- Exact state encryption prefixText
- Exact clan secrets fetching pattern

### What to adapt

- Module names (base, dns, with-dns → your names)
- Provider plugins list
- Machine names and IPs
- DNS zones and records

## Testing the implementation

### Verify terranix configurations are available

```bash
nix flake show
# Should show:
# └───packages
#     ├───x86_64-linux
#     │   ├───dns: package '...'
#     │   └───terraform: package '...'
```

### Test terraform wrapper

```bash
nix run .#terraform -- version
# Should show OpenTofu version and list providers
```

### Test clan secrets integration

```bash
nix run .#terraform -- init
nix run .#terraform -- plan
# Should fetch secrets and show plan without errors
```

### Test state encryption

```bash
nix run .#terraform -- apply
cat terraform/terraform.tfstate
# Should see encrypted content (not plaintext JSON)
```

## Troubleshooting

### "clan: command not found" in terraform

**Fix:** Add to terraformWrapper.extraRuntimeInputs:

```nix
terraformWrapper.extraRuntimeInputs = [ inputs'.clan-core.packages.default ];
```

### "jq: command not found" in data.external

**Fix:** Add jq to writeShellApplication runtimeInputs:

```nix
pkgs.writeShellApplication {
  name = "get-clan-secret";
  runtimeInputs = [ pkgs.jq ];
  text = ''
    jq -n --arg secret "$(clan secrets get hetznerdns-token)" '{"secret":$secret}'
  '';
}
```

### "module.dns not found"

**Fix:** Ensure both configs use same workdir:

```nix
terranixConfigurations.dns.workdir = "terraform";
terranixConfigurations.terraform.workdir = "terraform";
```

### State not encrypted

**Fix:** Check prefixText exports TF_ENCRYPTION:

```bash
export TF_ENCRYPTION
# Must be at end of prefixText
```

## Next steps

1. Implement minimal pattern in test-clan
2. Test with real providers (Hetzner DNS recommended for simplicity)
3. Add machine-specific configs one at a time
4. Later: refactor to dendritic patterns if desired (namespace modules, etc.)

## References

- clan-infra source: `/Users/crs58/projects/nix-workspace/clan-infra/`
- Terranix docs: https://terranix.org
- OpenTofu state encryption: https://opentofu.org/docs/language/state/encryption/
