# Unified cryptographic infrastructure implementation plan

Implementation guide for adopting the unified SSH key pattern from [defelo-nixos](~/projects/nix-workspace/defelo-nixos) into this nix-config repository.

## Overview

This plan implements a unified cryptographic infrastructure using a single SSH Ed25519 key for multiple purposes:

1. **Radicle node identity** - P2P repository synchronization and identity
2. **Git commit signing** - SSH-based commit verification
3. **Jujutsu commit signing** - Shared SSH signature verification with Git

## Current state

**Existing components**:
- ✅ SOPS-nix integration with Age encryption
- ✅ Age keys at `~/.config/sops/age/keys.txt`
- ✅ Git SSH signing (using `~/.ssh/id_ed25519.pub`)
- ✅ Structured secrets in `secrets/` directory
- ✅ `.sops.yaml` with multi-host/user configuration

**Target unified SSH key**:
- **Public key**: `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+`
- **Bitwarden entry**: `sops-admin-user-ssh`
- **Current location**: `~/.ssh/id_ed25519` (private key)
- **SHA256 fingerprint**: `SHA256:WbnjY1SC0MRG1pujS+EzxIpSBi13f8c7c2tVtI+8/BE`
- **Email**: `cameron.ray.smith@gmail.com` (from config.nix)

**Needs implementation**:
- ❌ Separate secrets repository as flake input
- ❌ Radicle client installation and configuration
- ❌ Upstream Jujutsu flake integration
- ❌ Jujutsu migration from GPG to SSH signing
- ❌ SOPS deployment of unified SSH key to `~/.radicle/keys/radicle`

## Architecture

### Unified key deployment flow

```
~/.ssh/id_ed25519 (existing private key)
    ↓
Encrypt with SOPS/Age
    ↓
Store in secrets repository (~/projects/nix-workspace/nix-secrets/)
    ↓
Add as flake input to nix-config
    ↓
SOPS deploys to ~/.radicle/keys/radicle at runtime
    ↓
Referenced by: Git signing + Jujutsu signing + Radicle identity
```

### Configuration reuse pattern

```nix
# Git configuration
programs.git.signing.key = config.sops.secrets."radicle/ssh-private-key".path;
programs.git.extraConfig.gpg.ssh.allowedSignersFile = "/path/to/allowed-signers";

# Jujutsu reuses Git's configuration
programs.jujutsu.settings.signing.key = config.sops.secrets."radicle/ssh-private-key".path;
programs.jujutsu.settings.signing.backends.ssh.allowed-signers =
  config.programs.git.extraConfig.gpg.ssh.allowedSignersFile;

# Radicle uses the same deployed key
home.file.".radicle/keys/radicle" = {
  source = config.sops.secrets."radicle/ssh-private-key".path;
};
```

## Implementation phases

### Phase 1: Create secrets repository structure

**Goal**: Set up separate `nix-secrets` repository with flake structure.

**Location**: `~/projects/nix-workspace/nix-secrets/`

**Actions**:

1. Create directory structure:
```bash
mkdir -p ~/projects/nix-workspace/nix-secrets
cd ~/projects/nix-workspace/nix-secrets
git init

mkdir -p hosts/stibnite/secrets
mkdir -p shared
```

2. Create `flake.nix` exposing secret paths:
```nix
{
  description = "SOPS-encrypted secrets for nix-config";

  outputs = { self, ... }: {
    # Expose secrets per host
    secrets = {
      # stibnite (Darwin)
      stibnite = {
        # Unified SSH key for Radicle + Git + Jujutsu
        radicle = ./hosts/stibnite/secrets/radicle.yaml;

        # Test/example secrets
        test = ./shared/test.yaml;
      };

      # Future: blackphos (NixOS)
      blackphos = {
        radicle = ./hosts/blackphos/secrets/radicle.yaml;
        test = ./shared/test.yaml;
      };

      # Future: orb-nixos (NixOS)
      orb-nixos = {
        radicle = ./hosts/orb-nixos/secrets/radicle.yaml;
        test = ./shared/test.yaml;
      };
    };
  };
}
```

