# vanixiets

vanixiets manages nix-darwin workstations and NixOS cloud servers with [clan](https://clan.lol), using a deferred module composition architecture.
Clan handles multi-machine provisioning and declarative configuration across nix-darwin, NixOS, and home-manager, with sops-nix for secrets and ZeroTier for the private mesh network.
The flake is built with flake-parts and import-tree, so every module under `modules/` is discovered from the filesystem rather than listed in an explicit import set; adding a file is how a module is registered.

The repository also publishes an [apm](https://github.com/microsoft/apm) marketplace of agent-skill plugins, which is independent of the Nix configurations and installable on its own.

## Repository layout

`machines/` holds one directory per NixOS machine.
`modules/` holds the flake-parts modules import-tree discovers, subdivided by concern: `clan/` for inventory and clan services, `darwin/` and `nixos/` for per-platform system configuration, `home/` for home-manager, `terranix/` for cloud resource declarations, `checks/` for flake checks, and `containers/`, `kubernetes.nix`, and `nixidy.nix` for the container and Kubernetes layers.
`pkgs/by-name/` holds first-party packages, several of which override versions supplied by flake inputs.
`lib/`, `scripts/`, `secrets/`, `sops/`, `vars/`, and `terraform/` hold shared helpers, operational scripts, encrypted material, and generated Terraform state respectively.

Documentation lives in two places.
`packages/docs/` is an Astro Starlight site published from this repository, and architecture decision records live under `packages/docs/src/content/docs/development/architecture/adrs/`.
`docs/` holds the working notes and reference material that feed it, including `docs/notes/development/kubernetes/` for the Kubernetes platform design and its own ADR series.

`openspec/` holds change proposals and their specs; `openspec/changes/archive/` is deliberately tracked, which is why the `archive/` ignore rule in `.gitignore` is anchored to the repository root.

## Building, checking, and testing

`just` is the task entry point; `just help` lists the recipes.

`just check` runs `nix flake check` over everything.
`just check-fast` runs the same check set through `nix-fast-build` and is the normal local loop.
`just test-quick` builds a named subset of checks directly for fast feedback.
`just lint` runs the `prek` hook set, which is treefmt plus a staged-diff gitleaks scan; the hooks are declared in `modules/formatting.nix` rather than in a `.pre-commit-config.yaml`.

Individual checks are addressable, so the narrowest useful selection is usually a direct build of the one that covers the change, for example `nix build .#checks.<system>.gitleaks`.
`checks.gitleaks` scans the whole flake source tree with `gitleaks detect --no-git`, so it covers any newly committed file, not only staged diffs.
Check definitions live under `modules/checks/`, and each carries a `passthru.meta.description` naming what it validates.

Documentation has its own lane under `packages/docs`: `just docs-lint`, `just docs-check`, and the `just docs-test-*` recipes.

## Machine configuration

Cloud machines are declared through terranix in `modules/terranix/`, one file per provider.
Each machine carries an `enabled` boolean: setting it to `false` and running `nix run .#terraform` removes the cloud resources while leaving the machine's full NixOS configuration, clan inventory entry, and disko layout in the repository.
A machine present in `machines/` is therefore not necessarily provisioned, and agents should not assume any machine is reachable or attempt remote operations against one.

Two admin-username conventions coexist: older machines force the username `crs58`, and newer ones use `cameron` as a home-manager alias for the same account.
Modules that hardcode a username are following one convention or the other, and which one is a property of the machine.

## AI agent architecture

`modules/home/tools/agents-md.nix` is the single source that generates the user-level agent context files (`~/.claude/CLAUDE.md`, `~/.gemini/GEMINI.md`, and the `AGENTS.md`, `CRUSH.md`, and `OPENCODE.md` equivalents).
Those destinations are Nix-managed outputs: edit `agents-md.nix`, never the generated file.
This is user-level context and is distinct from the project-level context in this file.

Agent skills are packaged as apm marketplace plugins.
The source of truth for every first-party skill is `modules/home/ai/plugins/<group>/.apm/skills/<skill>/SKILL.md`, currently 132 skills across 18 packages.
Each `<group>/` carries an `apm.yml` and a `plugin.json` manifest beside its `.apm/skills/` tree, and the marketplace manifest is `.github/plugin/marketplace.json`.

At build time `pkgs/by-name/apm-skills-compose/` composes those packages, plus remote apm dependencies resolved offline, into a flat skill tree.
`modules/home/ai/skills/{compose.nix,default.nix}` re-globs that tree and delivers it through home-manager symlinks to each harness's skills directory.
The delivered `~/.claude/skills/<skill>/SKILL.md` is a read-only Nix store symlink, so edits belong in the plugins source in this repository.

`modules/home/ai/` also holds per-harness home-manager modules for hooks, MCP servers, settings, and wrappers, one directory per agent tool.

## Reference repositories

Local copies of upstream sources live under `~/ghq/<host>/<org>/<repo>`.
`ghq list -p <name>` is the authority for whether a copy exists, because it walks the filesystem rather than consulting an index; `zoxide query -l <name>` is a fast path only and must be validated against `ghq list -p` before it is relied on.
On a miss, `ghq-sync <url>` clones shallow and blobless and registers the path.
`ghq-sync` is built from `pkgs/by-name/` in this repository.

For clan orchestration, secrets, and networking:

- `clan/clan-core` — clan source
- `clan/clan-infra` — the primary production reference, flake-parts without deferred module composition
- `Qubasa/infra`, `Mic92/dotfiles`, `pinpox/nixos` — clan-core maintainers' own clan configurations
- `jfly/snow`, `Enzime/dotfiles-nix`, `onixcomputer/onix-core` — third-party clan usage

For deferred module composition, a pattern also published under the name "dendritic":

- `hercules-ci/flake-parts` — flake-parts source
- `vic/import-tree` — the auto-discovery mechanism
- `mightyiam/dendritic` — the original pattern description
- `vic/dendrix`, `drupol/infra`, `mightyiam/infra`, `GaetanLepage/nix-config` — reference implementations
- `molybdenumsoftware/nixpkgs.molybdenum.software` — a minimal deferred-module-composition plus clan combination
- `nix-community/nix-unit` and `cameronraysmith/nix-unit-flake-parts` — Nix unit testing

For the build, Kubernetes, and cloud-provisioning layers:

- `nix-community/buildbot-nix` and `Mic92/niks3` — the CI and binary-cache NixOS modules
- `arnarg/nixidy` and `arnarg/cluster` — ArgoCD rendered-manifest generation, with an example cluster configuration
- `Lillecarl/easykubenix` and `Lillecarl/hetzkube` — Cluster API on Hetzner, with an example
- `terranix/terranix` — the Terraform-from-Nix layer
- `syself/cluster-api-provider-hetzner` — the Cluster API infrastructure provider
- `hetznercloud/terraform-provider-hcloud`, `cloudflare/terraform-provider-cloudflare`, `carlpett/terraform-provider-sops` — Terraform providers in use
- `isindir/sops-secrets-operator`, `smallstep/helm-charts` — in-cluster secrets and PKI

## Domain modeling sources

The `preferences-domain-driven-architecture`, `preferences-event-driven-systems`, and `preferences-functional-programming-theory` skill packages synthesize three sources, and the skills' vocabulary is easier to follow with the attribution in hand:

- Scott Wlaschin, *Domain Modeling Made Functional* (2018) — practical type-driven patterns in F#: smart constructors, workflows as pipelines, making illegal states unrepresentable, railway-oriented programming
- Debasish Ghosh, *Functional and Reactive Domain Modeling* (2016) — algebraic foundations in Scala: signatures, algebras and interpreters, laws as specifications, the module algebra pattern
- Kevin Hoffman, *Real World Event Sourcing* (2024) — event sourcing depth in Rust: aggregate design, projections, process managers, operational concerns

## Version control

The default branch is `main`.
Merge queue behaviour is declared in `.github/mergify.yml`: human pull requests fast-forward so their commit SHAs survive, while bot pull requests are batched and rebased.

Checkouts of this repository are commonly colocated with [jujutsu](https://jj-vcs.github.io/jj/), in which case a detached git `HEAD` is normal and must not be reattached.
Because this is a flake repository, flake evaluation resolves the root through git, so a second working tree must be created with `git worktree add` rather than `jj workspace add`.

## Agent context files

`AGENTS.md` at the repository root is the single source of truth for project-level agent context, and it is committed and reviewed like any other file in the tree.
`CLAUDE.md` is a one-line pointer, `@AGENTS.md`, so Claude Code loads the same text without a second copy that can drift.
Any clone or worktree of this repository is context-primed from these two committed files alone, with no machine-local setup step.
[ADR-0022](packages/docs/src/content/docs/development/architecture/adrs/0022-committed-per-repository-agent-context.md) records why the context is committed rather than provisioned per machine.

`CLAUDE.md` must stay a real file rather than a symlink to `AGENTS.md`.
OpenWiki maintains a managed block in both files independently, and writing through a symlink would deliver the `CLAUDE.md` block into `AGENTS.md`, leaving two marker pairs in one file; OpenWiki then refuses to update that file at all.
For the same reason, OpenWiki's literal marker strings must not appear in this file outside the block OpenWiki owns, since it locates its block with a first-and-last-occurrence match and treats a second pair as malformed.

Repository-specific direction for OpenWiki lives in `openwiki/INSTRUCTIONS.md`, which is user-authored and is never rewritten by a normal run.
The scheduled refresh is `.github/workflows/openwiki-update.yml`.

`.claude/` is not covered by any rule in `.gitignore`; `.claude/settings.local.json` is excluded per checkout through `.git/info/exclude`.
`.factory/`, droid's equivalent, is likewise machine-local and covered by no committed ignore rule.
If either directory gains a file that should be shared, add a committed ignore rule for the rest at that point rather than assuming one exists.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
