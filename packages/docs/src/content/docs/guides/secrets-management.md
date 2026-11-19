---
title: Secrets management
description: The two sops trees, the keys that read them, and the procedures that maintain them
sidebar:
  order: 7
---

This guide describes how secrets are arranged in this repository and gives the procedures that maintain them.
For a learning-oriented walkthrough, see the [Secrets Setup Tutorial](/tutorials/secrets-setup/); for how clan composes the machine side, see [Clan Integration](/concepts/clan-integration#secrets-management).

## Architecture

vanixiets keeps secrets in two sops trees that share one operator identity.

**Clan's store** (`sops/` and `vars/`) holds admin keys, machine keys and generated secrets.

- **Admin keys:** `sops/users/{cameron,crs58}/key.json` are both the `ssh-to-age` image of crs58's login key (the first `sshKeys` entry in `modules/home/users/crs58/meta.nix`). The same key is the `.sops.yaml` anchor `&admin-user`, the operator identity.
- **Machine keys:** `sops/machines/<machine>/key.json` holds each machine's public key, for the six NixOS hosts and for stibnite, rosegold, argentum and gcp-vm. Each private key is in `sops/secrets/<machine>-age.key/secret`, encrypted to the admin user, which is the recovery chain for machine keys.
- **Generated secrets:** `clan vars generate` writes them under `vars/per-machine/<machine>/` and `vars/shared/`, encrypted to the machine and its users.
- **On the host:** sops-nix reads the machine key from `/var/lib/sops-nix/key.txt`. Only `clan machines update`, `clan machines install` and `clan vars upload <machine>` write that file; a local activation never does. Darwin hosts are activated locally with `just activate`, so each needs `clan vars upload <host>` once, and the activation guard enforces it (see [Installing a darwin host's machine key](#installing-a-darwin-hosts-machine-key)).

**The legacy tree** (`.sops.yaml` and `secrets/`) carries the secrets that are not clan vars.

- **Home-manager user secrets:** `secrets/home-manager/users/<user>/secrets.yaml`, set as `sops.defaultSopsFile` in `modules/home/users/<user>/default.nix`. Each home decrypts them with `~/.config/sops/age/keys.txt` (`modules/home/base/sops.nix`).
- **Bridge keys:** on NixOS, `hm-sops-bridge` delivers a user's age key from `secrets/bridge/<identity>-age-key.enc`, which is encrypted to the NixOS machine keys, so NixOS homes need no hand-placed `keys.txt`.
- **Operator credentials:** `secrets/shared.yaml` (forge, DNS and cache credentials), read by `just` recipes. Only the operator identity and the offline recovery key can read it.
- **Cluster secrets:** `secrets/clusters/local/`, also read in CI through the `SOPS_AGE_KEY` secret (the `&ci` key).
- **The Devin `ubuntu` profile**, whose key is seeded from `SOPS_AGE_KEY`.

**Bitwarden** holds the SSH key pairs (items of type SSH key named `sops-<identity>-user-ssh`) whose `ssh-to-age` images are the legacy tree's user recipients. It is the source for a workstation's `keys.txt` entry and for bridge keys. It holds no clan machine key. The `&admin` key is an offline recovery key, not in Bitwarden.

The flake check `checks.x86_64-linux.sops-correspondence` keeps the public keys in agreement: user anchors and clan user keys against users' login keys, machine anchors against `sops/machines`, the blackphos host-key anchor against its pinned host key, and every file's recipients against its `.sops.yaml` rule. NixOS hosts also fail evaluation when a bridge key they use is not encrypted to them.

## Clan vars

Clan vars holds machine and generated secrets: SSH host keys, zerotier identities, service credentials and certificates.

```bash
# Generate any missing vars for a machine
clan vars generate <machine>

# Show a public value
clan vars get <machine> openssh/ssh.id_ed25519.pub

# Check that every var is encrypted to its current recipients
clan vars check <machine>

# Deploy a NixOS machine; uploads its machine key and vars, then activates
clan machines update <machine>
```

Generated secrets are stored encrypted under `vars/`:

```
vars/
├── per-machine/
│   └── cinnabar/
│       ├── openssh/
│       │   ├── ssh.id_ed25519/secret      # private key (encrypted)
│       │   └── ssh.id_ed25519.pub/value   # public key
│       └── zerotier/…
└── shared/…
```

On the host, sops-nix installs them under `/run/secrets/` during activation.

## Installing a darwin host's machine key

A darwin host whose machine key exists in the repository (`sops/secrets/<host>-age.key`) needs `/var/lib/sops-nix/key.txt` before its first activation and after any machine-key rotation.
Without it, sops-nix cannot install the host's secrets and activation fails.

Install it from a machine that holds the operator identity:

```bash
clan vars upload <host>
```

`just activate` and `just activate-darwin <host>` check the key first.
When the file is missing or holds a different key, they stop before activating and print the expected and found public keys with this command; with `--dry` they print the same message and continue.
The expected keys are in `flake.lib.darwinMachineKeys`.

## Workstation age key

A person's workstation key for the legacy tree is derived from their SSH key in Bitwarden, so it is the same on every workstation and matches the anchor the correspondence check verifies.
There is no other convention: never generate an unrelated age key for a person.

```bash
export BW_SESSION=$(bw unlock --raw)
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

The procedure only appends: `keys.txt` may hold identities for other repositories, so never overwrite it.
`bw` is the nixpkgs Bitwarden CLI from the home profile.
Check the result: `age-keygen -y ~/.config/sops/age/keys.txt` lists the public key that `.sops.yaml` names for you.

## Working with legacy secrets

```bash
# Edit a user's home secrets (decrypts, opens $EDITOR, re-encrypts)
sops secrets/home-manager/users/<user>/secrets.yaml

# Check decryption without printing values
sops -d secrets/home-manager/users/<user>/secrets.yaml >/dev/null && echo ok

# List key names without decrypting
yq 'del(.sops) | keys' secrets/home-manager/users/<user>/secrets.yaml
```

Reference a new secret from the user's home module; `defaultSopsFile` already points at the file:

```nix
# modules/home/users/<user>/default.nix
sops = {
  defaultSopsFile = ../../../../secrets/home-manager/users/<user>/secrets.yaml;
  secrets.my-new-secret = { };
};
# elsewhere: config.sops.secrets.my-new-secret.path
```

Name the file with a path literal, never `inputs.self + "/secrets/..."`.
A path literal copies only that file into the store, while `inputs.self` makes the secrets manifest depend on the whole repository, so every commit would change every host that carries it.
An assertion on every host and home (`flake.lib.sourceContextObligations`) fails evaluation, naming the option, when a sops file or a home-manager file source references the repository source that way.

Deploy with `just activate` (darwin, or a standalone home) or `clan machines update <machine>` (NixOS).

## Changing recipients and rotating keys

No tool writes `.sops.yaml` or a host key; these are procedures, and the correspondence check confirms the result.

**A machine key:** rotate it with clan (`clan vars generate`, `clan vars fix`, `clan secrets key update`), deploy with `clan machines update <machine>` (NixOS) or `clan vars upload <host>` then `just activate` (darwin), and update the machine's `.sops.yaml` anchor if it has one.

**A recipient of the legacy tree** (adding, replacing or removing a person, machine or host key):

1. Edit the anchor or the rule in `.sops.yaml`.
2. Re-apply the rules: `just update-all-keys`.
3. For each file that lost a recipient, renew its data key: `sops rotate --in-place <file>`. `updatekeys` keeps the old data key, so without this a removed recipient could read values written later. Earlier commits stay readable by their recipients of the time; rotate the credential values themselves if that matters.
4. If a bridge identity is affected, re-provision it: `just provision-bridge-key <identity> [bitwarden-item]`. It encrypts the derived key straight from a pipe; no plaintext touches disk.
5. Run `nix build .#checks.x86_64-linux.sops-correspondence` and deploy the hosts that read the changed files.

A new NixOS machine that uses the bridge needs its anchor in the `secrets/bridge/` rule and `just update-all-keys` before its configuration evaluates.

## Troubleshooting

**Activation stops with "Machine key check failed":** run `clan vars upload <host>`, then activate again.

**`sops -d` fails with "could not decrypt data key":** your key is not a recipient of that file. Compare `age-keygen -y ~/.config/sops/age/keys.txt` with the anchors in `.sops.yaml` and the file's `sops.age[].recipient` list; if the anchor is right but the file is stale, run `just update-all-keys`.

**"no key could be found":** `~/.config/sops/age/keys.txt` is missing; follow [Workstation age key](#workstation-age-key). Note that sops also tries `~/.ssh/id_ed25519` as an age identity.

**A NixOS host fails evaluation naming a bridge file:** add the host's anchor to the `secrets/bridge/` rule and run `just update-all-keys`.

**Secrets missing on a NixOS host after deploy:** the fleet decrypts system secrets in the `setupSecrets` activation script, so read the `clan machines update` output for `sops-install-secrets` errors and check `ls -la /run/secrets/`; for a home, check `systemctl --user status sops-nix`.

## See also

- [Clan Integration](/concepts/clan-integration) - how clan composes machines and their secrets
- [Host Onboarding](/guides/host-onboarding) - platform-specific setup steps
- [Home-Manager Onboarding](/guides/home-manager-onboarding) - user module patterns

## External references

- [sops](https://github.com/getsops/sops) and its [key management](https://getsops.io/docs/usage/key-management/) notes
- [age](https://age-encryption.org/)
- [ssh-to-age](https://github.com/Mic92/ssh-to-age)
- [sops-nix](https://github.com/Mic92/sops-nix)
- [clan vars](https://clan.lol/)