3. Create `.sops.yaml` configuration:
```yaml
keys:
  # Use existing Age key from main config
  - &admin age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8

creation_rules:
  # Host-specific secrets
  - path_regex: hosts/stibnite/.*\.yaml$
    key_groups:
      - age:
          - *admin

  - path_regex: hosts/blackphos/.*\.yaml$
    key_groups:
      - age:
          - *admin

  - path_regex: hosts/orb-nixos/.*\.yaml$
    key_groups:
      - age:
          - *admin

  # Shared secrets
  - path_regex: shared/.*\.yaml$
    key_groups:
      - age:
          - *admin
```

4. Create `.gitignore`:
```
# Unencrypted keys (safety check)
*.key
*.pem
id_*
!*.yaml
!*.yml
```

**Testing**:
```bash
# Verify flake structure
cd ~/projects/nix-workspace/nix-secrets
nix flake show

# Should show: secrets.stibnite, secrets.blackphos, secrets.orb-nixos
```

**Commit point**: `feat(secrets): initialize secrets repository structure`

---

### Phase 2: Encrypt unified SSH key with SOPS

**Goal**: Encrypt the existing `~/.ssh/id_ed25519` private key and create test secrets.

**Actions**:

1. Create the Radicle key secret file:
```bash
cd ~/projects/nix-workspace/nix-secrets
sops hosts/stibnite/secrets/radicle.yaml
```

In the SOPS editor, add:
```yaml
radicle:
  ssh-private-key: |
    [paste contents of ~/.ssh/id_ed25519 here]
```

2. Create test secret:
```bash
sops shared/test.yaml
```

In the SOPS editor:
```yaml
test:
  example-value: "This is a test secret to verify SOPS deployment works"
  timestamp: "2025-10-15"
```

3. Test decryption works:
```bash
# Verify key decrypts
sops -d hosts/stibnite/secrets/radicle.yaml

# Verify test secret decrypts
sops -d shared/test.yaml
```

4. Create initial commit:
```bash
git add .
git commit -m "feat(secrets): add encrypted radicle key and test secrets"
```

**Verification**:
- ✓ `radicle.yaml` contains encrypted SSH private key
- ✓ `test.yaml` contains encrypted test value
- ✓ Both files decrypt successfully with your Age key
- ✓ Files are committed to git (encrypted, safe to commit)

**Commit point**: `feat(secrets): add encrypted radicle key and test secrets`

---

### Phase 3: Add secrets as flake input

**Goal**: Integrate secrets repository into main nix-config flake.

**File**: `flake.nix`

**Actions**:

1. Add secrets as flake input (after existing inputs, before outputs):
```nix
inputs = {
  # ... existing inputs ...

  # Secrets repository (local for now, can move to Radicle later)
  secrets.url = "git+file:///Users/crs58/projects/nix-workspace/nix-secrets";
  secrets.flake = true;
};
```

2. Pass secrets to configurations via nixos-unified:

The `nixos-unified.flakeModules.autoWire` should automatically make the secrets input available to configurations. We'll verify this works by checking if secrets are accessible in home-manager modules.

**Testing**:
```bash
cd ~/projects/nix-workspace/nix-config

# Update flake lock
nix flake lock --update-input secrets

# Verify flake evaluates
nix flake show

# Check secrets are accessible
nix eval .#darwinConfigurations.stibnite.config.home-manager.users.crs58.home.homeDirectory
```

**Commit point**: `feat(secrets): add secrets repository as flake input`

---

### Phase 4: Add upstream Jujutsu flake

**Goal**: Add upstream Jujutsu flake for latest SSH signing features (revset-based `sign-on-push`).

**Reference**: [defelo-nixos flake.nix:24](~/projects/nix-workspace/defelo-nixos/flake.nix)

**File**: `flake.nix`

**Actions**:

1. Add jujutsu upstream flake input:
```nix
inputs = {
  # ... existing inputs ...

  jj.url = "github:martinvonz/jj";
  jj.inputs.nixpkgs.follows = "nixpkgs";
};
```

2. Create overlay to use upstream jujutsu:

**File**: `overlays/packages/jujutsu-upstream.nix` (new file)
```nix
{ inputs }:
final: prev: {
  # Override jujutsu with upstream version for latest SSH signing features
  jujutsu = inputs.jj.packages.${final.system}.jujutsu;
}
```

3. Register overlay in `overlays/default.nix`:
```nix
{
  # Add to the list of overlays
  jujutsu-upstream = import ./packages/jujutsu-upstream.nix { inherit inputs; };
}
```

4. Update `modules/flake-parts/nixos-flake.nix` to include jj in primary inputs:
```nix
primary-inputs = [
  "nixpkgs"
  "home-manager"
  "nix-darwin"
  "nixos-unified"
  "nix-index-database"
  "omnix"
  "jj"  # Add this
];
```

**Testing**:
```bash
# Update flake lock
nix flake lock --update-input jj

# Check jujutsu version
nix build .#jujutsu
./result/bin/jj --version

# Should show latest version from upstream (likely newer than nixpkgs)
```

**Commit point**: `feat(jujutsu): add upstream flake for latest SSH signing features`

---

### Phase 5: Update SOPS home-manager configuration

**Goal**: Configure SOPS to deploy the unified SSH key to `~/.radicle/keys/radicle`.

**File**: `modules/home/all/core/sops.nix`

**Actions**:

1. Update SOPS configuration to handle secrets flake input:
```nix
{
  config,
  pkgs,
  lib,
  self,
  inputs,  # Add inputs to access secrets
  ...
}:
{
  # Configure sops age key location using XDG paths
  sops.age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt";

  # Remove defaultSopsFile (we'll specify per-secret now)
  # sops.defaultSopsFile = ../../../../secrets/shared.yaml;

  # Note: Individual modules will declare secrets using:
  # sops.secrets."radicle/ssh-private-key" = {
  #   sopsFile = inputs.secrets.secrets.<hostname>.radicle;
  # };
}
```

**Note**: We need to ensure `inputs.secrets` is available. Check how nixos-unified passes inputs to home-manager modules.

**Testing**:
```bash
# Check SOPS module loads without errors
nix build .#darwinConfigurations.stibnite.config.home-manager.users.crs58.home.activationPackage
```

**Commit point**: `refactor(sops): prepare for per-secret sopsFile configuration`

---

### Phase 6: Configure Git SSH signing with unified key

**Goal**: Update Git configuration to use SOPS-deployed unified SSH key.

**File**: `modules/home/all/development/git.nix`

**Actions**:

1. Update signing configuration to use SOPS secret:
```nix
{
  pkgs,
  flake,
  config,
  lib,
  inputs,  # Add to access secrets
  ...
}:
let
  package = pkgs.gitAndTools.git;

  # Get hostname for secrets selection
  hostname = flake.config.me.username;  # or however you determine hostname
in
{
  programs.git = {
    inherit package;
    enable = true;
    userName = flake.config.me.fullname;
    userEmail = flake.config.me.email;

    signing = {
      # Point to SOPS-deployed key
      key = config.sops.secrets."radicle/ssh-private-key".path;
      format = "ssh";
      signByDefault = true;
    };

    # ... rest of existing config ...

    extraConfig = {
      # ... existing extraConfig ...

      # allowedSignersFile for verification
      gpg.ssh.allowedSignersFile = "${config.home.homeDirectory}/.config/git/allowed_signers";
      log.showSignature = false;
    };
  };

  # ... lazygit config ...

  # Generate allowedSignersFile from public key
  home.file."${config.xdg.configHome}/git/allowed_signers".text = ''
    ${flake.config.me.email} namespaces="git" ${flake.config.me.sshKey}
  '';

  # Declare SOPS secret for SSH private key
  sops.secrets."radicle/ssh-private-key" = {
    sopsFile = inputs.secrets.secrets.stibnite.radicle;  # Adjust for hostname
    mode = "0400";
  };
}
```

**Note**: We need to figure out how to access `inputs.secrets` in home-manager modules. This might require passing it through `extraSpecialArgs`.

**Testing**:
```bash
# After rebuild, test Git signing
git config --get user.signingkey
# Should show path to SOPS secret

# Test commit signing (in a test repo)
git commit --allow-empty -m "Test commit"
git log --show-signature -1
# Should show valid signature
```

