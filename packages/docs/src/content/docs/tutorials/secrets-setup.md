---
title: "Secrets Setup"
description: "Learn how secrets management works in this infrastructure, from age key derivation to encrypted secret deployment."
sidebar:
  order: 3
---

This tutorial teaches you how secrets management works in this infrastructure.
You'll understand the two places secrets live, derive your age key from your SSH key in Bitwarden, and set up user secrets that deploy with your configuration.

## What you will learn

By the end of this tutorial, you will understand:

- How clan vars and the legacy sops tree divide the fleet's secrets
- How age encryption provides the foundation for both
- How your workstation age key is derived from your Bitwarden SSH key
- How sops-nix delivers your secrets during home-manager activation
- How the repository checks that the public keys it names stay in agreement

## Prerequisites

Before starting, you should have:

- Completed the [Bootstrap to Activation Tutorial](/tutorials/bootstrap-to-activation)
- Your machine activated and working
- An SSH key item in Bitwarden (item type "SSH key"), named `sops-<identity>-user-ssh`
- The Bitwarden CLI (`bw`, from your home profile)

## Estimated time

30-45 minutes for initial setup.
Adding new secrets takes 5-10 minutes once you understand the workflow.

## Understanding secrets architecture

### Two trees, one operator identity

**Clan vars** holds machine and generated secrets on every host, NixOS and darwin alike: SSH host keys, zerotier identities, service credentials and certificates.
Clan generates them (`clan vars generate`) and encrypts them to each machine's own age key, its *machine key*.
A machine reads them with that key from `/var/lib/sops-nix/key.txt`, which clan installs: `clan machines update` does it for NixOS hosts, and darwin hosts, which are activated locally with `just activate`, need `clan vars upload <host>` once.

**The legacy sops tree** (`.sops.yaml` and `secrets/`) holds secrets people write by hand, chiefly each user's home-manager secrets in `secrets/home-manager/users/<user>/secrets.yaml`.
Your home decrypts them during home-manager activation with your *personal* age key in `~/.config/sops/age/keys.txt`.
On NixOS, the `hm-sops-bridge` module delivers that personal key from an encrypted bridge file instead, so NixOS homes need no hand-placed key.

The operator identity (`&admin-user` in `.sops.yaml`) can read every file in both trees, and an offline recovery key (`&admin`) can read every legacy file.

### Current implementation status

| Aspect | Darwin (macOS) | NixOS |
|--------|----------------|-------|
| Clan vars | Active; machine key installed by `clan vars upload <host>` | Active; machine key installed by `clan machines update` |
| User secrets | sops-nix, personal key in `~/.config/sops/age/keys.txt` | sops-nix, personal key delivered by `hm-sops-bridge` |
| Deployment | `just activate` (checks the machine key first) | `clan machines update <machine>` |

