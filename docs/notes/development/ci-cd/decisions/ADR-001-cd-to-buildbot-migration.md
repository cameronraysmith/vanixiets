# ADR-001: cd.yaml → buildbot-nix / hercules-ci-effects migration

Status: Accepted 2026-04-21; revised 2026-04-22 to incorporate discovery resolutions and correct architectural claims.

## Identity

Migrate `.github/workflows/cd.yaml` and everything it transitively invokes (reusable workflows, composite actions, inline script bodies) off GitHub Actions and onto magnetite's buildbot-nix deployment, using hercules-ci-effects for impure execution and `writeShellApplication` flake apps for script bodies. Scope is strictly the CD surface — `ci.yaml` migration already landed pre-epic.

## Context

Three options were considered for the caching problem that surfaced in the origin artifact (`./logs/vanixiets-2026-04-21-test-cluster-cache-strategy.txt`), where `cd.yaml`'s coarse cache invalidation in `cached-ci-job/action.yaml` caused unrelated-input bumps to re-run the full job set:

- **Option A — narrow the `flake.lock` cache key via `jq` node extraction.** Recompute the key from just the subset of lock-file nodes relevant to a given job. Rejected outright: `flake.lock`'s node graph is denormalized (follows-resolutions, transitive inputs), and correctly computing a per-job projection is its own correctness problem with no test harness behind it. Brittle in-place of a principled fix.

- **Option B — drvPath-derived cache key in `cached-ci-job/action.yaml`.** Compute `nix eval --raw '.#checks.<sys>.<name>.drvPath'` once per job and key `actions/cache` on that. Principled (the drvPath is the canonical content hash for a nix build) but is bespoke GHA machinery that becomes garbage the moment buildbot-nix takes over. Retained as **designated fallback** if Option-C discovery blocks on any single job; otherwise discarded.

- **Option C — migrate `cd.yaml` to buildbot-nix using `writeShellApplication` flake apps + hercules-ci-effects.** Realizes "run only when pure closure changes" as the native semantic of the build system. Chosen direction for the full `cd.yaml` surface.

The caching question is the proximate trigger; the underlying decision is driven by `nix-7v7`, which established self-sovereign build infrastructure on magnetite: niks3 binary cache on Cloudflare R2, buildbot-nix with GitHub + Gitea forge integration, and Gitea self-hosted forge. `buildbot-nix.toml` already configures magnetite's buildbot to evaluate `checks.x86_64-linux` against vanixiets. This epic realizes the CI/CD yield of that infrastructure investment; without it, magnetite evaluates vanixiets checks but does not gate releases.

Hercules-ci-effects is available to buildbot-nix as a transitive flake-lock pin only. It is **not** a top-level flake input of vanixiets today, **not** imported as a flake-parts module, and no `herculesCI` / `onPush` / `mkEffect` attribute is defined anywhere in `./modules`. Phase 3 introduces all three. (Source: `flake.nix`, `flake.lock:655-678`.) Confidence: HIGH.

The steady-state target on magnetite (Hetzner, a CX53 instance type) is niks3 + buildbot-nix + Gitea colocated, with hercules-ci-effects enabled and a docker-compatible container runtime provisioned for k3d-running effects. The exact CX53 shape is internally inconsistent in-repo (`modules/nixos/buildbot.nix` sets `cores = 16`; `modules/terranix/hetzner.nix:25-30` documents 16 vCPU / 32 GB / 320 GB; an inline comment in `buildbot.nix:103` says "8 vCPU / 16 GB") and requires a live `nproc` / `free -h` / `df -h` check before capacity claims become load-bearing — noted as a Phase 4 entry condition, not fabricated as a resolved value.

`cached-ci-job/action.yaml`'s hashing algorithm has been verified (D14): it hashes `flake.lock` in its entirety via a single `git hash-object` call; the `hash-sources` input is a whitespace-separated glob list iterated with `set -f` disabling shell expansion; `**`-containing patterns are expanded by shelling to `find -type f -name <last-segment>` rather than bash globstar; the action auto-includes the invoking workflow file and itself, and excludes `packages/docs/src/content/docs/notes/*`. The final key is `job-result-<sanitized-name>-<12-char sha256 prefix>` over concatenated `git hash-object` outputs. Confidence: HIGH. This confirms the original cache-coarseness hypothesis and informs Option B fallback design if discovery blocks.

## Decision — target architecture

### Module layout

Four domain-organized subdirectories under `modules/apps/` host migrated job logic:

- `modules/apps/cluster/` — k3d local integration and forward-compatible Hetzner production cluster orchestration
- `modules/apps/docs/` — documentation preview/release/deploy (partially present per nix-a8g precedent)
- `modules/apps/release/` — production release-packages
- `modules/apps/bootstrap/` — bootstrap-verification

Each app follows the nix-a8g template: `<name>.nix` declares `pkgs.writeShellApplication` with `runtimeInputs` for the hermetic package closure; `<name>.sh` holds the script body ingested via `readFile`.

Template bifurcation (per nix-a8g extraction): `modules/apps/docs/deploy.nix` uses string-interpolation form `text = "${builtins.readFile ./deploy.sh}"` because it injects nix-computed variables at eval time (`SOPS_SECRETS_FILE`, `DOCS_PAYLOAD`); `release.nix` and `preview-version.nix` use pure `text = builtins.readFile ./release.sh`. Cluster apps requiring injection of nix-computed paths (e.g., `CLUSTER_CONFIG`, `SOPS_AGE_KEY_PATH`) use the interpolation form; otherwise pure readFile. Phase 1 documents this bifurcation as part of the cluster-app template guide. Confidence: HIGH.