**Commit point**: `feat(git): use SOPS-deployed unified SSH key for signing`

---

### Phase 7: Configure Jujutsu SSH signing

**Goal**: Migrate Jujutsu from GPG to SSH signing, reusing Git's configuration.

**File**: `modules/home/all/development/jujutsu.nix`

**Actions**:

1. Update Jujutsu configuration to use SSH signing:
```nix
{
  flake,
  config,
  lib,
  ...
}:
{
  programs.jujutsu = {
    enable = true;

    settings = {
      user = {
        name = flake.config.me.fullname;
        email = flake.config.me.email;
      };

      signing = {
        # Sign own commits, drop existing signatures
        behavior = "own";

        # Use SSH backend instead of GPG
        backend = "ssh";

        # Reuse Git's allowedSignersFile for verification
        backends.ssh.allowed-signers =
          config.programs.git.extraConfig.gpg.ssh.allowedSignersFile;

        # Use same SOPS-deployed key as Git
        key = config.sops.secrets."radicle/ssh-private-key".path;
      };

      ui = {
        editor = "nvim";
        color = "auto";
        diff-formatter = ":git";
        pager = "delta";

        # Show signature status in log output
        show-cryptographic-signatures = true;
      };

      git = {
        # Enable git colocate mode
        colocate = true;

        # Sign commits before pushing (revset syntax from upstream)
        # Options: true, false, "mine()", "~signed()", etc.
        sign-on-push = true;
      };

      # Snapshot settings
      snapshot = {
        max-new-file-size = "300KiB";
        auto-track = "all()";
      };
    };
  };
}
```

**Note**: The `sign-on-push` revset syntax (like `"mine()"`) requires upstream Jujutsu, which we added in Phase 4.

**Testing**:
```bash
# After rebuild, test Jujutsu signing
jj config list | grep -A 10 signing
# Should show backend = "ssh" and key path

# Test commit signing (in a jj repo)
jj new -m "Test commit"
jj log -r @ -T 'signature'
# Should show signature status
```

**Commit point**: `feat(jujutsu): migrate to SSH signing with unified key`

---

### Phase 8: Create Radicle client module

**Goal**: Set up Radicle client with systemd service, using the unified SSH key.

**File**: `modules/home/all/tools/radicle.nix` (new file)

**Actions**:

1. Create Radicle client configuration:
```nix
{
  config,
  lib,
  pkgs,
  flake,
  inputs,
  ...
}:
let
  # Helper script to open Radicle repos in web UI
  rad-browse = pkgs.writeShellScriptBin "rad-browse" ''
    rid="''${1:-$(rad .)}"
    # Use app.radicle.xyz as the public explorer
    xdg-open "https://app.radicle.xyz/nodes/seed.radicle.xyz/$rid"
  '';
in
{
  # Note: Your Radicle Node ID (NID) will be derived from the public key
  # ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+
  # This will be generated when you first run `rad auth`

  # Deploy public key
  home.file.".radicle/keys/radicle.pub".text =
    "${flake.config.me.sshKey} ${flake.config.me.email}";

  # Configure Radicle node
  home.file.".radicle/config.json".source = pkgs.writers.writeJSON "config.json" {
    # Web UI URL (using app.radicle.xyz as public explorer)
    publicExplorer = "https://app.radicle.xyz/nodes/seed.radicle.xyz/$rid";

    # Node alias
    node.alias = "cameronraysmith";

    # Preferred seeds (public Radicle seeds)
    preferredSeeds = [
      "z6MksmpU5b1dS7oaqF2bHXhQi1DWy2hB7Mh9CuN7y1DN6QSz@seed.radicle.xyz:8776"
      "z6MkrLMMsiPWUcNPHcRajuMi9mDfYckSoJyPwwnknocNYPm7@iris.radicle.xyz:8776"
      "z6Mkmqogy2qEM2ummccUthFEaaHvyYmYBYh3dbe9W4ebScxo@rosa.radicle.xyz:8776"
    ];
  };

  # Radicle node as systemd user service
  systemd.user.services.radicle-node = {
    Unit = {
      Description = "Radicle Node";
      After = [ "sops-nix.service" ];  # Wait for keys to be deployed
    };

    Install.WantedBy = [ "default.target" ];

    Service = {
      ExecStart = "${lib.getExe' pkgs.radicle-node "radicle-node"}";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # Install Radicle tools
  home.packages = lib.attrValues {
    inherit (pkgs)
      radicle-node      # Core node daemon
      ;
    inherit rad-browse;  # Helper to open repos in web UI
  };

  # Deploy private key via SOPS (same key as Git/Jujutsu)
  sops.secrets."radicle/ssh-private-key" = {
    sopsFile = inputs.secrets.secrets.stibnite.radicle;
    path = "${config.home.homeDirectory}/.radicle/keys/radicle";
    mode = "0400";
  };
}
```