For the complete architecture reference, see [Clan Integration: Secrets Management](/concepts/clan-integration#secrets-management) and the [Secrets Management Guide](/guides/secrets-management).

## Step 1: Understand age encryption

[Age](https://age-encryption.org/) uses a single key pair: a private key for decryption and a public key for encryption.

In this infrastructure:
- Your **age private key** lives at `~/.config/sops/age/keys.txt` and decrypts your secrets
- Your **age public key** is an anchor in `.sops.yaml`, so sops encrypts your files to it

### Why derive from SSH keys?

Your age key is not generated separately; it is computed from your SSH key with `ssh-to-age`.
The same SSH key always yields the same age key, so:

- every workstation you use ends up with the same personal key;
- nothing new needs backing up, because Bitwarden already holds the SSH key;
- the repository can check, from public data alone, that your `.sops.yaml` anchor is the image of the login key in your `modules/home/users/<user>/meta.nix`.

## Step 2: Derive your age key from Bitwarden

```bash
# Log in once, then unlock for this shell
bw login            # only if `bw status` says unauthenticated
export BW_SESSION=$(bw unlock --raw)

# Confirm the item and print its age public key
bw get item sops-<identity>-user-ssh | jq -r .sshKey.publicKey | ssh-to-age
```

Now append the private key to your key file, unless it is already there.
The key goes straight from Bitwarden through `ssh-to-age` into the file; it is never written anywhere else.

```bash
mkdir -p ~/.config/sops/age && chmod 700 ~/.config/sops/age
pub=$(bw get item sops-<identity>-user-ssh | jq -r .sshKey.publicKey | ssh-to-age)
if [ -f ~/.config/sops/age/keys.txt ] && age-keygen -y ~/.config/sops/age/keys.txt | grep -qx "$pub"; then
  echo "already present"
else
  ( umask 077
    bw get item sops-<identity>-user-ssh | jq -r .sshKey.privateKey | ssh-to-age -private-key \
      >> ~/.config/sops/age/keys.txt )
fi
bw lock
```

Always append: `keys.txt` may hold identities for other repositories.

Verify:

```bash
age-keygen -y ~/.config/sops/age/keys.txt   # lists your public key among any others
ls -la ~/.config/sops/age/keys.txt          # -rw------- (600)
```

## Step 3: Add your key to .sops.yaml

`.sops.yaml` names each public key once, as a YAML anchor, and lists for each path which keys can read it.
A new user's key and rule look like this:

```yaml
keys:
  - &admin age1…            # offline recovery key
  - &admin-user age1…       # the operator identity
  - &yourname-user age1…    # your key from Step 2

creation_rules:
  - path_regex: secrets/home-manager/users/yourname/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *admin-user
        - *yourname-user
```

Every rule lists `*admin` (recovery) and `*admin-user` (so the operator can maintain the file).
The correspondence check classifies every anchor, so a new user anchor also needs an entry in the user table of `modules/checks/sops-correspondence.nix`, mapping it to your flake user; the check then confirms it is the `ssh-to-age` image of the first key in your `meta.nix` `sshKeys`.

```bash
nix build .#checks.x86_64-linux.sops-correspondence
```

## Step 4: Create your first secret

```bash
mkdir -p secrets/home-manager/users/yourname
sops secrets/home-manager/users/yourname/secrets.yaml
```

This opens your `$EDITOR` with a new file.
Add secrets in YAML format, save and close; sops encrypts the file to the keys of its matching rule.

```yaml
github-token: <value>
some-api-key: <value>
```

Check it without printing values:

```bash
yq 'del(.sops) | keys' secrets/home-manager/users/yourname/secrets.yaml   # key names only
sops -d secrets/home-manager/users/yourname/secrets.yaml >/dev/null && echo "decrypts"
```

## Step 5: Integrate secrets with home-manager

In your user module (`modules/home/users/yourname/default.nix`) point sops-nix at the file and declare the secrets; the key file location is set for every home in `modules/home/base/sops.nix`:

```nix
sops = {
  defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/yourname/secrets.yaml";
  secrets = {
    github-token = { };
    some-api-key = { };
  };
};
```

Reference a secret by its decrypted path, `config.sops.secrets.github-token.path`, never by its value.

### Activate and verify

```bash
just activate
ls -la ~/.config/sops-nix/secrets/   # one file per secret, mode 0400
```

If you work on a NixOS host, ask the operator to provision your bridge key (`just provision-bridge-key <identity>`) and add you to `hm-sops-bridge` for that host; the host's evaluation fails until the bridge file is encrypted to its machine key.

## What you've learned

- **Clan vars** holds machine and generated secrets on every host, read with the machine key that clan installs
- **The legacy tree** holds hand-written secrets, read with personal keys
- **Your personal key** is derived from your Bitwarden SSH key, so it is the same everywhere
- **The correspondence check** confirms every public key the repository names, without Bitwarden

## Next steps

1. **Add more secrets** as needed; see [Working with legacy secrets](/guides/secrets-management#working-with-legacy-secrets).
2. **Continue to platform-specific tutorials**:
   - [Darwin Deployment Tutorial](/tutorials/darwin-deployment) for macOS specifics
   - [NixOS Deployment Tutorial](/tutorials/nixos-deployment) for server deployment
3. **Review operational procedures** in the [Secrets Management Guide](/guides/secrets-management) for rotation and troubleshooting.

## Troubleshooting

### "no key could be found"

`~/.config/sops/age/keys.txt` is missing or holds no matching key; repeat Step 2.

### "could not decrypt data key"

Your key is not a recipient of the file:

```bash
age-keygen -y ~/.config/sops/age/keys.txt                         # your public keys
yq '.sops.age[].recipient' secrets/home-manager/users/yourname/secrets.yaml   # the file's recipients
```

If your anchor is right but the file predates it, ask the operator to run `just update-all-keys`.

### Secrets not appearing after activation

```bash
nix eval '.#homeConfigurations."yourname@aarch64-darwin".config.sops.secrets' --apply builtins.attrNames
```

On darwin, also check `launchctl list | grep sops-nix`; see [Troubleshooting](/guides/secrets-management#troubleshooting) for more.