Dual-maintenance between justfile recipe and flake app is convention-only. Justfile recipes wrap flake apps via `nix run .#<app>`; no enforced lint. Indirect safeguards: (a) CI hash-sources pin the coupling so drift surfaces as rebuild during Phase 5; (b) shellcheck at build time catches script-level regressions. Phase 1 documents dual-maintenance as a review responsibility. Confidence: HIGH.

### Execution model

Pure data jobs become package-classified derivations where the work is genuinely a nix derivation producing a consumed artifact. The GHA `set-variables` job does **not** survive as a single derivation in the target architecture; its dispatch-variable surface is distributed across three native buildbot-nix / hercules-ci-effects mechanisms rather than centralized in one emitting package. See "Trigger translation" below for the per-variable mapping: `branch` / `rev` / `shortRev` arrive as top-level arguments to each effect via buildbot-effects; `debug` is the `buildbot-effects run --debug` flag; `force-ci` has no analog (every effect run is fresh — there is no GHA-style cache-hit skipping to override); `sanitized_branch` is computed inline inside each effect that needs it; `deploy_enabled` collapses into per-effect `hci-effects.runIf` gating plus `effects_branches` configuration; the `packages` matrix becomes flake-eval-time expansion — one attribute per package under `onPush.default.outputs.effects` or under `packages.x86_64-linux.*`. No synthetic `cd-variables` package exists in the target architecture. Confidence: HIGH.

Impure jobs become hercules-ci-effects under a **single fixed attribute path**. buildbot-nix reads `flake.outputs.herculesCI(args).onPush.default.outputs.effects` on every evaluation; the literal `default` is not a branch name — it is the one and only attribute path buildbot-nix consumes. Source of truth: `buildbot-nix/buildbot_effects/buildbot_effects/__init__.py:142-159`. Per-branch `onPush.<name>` nodes are allowed by the hercules type system but are ignored by buildbot-nix. Branch-specific gating is expressed two ways, neither of them in the Nix attribute path:

- **What runs:** `herculesCI.onPush.default.outputs.effects.<name>` (always the same set per evaluation).
- **When it runs:** `effects_branches = ["main", "release/*", ...]` (glob list) and `effects_on_pull_requests = true|false` in `buildbot-nix.toml`, **always read from the default-branch copy** via `git show origin/<default>:buildbot-nix.toml`. A PR author cannot self-authorize by modifying their PR's toml. Source: `buildbot-nix/buildbot_nix/buildbot_nix/nix_eval.py:596-632`.
- **Within the Nix expression:** `hci-effects.runIf <cond> <effect>` gates individual effects at eval time (e.g., `runIf (args.branch == "main")`).

Inter-effect dependencies are **not expressible** at the buildbot-nix surface. Every attribute under `onPush.default.outputs.effects` becomes one independent Triggerable build on the `<project>/run-effect` builder; all effects are triggered in parallel with `waitForFinish=True, haltOnFailure=True, flunkOnFailure=True` (`nix_eval.py:708-729`). The only cross-effect ordering guarantee is "the prior `nix-build` matrix has succeeded"; there is no "effect A before effect B" edge. Former GHA `needs:` edges carrying no data are dropped; edges carrying data collapse to derivation-input references; edges demanding execution ordering are expressed via `runIf` gating on a prior effect's completion-signal derivation or by composing into a single larger effect. Confidence: HIGH.

### Secret pipeline (not a sidecar)

There is no buildbot-effects sidecar process. `buildbot-effects` is a CLI tool in the worker's Python environment. The end-to-end secret flow for an effect build is:

1. `services.buildbot-nix.master.effects.perRepoSecretFiles."<forge>:<owner>/<repo>" = <path>` declared on the master's NixOS config (option at `buildbot-nix/nixosModules/master.nix:716-732`).
2. Master loads the file as a systemd `LoadCredential` entry.
3. Buildbot reads it as a `SecretInAFile` via `$CREDENTIALS_DIRECTORY`.
4. For a scheduled effect build, the master writes the JSON blob to `../secrets.json` relative to the worker's build directory and invokes `buildbot-effects run --secrets ../secrets.json <effect-attr>`.
5. `buildbot-effects` starts a `bwrap` sandbox, bind-mounts the file at `/run/secrets.json`, and sets `HERCULES_CI_SECRETS_JSON=/run/secrets.json`.
6. The effect script reads that env var and parses the JSON to obtain secrets at runtime.

Canonical end-to-end example: Harmonia's codecov token, wired at `~/projects/nix-workspace/mic92-clan-dotfiles/machines/eve/modules/buildbot.nix:50-66` and consumed at `~/projects/nix-workspace/harmonia/nix/herculesCI.nix:54-60` with `jq -r '.codecov.data.token // empty' "$HERCULES_CI_SECRETS_JSON"`. Confidence: HIGH.