2. Add to home-manager modules:

**File**: `modules/home/all/tools/default.nix`

Add `./radicle.nix` to the imports list.

**Testing**:
```bash
# After rebuild, check Radicle configuration
ls -la ~/.radicle/keys/
# Should show radicle (private key from SOPS) and radicle.pub

cat ~/.radicle/config.json
# Should show node alias and preferred seeds

# Check systemd service
systemctl --user status radicle-node
# Should be loaded (may not be running yet until we do `rad auth`)
```

**Commit point**: `feat(radicle): add client configuration with unified SSH key`

---

### Phase 9: Handle input propagation to home-manager

**Goal**: Ensure `inputs.secrets` is available in home-manager modules.

**Investigation needed**: Check how nixos-unified passes inputs to home-manager.

**Possible approaches**:

**Approach A**: If using home-manager as NixOS/nix-darwin module:
```nix
# In darwin configuration
home-manager.extraSpecialArgs = inputs // {
  inherit (inputs) secrets;
};
```

**Approach B**: If nixos-unified handles this automatically:
- Verify inputs are available in modules
- May just work out of the box

**Actions**:

1. Check one of your Darwin configurations (e.g., `configurations/darwin/stibnite.nix`)
2. Verify how home-manager is integrated
3. Add `extraSpecialArgs` if needed

**Testing**:
```bash
# Try to evaluate a home-manager module that uses inputs.secrets
nix eval .#darwinConfigurations.stibnite.config.home-manager.users.crs58.sops.secrets.\"radicle/ssh-private-key\".sopsFile --json
# Should show path to secrets file
```

**Commit point**: `refactor(home-manager): ensure secrets input available to modules`

---

### Phase 10: Rebuild and test complete setup

**Goal**: Deploy the complete unified cryptographic infrastructure.

**Actions**:

1. Rebuild Darwin configuration:
```bash
cd ~/projects/nix-workspace/nix-config
darwin-rebuild switch --flake .#stibnite
```

2. Test SOPS secret deployment:
```bash
# Check private key deployed
ls -la ~/.radicle/keys/radicle
# Should exist, mode 0400, owned by you

# Verify it's the correct key
ssh-keygen -y -f ~/.radicle/keys/radicle
# Should output: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+
```

3. Test Git signing:
```bash
# Create test commit in a git repo
cd /tmp
mkdir test-git-signing
cd test-git-signing
git init
git commit --allow-empty -m "Test commit signature"

# Verify signature
git log --show-signature -1
# Should show: Good "git" signature for cameron.ray.smith@gmail.com with ED25519 key SHA256:WbnjY1SC...
```

4. Test Jujutsu signing:
```bash
# Create test jj repo
cd /tmp
mkdir test-jj-signing
cd test-jj-signing
jj git init --colocate

# Create test commit
jj new -m "Test commit signature"

# Verify signature
jj log -r @ -T 'signature'
# Should show signature information
```

5. Initialize Radicle node:
```bash
# This will detect the existing key at ~/.radicle/keys/radicle
rad auth

# Check node identity
rad self
# Should show your Node ID (NID) derived from the public key

# Check connectivity to seeds
rad node status
rad node sessions
# Should show connections to seed.radicle.xyz, iris.radicle.xyz, rosa.radicle.xyz
```

6. Start Radicle systemd service:
```bash
systemctl --user start radicle-node
systemctl --user status radicle-node
# Should be active (running)

# Check logs
journalctl --user -u radicle-node -f
```

