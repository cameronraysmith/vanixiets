## Context

`apm-skills-compose` (`pkgs/by-name/apm-skills-compose/package.nix`) composes the 18 first-party apm packages under `modules/home/ai/plugins/` into flat `.claude/skills` and `.agents/skills` trees.
Four of those packages declare ten remote apm dependencies (superpowers, mattpocock/skills, agency, linear-cli and playwright-cli in `planning-and-development`; unslop in `preferences-code-and-collaboration-conventions`; GreptimeTeam/dashboard in `preferences-operations-and-reliability`; worktrunk, gh-stack and mergify-cli in `version-control-and-forge`).
Archived decision D11 (`openspec/changes/archive/2026-08-27-apm-skills-marketplace/design.md:99`) kept the compose offline by pre-seeding apm's git checkout cache from a Nix `fetchFromGitHub` tree per dependency, and required each fetcher rev to equal the `apm.yml` ref.
Ten pre-seed blocks and ten drift checks implement that today (`package.nix:171-363`).

Three things broke the arrangement at apm 0.36.0.
The cache layout changed again (the second break, after 0.31), and the interim fix turned each seed into a real git repository with a replace ref, coupling the compose more tightly to apm internals.
apm refuses superpowers' `hooks.json` plus `hooks-cursor.json` pair for every hook-capable target, so the compose deletes `hooks/` from the seed, and plain `apm install` of `planning-and-development` fails for every marketplace user (M1).
And agency's `skills:` subset still installs agency's `Stop` hook into the consumer's `.claude/settings.json`.

The evidence behind this design was gathered on 2026-11-18 by a throwaway spike and two independent verification passes; logs are under the git-ignored `logs/` directory (`apm-verify-*`, `apm-sandboxlinux-*`, `apm-superpowersd1-*`), and `brainstorm.md` records the decision chain.

| Code | Claim | Status |
|---|---|---|
| U1 | The fixed-output download is reproducible | Holds: two Nix builds and a non-Nix `apm lock` agree on `sha256-s1hdAZqb…` |
| U2 | The offline consumer matches today's compose | Holds: no git, dead proxy, 10/10 `(cached)`, `.agents` identical, 175 skills |
| U3 | No second committed lock | Holds when every remote ref is a full SHA (enforced by D2) |
| F5 | The consumer runs plain `apm install` | Holds: the `apm lock` output records no deployed files, so `--frozen` fails after deploying |
| F6 | Edited downloads are detected and removed | Holds (`integrate.py:281-300`) |
| F7 | Narrowing superpowers to `agent-skills` | Holds; superseded by D3 |
| R1 | Offline under a real sandbox | Closed on magnetite; six negative controls fail as they should |
| R2 | Same hash on x86_64-linux and aarch64-darwin | Closed for the spike, D3 and full-repo manifests |
| R3 | An apm bump can change the hash | Confirmed (0.34/0.35 → `17mz…`, 0.36.x → `s1hd…`); accepted (D7) |
| R4 | Silent stale reuse after a pin change | Demonstrated, then closed by D2 |

Stakeholders: the operator, who bumps dependencies and reviews the diffs; the fleet's machines, which receive the composed skills through home-manager (`modules/home/ai/skills/default.nix` reads only `.claude/skills`); and marketplace users, who run plain `apm install` against `.github/plugin/marketplace.json` packages.

## Goals / Non-Goals

**Goals:**
- Write each remote dependency's commit once, in the declaring plugin's `apm.yml`, read by both plain apm and Nix.
- Remove the compose's dependence on apm's private cache layout, its ten pre-seed blocks and its ten drift checks.
- Make a forgotten `apmDepsHash` update, after a pin or apm change, fail at once with the new hash.
- Make plain `apm install` of every published package succeed for every target with no hook from superpowers or agency.
- Keep every CLI and the agent skill describing it on the same upstream release, with the release declared once by the CLI's Nix source.
- Keep the composed and delivered skill trees identical to today's apart from the intended changes (superpowers v7.0.2 adds `diagnosing-superpowers`; the worktrunk and gh-stack skills move to their CLIs' releases).

