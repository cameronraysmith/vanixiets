## Purpose

The machine-side contract between this repository and a Claude Code cloud environment's setup step: which Nix store path the setup step names, where it fetches it from, and the platform limits the generated script stays within.
Trust boundary: these properties guarantee only that the setup step fetches the named store path from the two binary caches, accepting it only under their signing keys, and runs that path's activation.
They do not guarantee that the caches still hold the path, that the platform runs the setup step, or that the activation succeeds; the `claude-sandbox-bootstrap` capability states the behaviour, and the world assumptions it rests on state the platform facts.

## ADDED Requirements

### Requirement: The setup step names the activation package by store path

The setup step SHALL name the `claude-sandbox@x86_64-linux` home-manager activation package by its Nix store path and fetch that path with `nix-store --realise` from `cache.scientistexperience.net` and `cache.nixos.org`, trusting only their public keys.
It SHALL then run the path's `activate` as root, and SHALL NOT evaluate a flake.

#### Scenario: The generated script is read

- **WHEN** `nix run .#claude-sandbox-setup-script` prints the setup script for a revision
- **THEN** it assigns `P` the store path of that revision's activation package, realises `P` with only those two substituters and their keys, and runs `"$P/activate"`, with no `nix eval`, `nix build` or flake reference

### Requirement: The named store path is the CI check's output

The store path the setup step names SHALL be the output of `checks.x86_64-linux.home-manager-claude-sandbox` at the revision the script's first comment line records, so that the build service builds it and publishes it to `cache.scientistexperience.net`.

#### Scenario: The script's store path is checked

- **WHEN** the `claude-sandbox-setup-script` check is built for a revision
- **THEN** it fails unless the script's `P` equals that revision's `home-manager-claude-sandbox` output path

### Requirement: The setup script stays within the platform's limits

The generated setup script SHALL have at most 100 lines of at most 200 bytes each once its revision and date are filled in, and its last line SHALL be `exit 0`.

#### Scenario: A script over the limits

- **WHEN** the template would produce a line over 200 bytes once filled, more than 100 lines, or a last line other than `exit 0`
- **THEN** the `claude-sandbox-setup-script` check fails evaluation with its own message