**Verification checklist**:
- [ ] SOPS deployed key to `~/.radicle/keys/radicle` with mode 0400
- [ ] Public key matches at `~/.radicle/keys/radicle.pub`
- [ ] Git commits are signed and verify correctly
- [ ] Jujutsu commits are signed and verify correctly
- [ ] Radicle node initialized with correct identity
- [ ] Radicle node connected to public seeds
- [ ] All three tools using the same unified SSH key

**Commit point**: `chore(system): rebuild and verify unified crypto infrastructure`

---

### Phase 11: Initialize secrets repository on Radicle

**Goal**: Push the secrets repository to Radicle for decentralized storage.

**Actions**:

1. Initialize secrets repo as Radicle project:
```bash
cd ~/projects/nix-workspace/nix-secrets

# Initialize as private Radicle repository
rad init \
  --name "nix-secrets" \
  --description "SOPS-encrypted NixOS/nix-darwin secrets" \
  --default-branch main \
  --private

# Note the Repository ID (RID) - looks like: rad:z2Wg1t47Ahi5sJqWKqPBVcf1DqB2A
rad .
```

2. Push to Radicle:
```bash
# Push to Radicle
git push rad main

# Announce to network (sync to public seeds)
rad sync --announce

# Verify synchronization
rad inspect
```

3. (Optional) Update flake input to use Radicle URL:

**File**: `nix-config/flake.nix`

```nix
# Change from local file to Radicle URL
# Before:
# secrets.url = "git+file:///Users/crs58/projects/nix-workspace/nix-secrets";

# After (using the RID from `rad .`):
secrets.url = "git+https://app.radicle.xyz/nodes/seed.radicle.xyz/<YOUR-RID>.git";
```

**Note**: For now, keeping the local `git+file://` URL is fine. You can switch to the Radicle URL later once you verify everything works.

4. Test cloning from Radicle (optional):
```bash
# Clone to a different location to test
cd /tmp
rad clone rad:<YOUR-RID>

# Or via HTTPS
git clone https://app.radicle.xyz/nodes/seed.radicle.xyz/<YOUR-RID>.git
```

**Commit point**: `feat(secrets): publish to Radicle network`

---

## Post-implementation tasks

### Documentation

- [ ] Update main README.md with unified crypto infrastructure overview
- [ ] Document key rotation procedure
- [ ] Document disaster recovery (Age key backup, SSH key backup)

### Testing

- [ ] Test on other hosts (blackphos, orb-nixos)
- [ ] Verify signature verification across different machines
- [ ] Test Radicle synchronization across nodes

### Optional enhancements

- [ ] Add upstream Jujutsu custom templates for signature display
- [ ] Create helper scripts (e.g., `jr` for Jujutsu reference)
- [ ] Set up Radicle patches workflow
- [ ] Implement revset-based signing (`git.sign-on-push = "mine()"`)

### Migration

- [ ] Migrate additional secrets from main repo to secrets repo
- [ ] Remove secrets from main repo (keep only encrypted in secrets repo)
- [ ] Update all secret references to use new structure

## Troubleshooting

### SOPS secret not deploying

**Symptom**: `~/.radicle/keys/radicle` doesn't exist after rebuild

**Check**:
```bash
# Verify SOPS service ran
systemctl --user status sops-nix.service

# Check Age key exists
cat ~/.config/sops/age/keys.txt

# Test manual decryption
sops -d ~/projects/nix-workspace/nix-secrets/hosts/stibnite/secrets/radicle.yaml
```

**Fix**:
- Ensure Age key matches public key in `.sops.yaml`
- Check sopsFile path is correct in module
- Verify secrets flake input is up to date

### Git/Jujutsu signatures show as "unknown"

**Symptom**: Signatures don't verify

**Check**:
```bash
# Verify allowedSignersFile content
cat ~/.config/git/allowed_signers
# Should show: cameron.ray.smith@gmail.com namespaces="git" ssh-ed25519 AAAA...

# Verify public key matches
cat ~/.radicle/keys/radicle.pub
ssh-keygen -y -f ~/.radicle/keys/radicle
```