**Non-Goals:**
- worktrunk's hooks, which still reach the composed `.claude/settings.json`; home-manager never reads that file.
- Making `apmDepsHash` independent of apm's version (R3; D7).
- Delivering superpowers' SessionStart bootstrap hook, or agency's subagents and rule (D4).
- Changing how first-party packages resolve: the compose keeps listing them as local paths in a generated root manifest.
- The `agent-plugins` fetchers still used by the Claude Code plugin marketplaces (cognee, cloudflare, dagster-skills, duckdb-skills, huggingface-skills, ouroboros).

## Decisions

The operator's 2026-11-18 decisions D1-D4 (named so in `brainstorm.md`) appear here as D3, D4, D5 and D6; D1, D2, D7 and D8 record the design consensus around them.

### D1: pin remote apm dependencies in apm.yml and download them in one fixed-output derivation (supersedes archived D11)

- **Boundary**: vendored versus first-party. Upstream trees are now fetched by apm inside the fixed-output derivation instead of by Nix fetchers; first-party packages stay local path dependencies of the generated root manifest.
- **Choice**: a fixed-output derivation `apm-deps-<digest>` (`outputHashMode = "recursive"`, one `apmDepsHash`) copies every discovered first-party package, writes the same root consumer manifest the compose writes, runs `apm lock -t agent-skills,claude` with network access, removes `apm_modules/_local`, and emits `apm_modules/` plus `apm.lock.yaml` with `generated_at` and `apm_version` deleted and local entries filtered out.
  It needs `cacert`, full `git` (not `gitMinimal`) and a writable `HOME`, all three shown necessary by sandbox ablations S2-S4; the explicit `SSL_CERT_FILE`/`GIT_SSL_CAINFO` attributes are redundant (S1).
  `apm-skills-compose` copies that output next to the generated root manifest and runs plain `apm install --root $out -t agent-skills,claude` with no git on PATH; apm reports every remote dependency `(cached)`.
