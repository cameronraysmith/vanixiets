---
description: vanixiets reference repositories — the ghq lookup mechanism, fork policy, and the upstream sources this repository's patterns and skill content are drawn from.
---

## Reference repositories

Local copies of upstream sources live under `$(ghq root)/<host>/<org>/<repo>`, which is `~/ghq` unless a host shares one tree.
Magnetite, pyrite and stibnite do: their root is the read-only `/var/lib/ghq`, which `~/ghq` links to and whose real path `ghq list -p` prints (`/private/var/lib/ghq` on stibnite), and its writer account carries out acquisition, update, deepening, promotion and hydration.
`ghq list -p <name>` is the authority for whether a copy exists, because it walks the filesystem rather than consulting an index; `zoxide query -l <name>` is a fast path only and must be validated against `ghq list -p` before it is relied on.
On a miss, `ghq-sync <url>` clones shallow and blobless and registers the path with the caller's zoxide.
Before reading at a revision other than the checked-out one, `ghq-sync --hydrate <rev> <path-or-owner/repo>` fetches the file contents that revision needs; Git LFS paths in the shared tree hold pointer files.
In the shared tree the writer also makes every commit a request brought into a copy's branches and remote-tracking branches, by an update, a deepen or a tag fetch, readable as a diff, unless more than 100,000 blobs are missing, which its answer reports; a commit only a tag reaches, as `--tags` fetches one at depth 1, stays unhydrated until `ghq-sync --hydrate <tag>` or until a branch commit an update brings in reaches it, and any other commit's diff (`git show <rev>`) needs `<rev>` and each parent hydrated, and `git diff A B` needs both `A` and `B`.
Readers' git there refuses every network transport, so a read needing absent contents fails at once with `transport '<scheme>' not allowed` and `could not fetch <oid> from promisor remote`, and `git ls-remote origin`, `git remote show origin` and `git fetch` inside a copy fail too; a request waiting for a busy repository prints `ghq-writer: waiting up to 3600 s for <repository>, …`, and the writer logs each request, without its target, to the `ghq-writer@` journal (magnetite, pyrite) or `/var/log/ghq-writer/writer.log` (stibnite).
`ghq-sync` is built from `pkgs/by-name/` in this repository.
Prefer the canonical upstream over a personal fork; acquire a personal fork only when contribution back to that upstream is anticipated.

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