**Fix**:
- Ensure public key in `config.nix` matches actual key
- Verify allowedSignersFile format is correct
- Check email matches in user.email and allowedSignersFile

### Radicle node won't start

**Symptom**: `systemd.user.services.radicle-node` fails

**Check**:
```bash
systemctl --user status radicle-node
journalctl --user -u radicle-node -n 50
```

**Common issues**:
- Private key not deployed: Check `~/.radicle/keys/radicle` exists
- Permission denied: Ensure key is mode 0400
- Port conflict: Check if port 8776 is in use

### Input `secrets` not available in modules

**Symptom**: Error about `inputs.secrets` not defined

**Check**: How nixos-unified passes inputs to home-manager

**Fix**: Add to `extraSpecialArgs` in Darwin/NixOS configuration:
```nix
home-manager.extraSpecialArgs = inputs;
```

## Security considerations

### Key backup strategy

**Critical items to backup**:
1. Age private key: `~/.config/sops/age/keys.txt`
2. SSH private key: `~/.ssh/id_ed25519` (source, before SOPS encryption)
3. Secrets repository: `~/projects/nix-workspace/nix-secrets/` (includes encrypted keys)

**Backup locations**:
- Secure offline storage (encrypted USB drive)
- Bitwarden (already has `sops-admin-user-ssh`)
- Paper backup of Age key (for disaster recovery)

### Key rotation procedure

If the unified SSH key is compromised:

1. Generate new SSH key pair
2. Update public key in `config.nix`
3. Encrypt new private key with SOPS
4. Update secrets repository
5. Rebuild all systems
6. Update Git allowedSignersFile
7. Re-sign important commits if needed

**Note**: Old commits remain signed with old key (historical validity).

### Access control

**Current model**:
- Secrets repository: SOPS-encrypted only (public Radicle repo is OK)
- Private key never on disk in plaintext (only SOPS-encrypted)
- SOPS deploys to tmpfs at runtime (cleared on reboot)
- Age key required to decrypt

**Future enhancements**:
- Self-hosted Radicle seed for private repository access control
- Hardware security key (YubiKey) for SSH key storage
- Regular key rotation schedule

## References

### Documentation sources

- [defelo-nixos README](~/projects/nix-workspace/defelo-nixos/docs/notes/README.md)
- [Jujutsu SSH signing guide](~/projects/nix-workspace/defelo-nixos/docs/notes/configuration/jujutsu-ssh-signing.md)
- [Radicle secrets management guide](~/projects/nix-workspace/defelo-nixos/docs/notes/infrastructure/radicle-secrets-management.md)

### Upstream documentation

- [Radicle Guides](https://radicle.xyz/guides)
- [Jujutsu Documentation](https://martinvonz.github.io/jj/)
- [SOPS-nix](https://github.com/Mic92/sops-nix)
- [Age Encryption](https://github.com/FiloSottile/age)
- [Git SSH Signing](https://git-scm.com/docs/git-config#Documentation/git-config.txt-gpgsshallowedSignersFile)

### Related repositories

- [defelo-nixos](https://github.com/defelo/nixos) - Original implementation
- [nixos-unified](https://github.com/srid/nixos-unified) - Flake architecture pattern

## Implementation tracking

**Started**: 2025-10-15
**Status**: Planning complete, ready to begin implementation
**Current phase**: Phase 1 - Create secrets repository structure
**Target completion**: TBD

### Completed phases

- [x] Phase 0: Planning and documentation

### In progress

- [ ] Phase 1: Create secrets repository structure

### Pending

- [ ] Phase 2: Encrypt unified SSH key with SOPS
- [ ] Phase 3: Add secrets as flake input
- [ ] Phase 4: Add upstream Jujutsu flake
- [ ] Phase 5: Update SOPS home-manager configuration
- [ ] Phase 6: Configure Git SSH signing with unified key
- [ ] Phase 7: Configure Jujutsu SSH signing
- [ ] Phase 8: Create Radicle client module
- [ ] Phase 9: Handle input propagation to home-manager
- [ ] Phase 10: Rebuild and test complete setup
- [ ] Phase 11: Initialize secrets repository on Radicle