- **Rationale**: this is the `cargoHash`/`npmDepsHash`/`vendorHash` pattern, in which the language's own manifest is the only place a human writes a dependency, the language tool downloads it, and the offline build consumes the download. U1-U3, F5, R1 and R2 establish that apm supports it.
- **Alternatives considered**: keep D11's cache pre-seed (fragile against apm's private layout, broke twice); fold the pre-seed blocks into one loop (DRY, but keeps the coupling); generate `apm.yml` refs from `flake.lock` (code generation over published files); let Nix select skills (reimplements apm's subsets and `plugin.json` normalization); `--frozen` in the consumer (fails, F5).

### D2: the stale-reuse guard names the download after its inputs

- **Boundary**: source versus delivered. The guard reads committed source manifests at evaluation time so that a changed source can never be served a stale delivered download.
- **Choice**: a pure Nix function, using the compose's plugin discovery (`readDir` plus a `.apm/skills` check), reads each plugin's `apm.yml` with `builtins.readFile`, takes the top-level `dependencies:` → `apm:` block (blank lines, full-line comments and trailing ` # …` comments dropped; `devDependencies` ignored), drops local `./`/`../` entries, and normalizes each remote entry to `{ plugin; repo; ref; <every other key verbatim>; }` from either the `owner/repo[/path]#ref` or the `git:` object form.
  Any other line shape throws.
  Every `ref` must match `^[0-9a-f]{40}$`, or evaluation throws naming the file, the entry and the ref.
  The digest is the first 32 hex characters of `builtins.hashString "sha256" (builtins.toJSON { apm = apm.version; deps = <entries sorted>; })`.
  The same parsed entries feed D3's same-ref rules and D6's alignment check, so the manifests are parsed once.
- **Rationale**: Nix reuses a fixed-output path by name and hash, so without the guard a pin bump or apm bump that forgot `apmDepsHash` returned the old output and the consumer failed later with a misleading `git executable not found` (N1).
  With it, both cases rename the derivation and fail with Nix's hash-mismatch error printing the new hash, even with the old output in the store; unrelated edits keep the name and fetch nothing, and fresh-name probes confirm such edits really produce the same bytes.
  Every key is digested because `skills:` and `targets:` change the download (`xpdd…`, `q4BC…`); the declaring plugin is digested because the lock records `resolved_by: _local/<plugin>`.
  The guard uses only `readDir`, `readFile` and `pathExists` on source paths and `apm.version`, so it needs no import-from-derivation; it was proved with `--option allow-import-from-derivation false`, and in a git flake it reads the git-tracked source.
- **Alternatives considered**: digest only repo, path and ref (reuses stale outputs when `skills:` changes); hash the whole plugins tree (refetches on every first-party skill edit); a YAML parser derivation (import-from-derivation).

### D3: superpowers and agency per skill directory, at one ref per repository

- **Boundary**: vendored versus first-party. The dependency moves from a whole upstream repository to individual upstream skill directories, still unforked and unedited.
- **Choice**: `planning-and-development/apm.yml` declares `obra/superpowers/skills/<name>#22f0b463e7a5e579904dd6211a520321035526f7` for each of the 15 skills at v7.0.2 (`brainstorming`, `diagnosing-superpowers`, `dispatching-parallel-agents`, `executing-plans`, `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `using-superpowers`, `verification-before-completion`, `writing-plans`, `writing-skills`) and `srid/agency/.apm/skills/<name>#81455051ccca654c57ad6088838c85e7248ac159` for `hickey`, `lowy` and `fact-check`, with one comment explaining why the entries are per skill.
  The same-ref check enforces four rules at evaluation time inside D2's guard: one ref per repository across all plugin manifests; every ref a full SHA; no whole-repository entry for either repository; every path exactly one skill directory (`skills/<name>` for superpowers, `.apm/skills/<name>` for agency).
  A fifth rule needs upstream's full `skills/` listing, which neither committed files nor the download hold (inferred: the D1 download held exactly the declared skill directories under `apm_modules/obra/superpowers/skills/`, and every skill was declared there, so whether apm fetches undeclared siblings is untested), so it runs inside the fixed-output derivation, which has network access: after `apm lock`, a blobless fetch of `obra/superpowers` at the declared commit lists `skills/` with `git ls-tree`, and the build fails unless the declared names equal that listing. The step writes nothing into `$out`, so it does not affect the output hash; the digest covers the declared list and the ref, so any change to either reruns it.
- **Rationale**: the package root becomes the skill directory, so apm never sees either repository's hooks; installs succeed for every target with no flags (E9, E10, addendum f1), both trees receive all 18 skills, and the two links today's whole-package form rewrites into dangling `apm_modules` paths stay as working sibling links.
  apm accepts mixed refs across such lines (E11), hence the check; the fifth rule makes a bump that adds an upstream skill fail rather than drop it silently.
- **Alternatives considered**: `targets: [agent-skills]` (Claude-target marketplace users lose the skills, F7); drop superpowers from apm (two mechanisms, two pin locations); wait for upstream (declined, obra/superpowers#2681); whole package plus an `executables` deny (every marketplace user must configure it, and a deny inside a dependency is ignored, E7).

### D4: accept losing agency's subagents and rule

- **Boundary**: source versus delivered. The loss is in what the marketplace delivers; the fleet's delivery reads only `.claude/skills` and loses nothing it uses.
- **Choice**: agency's `hickey`/`lowy` subagents and its `apm-sources` rule are no longer delivered; the three skills remain.
- **Rationale**: the subagents are thin wrappers that invoke the skills.
- **Alternatives considered**: two first-party wrapper agents (more first-party code for little value); whole package plus a hook deny (marketplace users get the hook back).

### D5: the guard keys on apm's version, not its store path

- **Boundary**: source versus delivered.
- **Choice**: the digest includes `apm.version`.
- **Rationale**: observed content changes track apm versions (R3: 0.34.0 = 0.35.1 ≠ 0.36.0 = 0.36.1), while the store path changes on most nixpkgs, Python or llm-agents rebuilds and would force a refetch and hash re-confirmation on most flake updates.
- **Alternatives considered**: the store-path hash, which removes the residual risk below at the cost of those refetches.
- **Residual risk**: a same-version apm rebuild whose bytes differ (for example a dependency's YAML serialization) does not rename the derivation, so a machine holding the old output reuses it; the difference surfaces as a hash mismatch on the next cold build of the download, on any machine without the old output (inferred, untested). Accepted by the operator on 2026-11-18 with no CI `--rebuild` backstop and no task; world assumption A139 records the condition that would void it.

### D6: one release-alignment rule for every CLI whose agent skill comes from the same upstream release (generalizes the operator's D4)

- **Boundary**: vendored versus first-party, at the seam between a vendored CLI binary and the vendored skill describing it.
- **Choice**: for each CLI/skill pair from one upstream release, the CLI's Nix source records the release commit, and a structural check requires the `apm.yml` ref for that repository (read from D2's parsed entries) to equal it.

  | Pair | CLI's Nix source | Recorded commit | Skill ref today → after |
  |---|---|---|---|
  | mergify-cli | `mergify-cli-bin` (release binaries) | new `passthru.sourceRev`, the commit tag `2026.9.16.1` points at | `e7c1ebbc…` (unchanged) |
  | linear-cli | `linear-cli.skillSrc` (`fetchFromGitHub`, also feeds `flake.lib.linearSkills`) | `skillSrc.rev` | `02571d34…` (unchanged) |
  | playwright-cli | `playwright-cli.src` | `src.rev` | `74354ecc…` (unchanged) |
  | worktrunk | `worktrunk-bin` (release binaries, 0.81.0) | new `passthru.sourceRev` = `e42f0f6fef2fdbd98fc92e5cd6c3cbea55b65b38` (lightweight tag `v0.81.0`, reachable from `main`) | `b49ca7ee…` (v0.80.0) → `e42f0f6f…` |
  | gh-stack | nixpkgs `gh-stack` 0.3.0 (`fetchFromGitHub { tag = "v0.3.0"; }`) | a repository overlay adds `passthru.sourceRev` = `2a49e6751238633db504655d8a8eba3e433e827d` (lightweight tag `v0.3.0`) | `14fc42ed…` (42 commits behind v0.3.0) → `2a49e675…` |

  Those Nix sources stay only because the CLI builds or `flake.lib.linearSkills` need them, never as a second pin for the skill.
  For the two release-binary packages and the gh-stack overlay, nothing else ties the recorded commit to the release, so the updaters (`mergify-cli-bin/update.sh`, `worktrunk-bin/update.sh`) resolve the tag's commit with `git ls-remote` and rewrite `sourceRev` and the `apm.yml` ref together, as `linear-cli/update.sh` already does for its ref.
  For gh-stack, whose source nixpkgs owns, the check additionally fetches `github/gh-stack` at `sourceRev` with the hash of nixpkgs' tagged source; equal content proves the recorded commit is the tagged one, and a nixpkgs bump of gh-stack fails that fetch until the overlay is updated. The operator accepted this proof on 2026-11-18; its premise (the tag fetch and the commit fetch share one NAR hash) is the first task of the alignment group, which fails visibly if it does not hold.
  The check module replaces `structure-mergify-release-alignment`: one attribute per pair under a static key set, on x86_64-linux only, each naming both values on failure, plus one negative control that runs the shared comparison on unequal fixtures and passes only when it fails naming both.
  The playwright byte-parity comparison (`diff -r -x LICENSE` of the delivered skill against `playwright-cli.src/skills/playwright-cli` in both trees) moves out of the compose into a structural check over the compose output.
- **Rationale**: each fact is pinned once, and the release stays declared by the binary. worktrunk and gh-stack show the drift the rule prevents: both skills lag the CLIs they describe today.
- **Alternatives considered**: keep `agent-plugins-mergify-cli` purely as alignment metadata (a second pin); apply the rule only to the three pairs checked today (leaves the two drifted pairs unguarded); compare versions instead of commits (a version string does not identify the skill's tree).

### D7: accept that some apm upgrades change apmDepsHash (R3)

- **Boundary**: source versus delivered.
- **Choice**: keep the full apm-produced output and update `apmDepsHash` when an apm upgrade changes it (one change in four versions observed).
- **Rationale**: the only difference between hash classes is the LICENSE files apm 0.36 carries into each skill directory. Stripping them makes the hash stable but silently drops 49 LICENSE files from `.agents/skills`; a raw-upstream-trees download fails for the five `plugin.json` packages, which need apm's normalization already present. D2 turns the change into an immediate, self-describing build failure.
- **Alternatives considered**: strip carried licenses; raw upstream trees plus reimplemented normalization.

### D8: a bump is one reviewed manifest edit plus a hash update; the root lock follows after merge

- **Boundary**: source versus delivered.
- **Choice**: a bump edits the `ref:` (every line of a repository together) and updates `apmDepsHash` from the printed mismatch; for a D6 pair, the CLI's updater makes both edits.
  `just agents-relock` refreshes the root `apm.lock.yaml` only after the change reaches `main`, because `apm-skills-install --relock` resolves the first-party packages from GitHub `main` (`modules/apps/apm-skills-install.sh:9-10,53`) and cannot see an unmerged edit.
  The stray `apm.lock.yaml` files in `planning-and-development/` and `preferences-code-and-collaboration-conventions/` (apm 0.32.0, consumed by nothing in the build or the marketplace path) are removed.
- **Rationale**: the existing Mergify requirement already uses this post-merge relock pattern; the root lock is the producer self-test's input, not the Nix build's.

## Risks / Trade-offs

- [Risk] A same-version apm rebuild produces different bytes and a machine reuses its stale download (D5) → Mitigation: accepted residual risk (operator decisions of 2026-11-18); a cold build on any machine without the old output reports the hash mismatch. No CI `--rebuild` backstop is added.
- [Risk] A future manifest uses a YAML shape the guard does not parse (quoted values, flow mappings) → Mitigation: the guard fails evaluation closed, naming the file; the parser is extended before such a shape is used.
- [Risk] An upstream force-push or deletion makes a pinned commit unfetchable → Mitigation: the fixed-output output stays in the binary caches; a cold rebuild fails loudly, as any Nix fetch would.
- [Risk] `adopt-queue-landing-protocol` (active) verifies upstream `mergify-stack` bytes against `agent-plugins-mergify-cli`, which this change removes → Mitigation: whichever change lands second compares against `apm_modules/Mergifyio/mergify-cli` in the fixed-output output instead; the requirement it adds ("existing release-alignment and offline dependency checks still pass") holds under D6 and D1.
- [Risk] The gh-stack overlay drifts when nixpkgs bumps gh-stack → Mitigation: D6's content-equality fetch fails until the overlay and the skill ref move together.
- [Trade-off] The superpowers allowlist needs a manifest line per upstream skill → accepted: a bump that adds a skill becomes a reviewed diff, and D3's fifth rule fails when one is missing.
- [Trade-off] Marketplace users lose superpowers' SessionStart bootstrap and agency's subagents and rule → accepted (D3, D4); the marketplace README says how to install superpowers natively and not to install both.
- [Trade-off] Fifteen manifest lines repeat one SHA → accepted: apm main rejects YAML anchors (microsoft/apm#3867), and the same-ref check keeps the copies equal.
- [Trade-off] worktrunk's hooks still reach the composed `.claude/settings.json` → accepted and out of scope; home-manager reads only `.claude/skills`.

## Migration Plan

1. Land the guard and the fixed-output derivation beside the current compose, and prove D2's properties with mutants on both systems.
2. Rewrite the compose as the offline consumer, switch the manifests to D3's lines and the worktrunk and gh-stack refs to D6's commits, regenerate `skills.json`, and confirm the composed trees differ from today's only by the intended changes.
3. Replace the Mergify alignment check with D6's module and the playwright parity check; record `sourceRev` and update the updaters.
4. Remove the eight retired fetchers, their `compose.nix` options and the stale comments; remove the stray plugin locks.
5. Activate on stibnite (nix-darwin) and on a NixOS host, and compare the delivered `~/.claude/skills` before and after.
6. After merge, run `just agents-relock` and commit the refreshed root lock.

The change reaches each machine at its next activation; no host's shared data changes. Rollback is reverting the change: the retired fetchers and the pre-seed compose return with it, and the binary caches still hold the previous compose output.

## Open Questions

None. The operator settled the questions raised during drafting on 2026-11-18: no CI `--rebuild` backstop (D5); the gh-stack proof as proposed, with its premise checked first (D6); and the apm and GitHub behaviours recorded as world assumptions A136-A141, each with a revisit trigger. The interaction with `adopt-queue-landing-protocol` stands as recorded under Risks.
