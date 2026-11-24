---
description: vanixiets repository overview — what it manages, its layout, and its build/check/test entry points.
---

## Repository overview

vanixiets manages nix-darwin workstations, a bare-metal NixOS laptop, and NixOS cloud servers with [clan](https://clan.lol), using a deferred module composition architecture.
Clan handles multi-machine provisioning and declarative configuration across nix-darwin, NixOS, and home-manager, with sops-nix for secrets and ZeroTier for the private mesh network.
The flake is built with flake-parts and import-tree, so every module under `modules/` is discovered from the filesystem rather than listed in an explicit import set; adding a file is how a module is registered.

The repository also publishes an [apm](https://github.com/microsoft/apm) marketplace of agent-skill plugins, which is independent of the Nix configurations and installable on its own.

## Repository layout

`machines/` holds one directory per NixOS machine.
`modules/` holds the flake-parts modules import-tree discovers, subdivided by concern: `clan/` for inventory and clan services, `darwin/` and `nixos/` for per-platform system configuration, `home/` for home-manager, `terranix/` for cloud resource declarations, `checks/` for flake checks, and `containers/`, `kubernetes.nix`, and `nixidy.nix` for the container and Kubernetes layers.
`pkgs/by-name/` holds first-party packages that are built, several of which override versions supplied by flake inputs; `pkgs/disabled/` holds derivations parked out of the build, including the beads issue-tracker family, which this repository no longer uses.
`lib/`, `scripts/`, `secrets/`, `sops/`, `vars/`, and `terraform/` hold shared helpers, operational scripts, encrypted material, and generated Terraform state respectively.

Documentation lives in two places.
`packages/docs/` is an Astro Starlight site published from this repository, and architecture decision records live under `packages/docs/src/content/docs/development/architecture/adrs/`.
`docs/` holds the working notes and reference material that feed it, including `docs/notes/development/kubernetes/` for the Kubernetes platform design and its own ADR series.

`openspec/` holds change proposals and their specs; `openspec/changes/archive/` is deliberately tracked, which is why the `archive/` ignore rule in `.gitignore` is anchored to the repository root.

## Building, checking, and testing

`just` is the task entry point; `just help` lists the recipes.

`just check` runs `nix flake check` over everything.
`just check-fast` runs the same check set through `nix-fast-build` and is the normal local loop; its positional parameters are `nom push system remote`, and a non-native `system` evaluates and builds on `remote`, `magnetite` by default or `pyrite`, e.g. `just check-fast auto off x86_64-linux`.
Either way it evaluates with the evaluating host's own `nix-eval-jobs`, iets or stock by that host's memory class (see §Evaluators).
On the NixOS hosts both evaluator names take a host-wide evaluation lock, so a remote run may print `nix-eval-jobs: waiting for the host evaluation lock held by ...` every 30 seconds while nixbot or another user evaluates; that is queueing, not a hang.
`just test-quick` builds a named subset of checks directly for fast feedback.
`just lint` runs the `prek` hook set, which is treefmt plus a staged-diff gitleaks scan; the hooks are declared in `modules/formatting.nix` rather than in a `.pre-commit-config.yaml`.

Individual checks are addressable, so the narrowest useful selection is usually a direct build of the one that covers the change, for example `nix build .#checks.<system>.gitleaks`.
`checks.gitleaks` scans the whole flake source tree with `gitleaks detect --no-git`, so it covers any newly committed file, not only staged diffs.
Check definitions live under `modules/checks/`.
Many, particularly those built through `mkStructuralCheck` in `validation.nix`, carry a `passthru.meta.description` naming what they validate, but this is not universal — files such as `package-tests.nix`, `aeneas-toolchain.nix`, and `home.nix` define checks without that field, so consult the file directly rather than assuming the annotation is present.

A check is not free once written: nixbot evaluates every check attribute on every system on every pull request, whether or not the derivation is cached, so evaluation rather than building is this repository's binding CI cost.
Two invariants carry most of that cost and are easy to violate without noticing.
A check module's attribute names must derive only from static data — literals, the `system` string, clan inventory metadata, flake-level `lib` — and never from an evaluated NixOS, nix-darwin, or home-manager configuration or an instantiated `pkgs`, because attribute sets are strict in their keys and every evaluator worker pays for the whole key set before it can select one check.
A check whose derivation would be identical on every system belongs to exactly one of them, while a check whose derivation genuinely differs per platform must stay per system.
Before adding, removing, or restructuring a check, read the `preferences-nix-checks-architecture` skill, whose `references/evaluation-cost.md` carries the measurement protocol and the derivation-path oracle that any evaluation refactor must pass, and whose `references/check-vacuity.md` carries the patterns that decide whether a proposed check can fail at all.

VM and container tests live under `vmTests`, not `checks`, so nixbot never runs them and they are not part of pull-request coverage.
QEMU tests need `kvm`, which only Pyrite advertises, and systemd-nspawn container tests run on Pyrite or Magnetite; a container test started on Pyrite must pass `--builders ''`, or Pyrite's daemon dispatches it to Magnetite (`modules/README.md` §On-demand VM tests).
The form that keeps a runtime test on Pyrite is `ssh pyrite.vanixiets.internal nix build --builders '' '<source>#vmTests.x86_64-linux.<name>'` against a source already on Pyrite, a checkout there or the store path `nix flake archive --to ssh-ng://pyrite.vanixiets.internal` prints.
`nix build --store ssh-ng://pyrite… --builders ''` from another host does not: the flag does not reach Pyrite's daemon, which on 2026-11-24 handed such a `fleet-ingress` build to Magnetite (`magnetite: building …` in `logs/tsc-1-fleet-ingress-20261124-111732.log`).

The test size classes of the fleet-wide agent context (§Test sizes) map onto this repository's runners as follows.
nixbot's pull-request gate builds `checks.x86_64-linux` on Magnetite's store and `checks.aarch64-darwin` best-effort; small and medium checks belong there, and a large check belongs there only with its reason recorded beside its definition.
nixbot records each attribute's build in the `build_attributes` table of its PostgreSQL database on Magnetite, from builder-slot acquisition to completion, and the dev-loop collection copies those rows into the telemetry store's `devloop` database; an uncached run there is the measurement a check's class rests on.
VM and container tests run on Pyrite, a container test with `--builders ''`, and their driver prints `test script finished in <seconds>`, to which a cold run adds the driver and node builds.
`fleet-ingress` is medium (its script measured 252 to 281 s on Pyrite on 2026-11-24) and is the test to run for a change to what the collectors filter, route or store.
An enormous test never gates a pull request: `fleet-ingress-outage` (about 28 minutes of script on Pyrite, the outage, queue, crash-loop, long-run and Langfuse-timer cases split out of `fleet-ingress`) and `devloop-ingest` (about 28 minutes) belong on a weekly schedule, which does not exist yet, so today every run of them is on demand and announced first.
No check or VM test declares its class in code, and nothing fails a build for exceeding one.
The `preferences-nix-checks-architecture` skill's `references/test-sizes.md` covers assigning a class, measuring one run, and what to do when a check outgrows its class.

`preferences-nix-development` governs the Nix code itself, including the rule that this repository instantiates one nixpkgs per system and the hard constraint that an upstream flake input's nixpkgs is never redirected with `follows`, because that changes the input's store paths and forfeits its binary cache.

Documentation has its own lane under `packages/docs`: `just docs-lint`, `just docs-check`, and the `just docs-test-*` recipes.

## Version control

The default branch is `main`.
Landing runs through gitea-mq at https://mq.scientistexperience.net, App id 4875422, installed on this repository with `batchMax = 20` and `skipQueueIfUpToDate = true` (`modules/nixos/gitea-mq.nix`).
Two active default-branch rulesets gate it: ours requires `nixbot/nix-eval`, `nixbot/nix-build`, and `nixbot/effects`; the App's requires `gitea-mq`, which it posts only after enqueue.
`.github/mergify.yml` retains pull-request rules only (self-assign, label-triggered approval) and no queue rules; Mergify no longer lands anything.
Approving a PR does not land it: no ruleset requires review, and the enqueue signal is the merge authorization.
For an ordinary trunk-based PR, enqueue with `gh pr merge <PR> --auto --rebase`; for a registered stack, label the topmost intended PR `merge-queue` and never enable auto-merge on any member.
`gh-queue-open-prs` evaluates every open PR against the ruleset-derived required set and enqueues the green ones in bulk; `gh-queue-open-prs -n` reports without acting.
External handoff follows `git-stacked-pr-integration` §Queue authorization in every local VCS mode.

A green `nixbot/nix-build` is not the same as every check having passed.
The aarch64-darwin checks are best-effort through `modules/checks/nixbot-best-effort-darwin.nix`, which marks their failures `ignored_failure` so an asleep or unreachable Mac builder cannot block the queue; the flag concerns builder availability, never correctness.
Read those failures before enqueueing rather than treating the aggregate status as the whole answer, because a genuine platform-specific break — an upstream package that compiles only with the other platform's toolchain, say — presents exactly as an ignored failure and would otherwise reach `main` unnoticed.

Checkouts of this repository are commonly colocated with [jujutsu](https://jj-vcs.github.io/jj/), in which case a detached git `HEAD` is normal and must not be reattached.
Because this is a flake repository, flake evaluation resolves the root through git, so a second working tree must itself be a git worktree: either a colocated `jj workspace add` directory, which jj 0.46.0 and later creates by default here because `git.colocate` is `true`, or a `wt switch --create <branch>` worktree.
Entering the devshell once in a new tree (`direnv allow`) installs the prek hooks, pins `core.hooksPath` to an absolute path so git runs them from every checkout, and runs `mergify stack setup`, so a git commit there gets treefmt, gitleaks, and a `Change-Id` trailer.
In a checkout with a `.jj/` directory the devshell also exports `CLAN_NO_COMMIT=1`, so clan registers the vars files it generates with `git add --intent-to-add` for jj to snapshot instead of committing them and moving git `HEAD` off the join; plain-git clones keep clan's commit.
jj commits run no git hooks and take their `Change-Id` from `templates.commit_trailers`, so run `just lint` before pushing them.
