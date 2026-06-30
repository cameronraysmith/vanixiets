## ADDED Requirements

### Requirement: First-party packages declare nix-pinned apm dependencies on upstream plugins

First-party apm packages SHALL be permitted to declare apm dependencies on upstream plugins, which MUST be pinned by nix `fetchFromGitHub` (rev + hash in `flake.lock`) and composed offline at the ROOT consumer manifest, with `apm.lock` recording per-file content hashes.
Only the root manifest MAY declare local-path dependencies.

#### Scenario: offline root-manifest composition

- **WHEN** the compose derivation generates a root consumer `apm.yml` whose `dependencies.apm` lists the first-party package dirs and the upstream store paths as local absolute paths, then runs `apm install --root $out`
- **THEN** the local-path dependencies skip apm's git-fetch code path and the dependency graph resolves offline at the root, because a remotely-fetched parent's local-path dependency would be rejected

#### Scenario: apm.lock records per-file content hashes

- **WHEN** the compose completes
- **THEN** `apm.lock` is a flat list (transitive deps recorded via `discovered_via`) in which upstream deps lock `resolved_commit` plus per-file content hashes and local deps lock content hashes only, while `flake.lock` owns the upstream version pins

---

### Requirement: Upstream plugins consumed without forking and extended additively

superpowers SHALL be consumable as a direct dependency without a fork (auto-detected as a `MARKETPLACE_PLUGIN` via its `.claude-plugin/`), and "extension" of an upstream plugin MUST be additive co-shipping rather than patch/override, since apm provides no patch or override mechanism.
A dependency source that lacks any packaging signal MUST gain one before it can be consumed.

#### Scenario: superpowers consumed as a MARKETPLACE_PLUGIN without a fork

- **WHEN** a first-party package declares a dependency on `obra/superpowers`
- **THEN** apm auto-detects it as a `MARKETPLACE_PLUGIN` and composes its skills with no fork required

#### Scenario: superpowers consumed as a regular remote dependency resolved offline; bridge stays an OpenSpec schema

- **WHEN** `planning-and-development` declares `obra/superpowers` as a regular (walked) remote apm dependency pinned to its full 40-char SHA, and the nix compose pre-seeds apm's git checkout cache from the flake-pinned `fetchFromGitHub` tree before `apm install`
- **THEN** apm resolves the remote ref from the warmed cache with zero network and records a remote-style `resolved_commit` lock, while the `openspec-schemas-superpowers-bridge` is NOT forked or given an apm packaging signal — it stays an OpenSpec schema delivered by its own home-manager module

#### Scenario: additive co-ship with no patch or override

- **WHEN** first-party skills are shipped alongside an upstream plugin's skills and a same-name collision occurs
- **THEN** the collision is resolved by precedence or `--force`, not by any declarative patch or override layer