clan-infra web01 is the **secret-wiring and niks3/buildbot colocation reference** only. Exhaustive grep of `~/projects/nix-workspace/clan-infra/` for `hercules|effects|mkEffect|onPush|herculesCI` returns no matches beyond the flake-parts URL. web01 does not run hercules effects. It uses two parallel secret systems — `sops.secrets.*` for buildbot forge credentials and `clan.core.vars.generators.*` for niks3 S3 creds, signing key, and API token — both delivered to services via systemd-managed decrypted files on disk. The effects-secrets JSON file on magnetite will follow the same delivery mechanism (clan-vars preferred, consistent with magnetite's existing convention of no sops-nix usage), but its shape (flat JSON dict) and wiring (`perRepoSecretFiles`) are dictated by buildbot-nix upstream, not web01. Confidence: HIGH.

### Per-job purity mapping

The `set-variables` job is intentionally absent from the table below: as explained in the execution-model paragraph above, its responsibilities (dispatch variables, package matrix, debug/force flags, branch gating) have more natural homes in the buildbot-nix / hercules-ci-effects surface — effect arguments, `runIf` gating, `effects_branches` configuration, and flake-eval-time attribute expansion — rather than as a single synthetic package derivation. See "Trigger translation" below.

| Job | Classification | Confidence | Rationale |
|---|---|---|---|
| `preview-release-version` | pure → `checks.x86_64-linux.preview-release-<pkg>` (or `packages.`) | HIGH | `@semantic-release/github` is explicitly filtered from `--plugins`; no `git push`; trap-restored local-only `git update-ref`; `contents: write` permission is vestigial (semantic-release `verifyAuth` requires it even in dry-run); can be kept or dropped |
| `bootstrap-verification` | effect | HIGH | Mutates `~/.config/sops/age/keys.txt`; `make bootstrap` installs nix daemon via the nix-installer + creates `nixbld` users + writes `/etc/nix/nix.conf`; `make setup-user` generates a fresh age key — all outside the nix sandbox. Cannot be subsumed under buildbot's check graph because its job is to test the bootstrapping path that *makes* nix usable |
| `test-cluster` | effect (local-only) | HIGH | Docker / k3d / ephemeral filesystem mutation; no cross-network mutation but still nix-sandbox-external |
| `preview-docs-deploy` | effect | HIGH | `wrangler versions upload` creates a preview alias on Cloudflare Workers |
| `production-docs-deploy` | effect | HIGH | `wrangler versions deploy <id>@100%` against production `infra.cameronraysmith.net` |
| `production-release-packages` | effect | HIGH | semantic-release with `--dry-run=false`, git tag push, GitHub Release creation, `npmPublish: false`; authority via `GITHUB_TOKEN` |

### Trigger translation

Mapping GHA triggers to buildbot-nix / hercules-ci-effects using the two-axis model (Nix attribute path + `buildbot-nix.toml` configuration):

- **`push` on branches** — effect discovery always happens at `onPush.default.outputs.effects.*`. Execution is gated by the default-branch `buildbot-nix.toml`: default branch always runs effects; other branches run iff their name matches an `effects_branches` glob.
- **`pull_request`** — effects execute iff `effects_on_pull_requests = true` in the default-branch `buildbot-nix.toml`. `checks.<sys>.*` builds run unconditionally in the Nix sandbox. See "Fork-PR posture" below.
- **`schedule`** — expressed as `herculesCI.onSchedule.<name> = { when = { minute; hour; dayOfWeek; dayOfMonth; }; outputs.effects.<effect> = ...; }`. The schema is a structured submodule, **not** a cron string; `dayOfWeek` is a list of `"Mon".."Sun"` translated to buildbot's `0..6`. Missing fields default to deterministic-seeded values to avoid thundering herd. Schedule changes propagate on the next successful default-branch `nix-eval` and trigger a `master.reconfig()`. Source: `buildbot-nix/buildbot_nix/buildbot_nix/scheduled.py`, `buildbot-nix/checks/test-flake/flake.nix`.
- **`workflow_dispatch`** — three substitute surfaces, in priority order:
  1. **CLI over ZeroTier (primary):** `ssh magnetite.zt buildbot-effects run github:cameronraysmith/vanixiets/<branch>#<effect> [--debug] [--secrets ...]`. The CLI is verified in `buildbot-nix/buildbot_effects/buildbot_effects/cli.py`; subcommands are `list`, `run`, `list-schedules`, `run-scheduled`; flags include `--rev`, `--branch`, `--repo`, `--path`, `--debug`, `--secrets <json>`; flakeref syntax (`github:org/repo/branch#effect`) is supported. The master runs exactly this same command on the `run-effect` builder. Packaging: `just ci-dispatch <effect> [flags]` wraps the SSH invocation. Confidence: HIGH.
  2. **Web-UI Rebuild (secondary):** The "Rebuild" button on a prior `run-effect` build gives per-effect re-run granularity at the prior rev. Available only if the effect has already run at least once at the desired rev. The web-UI "Force Build" affordance is wired only to `{project}/nix-eval` — it re-runs the whole evaluation, not a single effect; not a per-effect substitute.
  3. **Thin GHA shim (fallback only):** A `cd-dispatch.yaml` workflow with matching `inputs` that dispatches via buildbot REST or a trailer-parsed commit push. Retained as fallback for any case where operators demand a GitHub UI surface; adds a GHA layer that defeats simplification.

Path filters (`paths-ignore: '*.md'` is the only one in `cd.yaml` and exists at workflow level, not per-job) become derivation-input scoping — restricting a derivation's `src` to the relevant subtree via `lib.fileset.*`. For content-scoped `runIf` gating, hash path content and compare in the effect declaration.

Arguments passed to effects: buildbot-effects passes `{ name, branch, ref, tag, rev, shortRev, remoteHttpUrl, primaryRepo }` at top level, with `primaryRepo` containing the same fields. `ref` is always `null` (TODO in upstream). Fields that hercules-ci-agent natively provides (`owner`, `remoteSshUrl`, `webUrl`, `forgeType`) are **not** set by buildbot-effects; accessing them throws under the hercules flake-module unless effects are written to degrade gracefully. Effect scripts must only rely on the fields above.

### Fork-PR posture

buildbot-nix has no author/contributor allowlist for PR builds. The PR scheduler matches `category="pull"` unconditionally; `GitLocalPrMerge` fetches fork HEAD via the base-repo URL (`refs/pull/<n>/head`) and merges as normal. `userAllowlist`/`repoAllowlist` filter which *repositories buildbot manages*, not which PRs it accepts. Source: `buildbot-nix/buildbot_nix/buildbot_nix/project_config.py:85-99`, `common.py:116-150`.

Under buildbot-nix defaults (`effects_on_pull_requests = false`), fork PRs receive no effect-secrets: the effects builder returns `util.SKIPPED`, and `checks.<sys>.*` runs in the Nix sandbox with no wired secrets. If the flag is flipped to `true`, fork PRs receive the full `effects_per_repo_secrets` JSON with **no author allowlist, no fork-vs-same-repo differentiation, no differential privilege, and no Nix sandbox** — effects run as impure shell commands on the worker with the secrets file on disk. The upstream README (`buildbot-nix/README.md:184-190`) explicitly warns this is exploitable. Vanixiets currently has `effects.perRepoSecretFiles = {}` and the flag unset.

**Recommended default: Posture A.** `effects_on_pull_requests = false`. Preview-* effects run only on default-branch merges. Contributors see `checks.<sys>.*` feedback (safe, Nix-sandboxed) on their PRs but no contributor-triggered preview-deploy.

**Named future option: Posture B.** Re-push contributor PR commits onto base-repo `preview/<pr-id>` branches; add `effects_branches = ["preview/*"]` so secrets reach only writers with base-repo push access. Mirrors GHA's `pull_request_target` trust boundary. Adoption contingent on contributor preview-feedback becoming a priority.

## Phase structure

**Phase 1 — `writeShellApplication` foundation across four domains.** Per-job script bodies plus their transitive just/shell recipes are converted to the nix-a8g template. Justfile recipes rewrite as thin wrappers invoking `nix run .#<app>`. Phase-1 conversion set (from inventory research 03): `list-packages-json`, `k3d-integration-ci`, `k3d-full`, `k3d-bootstrap-secrets`, `k3d-configure-dns`, `k3d-wait-ready`, `k3d-wait-argocd-sync`, `k3d-test-coverage`, `nixidy-build`, `nixidy-bootstrap`, `nixidy-sync`, `nixidy-push`, and `scripts/k3d-test-coverage.sh`. Scope explicitly excludes composite-action and reusable-workflow disappearance work — that belongs to Phase 6. No production cutover; existing GHA still runs.

**Phase 2 — Per-job branch-point decision.** Per `cd.yaml` job, confirm Option-C viability. Jobs may diverge: `test-cluster` may proceed to C while `release-packages` awaits secret-pipeline work. Per-job decision, not global.

**Phase 3 — Effects wiring.** Entry conditions: (a) add `hercules-ci-effects` as a top-level flake input with `inputs.flake-parts.follows = "flake-parts"; inputs.nixpkgs.follows = "nixpkgs";`; (b) introduce a flake-level module importing `inputs.hercules-ci-effects.flakeModule` under the deferred-module composition; (c) declare at least an empty `herculesCI = { ... }: { onPush.default.outputs.effects = { }; }`. Then per job confirmed in Phase 2, populate `herculesCI.onPush.default.outputs.effects.<name>` and gate branches via `effects_branches` in `buildbot-nix.toml`. Overlaps with Phase 5.

**Phase 4 — Worker provisioning.** Entry conditions:

1. **Live CX53 capacity confirmation.** `ssh magnetite.zt 'nproc && free -h && df -h /'`. Reconcile with `modules/terranix/hetzner.nix:25-30` and `modules/nixos/buildbot.nix` `cores = 16`. The stale inline comment in `buildbot.nix:103` ("CX53 (8 vCPU, 16 GB RAM)") is either corrected or confirmed; capacity claims downstream become load-bearing only after live verification.
2. **Docker runtime.** magnetite currently runs only `virtualisation.podman` (for gitea-actions-runner, storage at `zroot/root/podman`). k3d effects need docker. Enable `virtualisation.docker.enable = true;` and provision a dedicated ZFS dataset `zroot/root/docker` in `modules/machines/nixos/magnetite/disko.nix` (mirroring the podman pattern). Validate that the docker socket is reachable by the buildbot worker user.
3. **`perRepoSecretFiles` wiring.** Add a clan-vars generator emitting the effects-secret JSON blob (shape: `{ "secretName": "value", ... }` — flat dict consumable as `HERCULES_CI_SECRETS_JSON`). Wire `services.buildbot-nix.master.effects.perRepoSecretFiles."github:cameronraysmith/vanixiets" = config.clan.core.vars.generators.buildbot-effects-vanixiets.files."secrets.json".path;`.
4. **Optional cgroup isolation.** `systemd.slices.effects` with `MemoryMax` and `CPUQuota` caps, attaching buildbot-effects runs to that slice; reduce `gitea-actions-runner.numInstances` during migration window if contention surfaces.

**Phase 5 — Per-job parity validation.** Entry condition: per-job parity-N threshold locked per the rollback rubric in "Resolutions" (D9 row). Both GHA and buildbot-nix paths run simultaneously.

- Reversible jobs (`bootstrap-verification`, `preview-release-version`, `preview-docs-deploy`, `test-cluster`): N = 2–3. (`set-variables` is absent from the migration target per "Execution model" / "Per-job purity mapping" above.)
- Irreversible jobs (`production-docs-deploy`, `production-release-packages`): N ≥ 5 with mandatory rollback rehearsal at least once. Dual-writer mitigation is mandatory during parity: keep buildbot's semantic-release in `dry-run: true` so only GHA publishes; flip to `dry-run: false` at cutover. Symmetric approach for tag push and production deploys.

Compared: success/failure consistency, timing, log quality, secret handling, observability. Abort parity if divergence rate exceeds 20% within the first 10 runs per job or if any single divergence occurs on an irreversible job.

**Phase 6 — Per-job sunset + `cd.yaml` archival + composite-action/reusable-workflow disappearance + drift cleanup.**

Disappearance cluster splits into two sub-clusters:

- **Disappears without replacement** (exactly two composite actions per the inventory):
  - `.github/actions/cached-ci-job/action.yaml` — subsumed by the content-addressed nix store + binary cache.
  - `.github/actions/setup-nix/action.yml` — buildbot-nix workers have nix pre-provisioned.
- **Artifact disappears, logic migrates:**
  - `.github/workflows/test-cluster.yaml` — logic migrates to `modules/apps/cluster/*.{nix,sh}` plus the `test-cluster` effect definition; the workflow file is removed.
  - `.github/workflows/deploy-docs.yaml` — logic migrates to `modules/apps/docs/deploy.{nix,sh}` (already present) plus the `preview-docs-deploy` and `production-docs-deploy` effects.
  - `.github/workflows/package-release.yaml` — logic migrates to `modules/apps/release/*.{nix,sh}` plus the `production-release-packages` effect.

Per-job removal from `cd.yaml` after parity threshold met. Final archival of `cd.yaml` once all migrated jobs are confirmed — `cd.yaml` preserved in `.github/deprecated/` per existing precedent, enabling rollback by un-archiving individual jobs.

**Drift and dead-surface cleanup (Phase 6):**

- `scripts/preview-version.sh` (legacy root copy, 8684 bytes, not referenced by any active workflow; consumed only by `package.json:18` and by the deprecated `.github/deprecated/*.yaml` hash-sources lines) — delete.
- `package.json:18` (`"preview-version": "./scripts/preview-version.sh"`) — repoint to `nix run .#preview-version` or drop.
- `.github/deprecated/ci-nix-fast-build.yaml` and `.github/deprecated/ci-pre-nix-check.yaml` — drop `scripts/preview-version.sh` references from `hash-sources` strings, or leave as historical if the deprecated files are themselves earmarked for deletion.
- Documentation drift: update `packages/docs/src/content/docs/about/contributing/semantic-release-preview.md` to reference `nix run .#preview-version` and `just preview-version <target> <package>`. (Path differs from earlier ADR drafts that said `docs/content/.../` — the actual path is `packages/docs/src/content/docs/about/contributing/semantic-release-preview.md`.)
- `cd.yaml` `workflow_call` inputs `target_configs`, `cache_control`, `job_selection` — declared, never referenced anywhere in the file. Dead input surface; strip during migration.
- `test-cluster.yaml` `env.CACHIX_BINARY_CACHE: cameronraysmith` — set, never consumed by any action. Dead env var; strip.
- `inputs.job` selector value `'docs-deploy'` vs actual job name `production-docs-deploy` — normalize during migration (rename selector to `production-docs-deploy` or document the alias).
- `permissions: contents: write` on `preview-release-version` — vestigial (semantic-release `verifyAuth` requires it even in dry-run). Document if kept; drop if the dry-run plugin filter eliminates the dependency.

### Exit criteria (mutually exclusive)

- **Fully-migrated.** All 7 jobs migrated. `cd.yaml` archived to `.github/deprecated/`. Composite actions and reusable workflows disappeared per Phase 6 sub-clusters. Worker provisioning complete. Rollback recoverable via un-archiving individual job definitions.
- **Hybrid-stable.** Subset migrated; remainder stays on GHA indefinitely due to blocking outcomes or coordination requirements. `cd.yaml` active for the GHA residue. Revisit trigger: quarterly review of still-on-GHA jobs against the blocker that kept them there. Prevents drift into indefinite hybrid.
- **Discovery-blocks.** A hard blocker (e.g., a job whose secret model cannot safely migrate, or a k3d-on-docker incompatibility) surfaces during Phase 3 or 4. Fall back to Option B scoped to affected jobs — `writeShellApplication` conversion from Phase 1 still lands as independently valuable infrastructure; Option B cache-key extension applied to `cached-ci-job/action.yaml` completes the fallback for the residue.

## Resolutions

Phase 0 is folded into Phase 3/4/5 entry conditions; the table below summarizes discovery items from the prior draft, their resolution, and the research report that resolved each. Reports are under `.factory/research/adr-001-validation/`.

| Item | Status | Resolution | Reference |
|---|---|---|---|
| **D1** — magnetite capacity / Docker / k3d | OPEN (live check) | CX53 shape internally inconsistent in-repo; requires `ssh magnetite.zt 'nproc && free -h && df -h'` before load-bearing use. Docker not currently enabled (only podman); Phase 4 adds `virtualisation.docker.enable = true` + dedicated ZFS dataset. | research/02 |
| **D2** — hercules-ci-effects + buildbot-nix integration | RESOLVED (HIGH) | Attribute path is fixed at `herculesCI.onPush.default.outputs.effects.<name>`; per-branch paths are ignored. Branch gating via `effects_branches` and `effects_on_pull_requests` in `buildbot-nix.toml` (read from default branch). Secrets via `perRepoSecretFiles` → JSON file → `HERCULES_CI_SECRETS_JSON` inside bwrap sandbox. hercules-ci-effects is currently only a transitive flake-lock pin on vanixiets; Phase 3 entry adds it as a top-level input + flake-parts module. | research/01, 02 |
| **D5a** — per-job secret inventory | RESOLVED (HIGH) | `set-variables`: none. `preview-release-version`: declared `contents: write` but plugin filter removes `GITHUB_TOKEN` consumption. `preview-docs-deploy`: `SOPS_AGE_KEY` (decrypts Cloudflare creds from `secrets/shared.yaml`). `bootstrap-verification`: none. `test-cluster`: `SOPS_AGE_KEY` (for k3d `sops-age-key` Kubernetes secret bootstrap). `production-release-packages`: explicit `SOPS_AGE_KEY` + implicit `GITHUB_TOKEN`. `production-docs-deploy`: `SOPS_AGE_KEY`. | research/03 |
| **D5b** — fork-PR security posture | RESOLVED (HIGH) | No author allowlist, no fork-vs-same-repo differentiation, no Nix sandbox for effects. `effects_on_pull_requests = false` default keeps fork PRs safe. Posture A (keep default) chosen; Posture B (preview/* base-repo branches) named as upgrade path. | research/04 |
| **D5c** — secret pipeline design | RESOLVED (HIGH) | "Sidecar" framing was incorrect; actual model is `perRepoSecretFiles` → systemd `LoadCredential` → JSON file in bwrap. Magnetite follows clan-vars convention (no sops-nix yet) to generate the JSON blob. | research/01, 02 |
| **D7a** — trigger-surface mapping | RESOLVED (HIGH) | See "Trigger translation" section. Two-axis model: Nix attribute path (`onPush.default.outputs.effects`) + `buildbot-nix.toml` config (`effects_branches`, `effects_on_pull_requests`) + `onSchedule.<name>.when` structured submodule + CLI for manual dispatch. | research/01, 05 |
| **D7b** — path-filter audit | RESOLVED (HIGH) | cd.yaml has a single workflow-level `paths-ignore: '*.md'`; no job-level path filters. Translates to `lib.fileset.*` scoping of derivation `src` where desired, or is dropped as trivially handled by nix content-addressing. | research/03 |
| **D7c** — workflow_dispatch substitute | RESOLVED (HIGH) | `buildbot-effects run` is verified: subcommands `list`, `run`, `list-schedules`, `run-scheduled`; flags `--rev`, `--branch`, `--repo`, `--path`, `--debug`, `--secrets`; flakeref syntax supported. Web-UI "Force Build" is only wired to `nix-eval` (whole-evaluation); per-effect "Rebuild" requires prior run. CLI over ZeroTier is primary; Rebuild is secondary; thin GHA shim is fallback-only. Confidence upgraded MEDIUM → HIGH. | research/01, 05 |
| **D8a** — per-job purity confirmation | RESOLVED (HIGH) | See "Per-job purity mapping" table. | research/03 |
| **D8b** — bootstrap-verification rubric | RESOLVED (HIGH) | EFFECT. `make bootstrap` installs nix daemon + `nixbld` users + systemd/launchd units; `make setup-user` writes `~/.config/sops/age/keys.txt`. By construction cannot be a buildbot check; either remains a minimal GHA job gated on bootstrap-relevant paths, or becomes an effect that provisions and tests a fresh worker. | research/03 |
| **D8c** — preview-release-version tag-push resolution | RESOLVED (HIGH) | PURE. Both `scripts/preview-version.sh` and `modules/apps/docs/preview-version.sh` operate in a throwaway worktree with trap-restored local-only `git update-ref`; `@semantic-release/github` plugin is explicitly filtered from `--plugins`; no `git push` anywhere. Classification is check (or package), not pure-effect or split. | research/03 |
| **D8d** — composite-action + reusable-workflow inventory | RESOLVED (HIGH) | Exactly two composite actions: `.github/actions/cached-ci-job/action.yaml` and `.github/actions/setup-nix/action.yml`. Both disappear without replacement. Reusable workflows: `deploy-docs.yaml`, `test-cluster.yaml`, `package-release.yaml` — logic migrates to `modules/apps/`. | research/03 |
| **D9** — rollback posture | RESOLVED (HIGH) | Two classes. Reversible (parity N = 2–3; fast-revert by un-archiving from `.github/deprecated/`; trigger rollback at 1–2 consecutive divergences). Irreversible (parity N ≥ 5; mandatory rollback rehearsal; dual-writer mitigation with semantic-release `dry-run: true` during parity). Automated rollback triggers depend on ntfy observability (D12); without it, detection is eyeball-only. | research/05 |
| **D10** — Ironstar history comparison | DEFERRED (out of epic scope per revision) | Research did not cover. Accretion-vs-load-bearing audit of `cd.yaml` patterns is independent of the migration mechanics and can be deferred. | — |
| **D12** — observability transition | RESOLVED (HIGH) | Tier 1 (per-effect GitHub Commit Status via `FilteredGitHubStatusPush` + `nix_status_generator.py`; each effect posts its own context `effects.<name>`) is sufficient for mission scope. Tier 2 (ntfy `HttpStatusPush` → `https://ntfy.zt/vanixiets-ci-fail` on default-branch failures) is deferred as an operational improvement post-mission. matrix-synapse further deferred behind ntfy. Gap vs GHA: implicit email-on-failure has no default replacement within mission scope; subscribers rely on GitHub Commit Status notifications until ntfy is wired. | research/05 |
| **D13** — cost posture | OPEN (live check) | Depends on D1 CX53-shape confirmation. CX53 at public Hetzner pricing ≈ €14/month; R2 storage ≈ $7.5/month at 500 GB. If live `nproc` shows 8 vCPU / 16 GB, headroom for concurrent k3d effects is tight and CX63 or CCX33 upgrade becomes a consideration. | research/02 |
| **D14** — cached-ci-job hashing | RESOLVED (HIGH) | Hashes `flake.lock` whole via single `git hash-object`; `hash-sources` is a whitespace-separated glob list iterated with `set -f`; `**` expanded via `find -type f -name <last-segment>`; auto-includes workflow file + the action itself; excludes `packages/docs/src/content/docs/notes/*`; key = `job-result-<sanitized-name>-<12-char sha256 prefix>`. | research/03 |

## Organizational shape

Single parent epic with internal clustering. Rejected alternative: parent epic + child epics per domain.

Justification: Phase 4 worker provisioning is cross-cutting across all effectful jobs; Phase 2 per-job branch-point decisions need a single coordination view; a unified "how is the migration going" view matters for duration tracking; dependency coordination via edges is cheaper than epic-metadata overhead.

Estimated duration: 6–12 weeks. With ~90% of discovery resolved (see Resolutions table), the range is anchored on Phase-1/3/4/5 execution time, not discovery outcomes. Phase 4 live CX53 verification may revise the upper bound if capacity forces a server upgrade.

Internal clusters:

- Cluster-domain app conversion (`modules/apps/cluster/`) — 13 recipes/scripts
- Docs-domain app conversion (completion + drift cleanup)
- Release-domain app conversion (`modules/apps/release/`)
- Bootstrap-domain app conversion (`modules/apps/bootstrap/`)
- Flake-level effects wiring (hercules-ci-effects input + flakeModule + `herculesCI` attribute + per-effect declarations)
- Worker provisioning (magnetite NixOS module: docker + ZFS dataset + `perRepoSecretFiles` + optional cgroup isolation; ntfy reporter deferred post-mission)
- Parity validation (per confirmed job, per N-run rubric)
- Sunset + disappearance (per-job removal, composite-action and reusable-workflow deletion, `cd.yaml` archival, drift cleanup per Phase 6 touchpoints)

## Consequences

Positive:

- Self-sovereign CI execution aligned with `nix-7v7` investment.
- Enables `nix-7v7` infrastructure to gate releases, not just evaluate checks.
- Per-effect granular caching via native hercules semantics; no bespoke GHA cache machinery.
- Each effect posts its own GitHub Commit Status context (`effects.<name>`) — observability contract for PR authors is preserved and arguably sharper.
- Domain-organized app layout supports forward-compatible Hetzner production cluster migration.
- `writeShellApplication` + `.sh` sidecar decouples shellcheck hygiene from nix string-templating.

Negative / risks:

- Magnetite becomes CI single-point-of-failure. **Mitigation:** `cd.yaml` is archived in `.github/deprecated/` during Phase 6, not deleted; un-archiving individual jobs restores the GHA fallback path without code rewrites. Rollback acceptance criteria for irreversible jobs (D9) include a mandatory rehearsal.
- Secret-pipeline migration has security-adjacent complexity — fork-PR secret exposure is a real footgun if `effects_on_pull_requests` is ever flipped. Posture A (default off) is the explicit guardrail.
- For irreversible jobs (`production-release-packages`, `production-docs-deploy`), the revert path cannot un-publish artifacts; it can only return publish authority to GHA for subsequent runs. **Mitigation:** dual-writer rule during Phase 5 parity — buildbot's semantic-release runs with `dry-run: true` so only GHA publishes until cutover.
- User-facing observability shifts from GHA UI to `buildbot.scientistexperience.net` with per-effect GitHub Commit Status contexts as the primary feedback channel on PRs. Implicit GHA email-on-failure has **no default replacement within mission scope** (ntfy Tier 2 is deferred as a post-mission operational improvement); subscribers rely on GitHub Commit Status notifications until the ntfy reporter is wired.
- Transient developer-ergonomics cost during hybrid state — PRs show both GHA and buildbot commit-status contexts until Phase 6 completes per job.
- `workflow_dispatch` ergonomics change (CLI substitute instead of GitHub UI). ZT access is required to trigger effects manually; non-admin contributors cannot force-run an effect.
- Effect debug UX is strictly more powerful (`buildbot-effects run --debug`) but strictly less ergonomic than `action-tmate@v3` for non-ZT contributors. Permanent ergonomic cost.
- Fixed-cost posture shift: magnetite (CX53) supersedes GHA's effectively-free public-repo CI capacity. Absolute cost minor at Hetzner pricing, but pending D1/D13 live confirmation, capacity headroom alongside niks3 + buildbot + Gitea + 2 gitea-actions-runner podman instances is not yet quantitatively validated.
- Drift between `.sh` sidecars and legacy copies (`scripts/preview-version.sh`, `package.json:18`, docs reference, deprecated workflow hash-sources) requires active Phase 6 cleanup per enumerated touchpoints.

## Explicit deferrals

- Individual issue bodies and beads IDs — not ADR content.
- Ironstar-style accretion-vs-load-bearing audit (D10) — out of epic scope per revision.
- Per-phase duration estimates beyond the top-level 6–12 week range.
- Posture B adoption (fork-PR preview via `preview/*` base-repo branches) — deferred until contributor preview-feedback becomes a priority.
- ntfy `HttpStatusPush` reporter wiring — operational steady-state concern, deferred as post-mission improvement. Tier 1 (per-effect GitHub Commit Status via `FilteredGitHubStatusPush`) plus PR-based validation (`gh pr checks` + `buildbot-logs`) covers the mission-scope dev loop; the email-on-failure gap is acknowledged under Consequences.
- matrix-synapse reporter wiring — deferred behind ntfy Tier 2 (which is itself post-mission).
- Phase 5 per-job parity validation is a wall-clock observational activity that begins after all mission features complete; the mission does **not** gate on parity confirmation. Parity windows run on calendar time, not on the mission's feature-completion critical path.
- `cd.yaml` archival to `.github/deprecated/`, deletion of the reusable workflows (`deploy-docs.yaml`, `test-cluster.yaml`, `package-release.yaml`), and deletion of the composite actions (`cached-ci-job/action.yaml`, `setup-nix/action.yml`) — deferred until post-mission parity observation completes (Phase 6 depends on Phase 5 exit). The mission as currently scoped stops before Phases 5 and 6 run their full course, though both phases remain the ADR's target end-state.
- Binary-cache poisoning analysis for fork-PR-triggered niks3 uploads — content-addressing makes direct collision attacks infeasible, but trust-in-cache-contents is out of scope.

## References

Codebase:

- GHA workflow authoritative source: `/Users/crs58/projects/nix-workspace/vanixiets/.github/workflows/cd.yaml`
- Reusable workflows: `.github/workflows/test-cluster.yaml`, `.github/workflows/deploy-docs.yaml`, `.github/workflows/package-release.yaml`
- Composite actions: `.github/actions/cached-ci-job/action.yaml`, `.github/actions/setup-nix/action.yml`
- nix-a8g precedent template: `modules/apps/docs/`
- Hermetic-deps derivation shape: `pkgs/by-name/vanixiets-docs-deps/package.nix`
- Legacy preview-version drift: `scripts/preview-version.sh`, `package.json:18`
- Docs-reference drift: `packages/docs/src/content/docs/about/contributing/semantic-release-preview.md`
- Buildbot worker NixOS module: `modules/nixos/buildbot.nix`
- niks3 NixOS module: `modules/nixos/niks3.nix`
- Buildbot-nix project config: `buildbot-nix.toml`
- Magnetite machine config: `modules/machines/nixos/magnetite/default.nix`, `modules/machines/nixos/magnetite/disko.nix`
- Terranix shape declaration: `modules/terranix/hetzner.nix:25-30`
- cinnabar ntfy deployment: `modules/machines/nixos/cinnabar/ntfy.nix`

Research reports (this revision's evidence base):

- `.factory/research/adr-001-validation/01-hercules-effects-buildbot-nix-mechanics.md`
- `.factory/research/adr-001-validation/02-magnetite-state-and-web01-pattern.md`
- `.factory/research/adr-001-validation/03-cd-yaml-inventory.md`
- `.factory/research/adr-001-validation/04-fork-pr-security.md`
- `.factory/research/adr-001-validation/05-ops-triggers-observability-rollback.md`

External sources:

- buildbot-nix upstream: `~/projects/nix-workspace/buildbot-nix/`
  - Effects CLI: `buildbot_effects/buildbot_effects/cli.py`
  - Effects flake-attr reader: `buildbot_effects/buildbot_effects/__init__.py:142-159`
  - Effects dispatch + gating: `buildbot_nix/buildbot_nix/nix_eval.py:596-632`, `708-729`
  - Master module effects options: `nixosModules/master.nix:716-732`, `1010-1040`
  - Scheduled effects: `buildbot_nix/buildbot_nix/scheduled.py`, `models.py:ScheduleWhen`
  - Commit-status generator: `buildbot_nix/buildbot_nix/nix_status_generator.py`
  - Security warning (fork-PR): `README.md:184-190`
- hercules-ci-effects upstream: `~/projects/nix-workspace/hercules-ci-effects/`
  - flakeModule: `flake-modules/herculesCI-attribute.nix`
  - `runIf`: `effects/default.nix:47-63`
- Reference implementation (secret-wiring + niks3/buildbot colocation only — **not** an effects reference): `~/projects/nix-workspace/clan-infra/`
- End-to-end effects-secrets example (codecov token): `~/projects/nix-workspace/mic92-clan-dotfiles/machines/eve/modules/buildbot.nix:50-66`, `~/projects/nix-workspace/harmonia/nix/herculesCI.nix:54-60`
- Origin artifact (caching question that triggered the epic): `./logs/vanixiets-2026-04-21-test-cluster-cache-strategy.txt`

Skills:

- `~/.claude/skills/preferences-nix-ci-cd-integration/SKILL.md`
- `~/.claude/skills/preferences-nix-checks-architecture/SKILL.md`
- `~/.claude/skills/preferences-secrets/SKILL.md`
- `~/.claude/skills/preferences-adaptive-planning/SKILL.md`
- `~/.claude/skills/stigmergic-convention/SKILL.md`
