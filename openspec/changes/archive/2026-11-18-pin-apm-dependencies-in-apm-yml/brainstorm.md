<!--
Raw capture of superpowers:brainstorming output.

This file captures the output of the brainstorming skill verbatim; it does not impose any structure.
The skill's natural output is usually a decision-log format (background → decision chain Q1-Qn → design trade-offs),
but the organization may vary depending on the conversation.

design.md is extracted from this file and reorganized into a structured design document.

Do not copy this file's content into design.md — design.md is an independent, reorganized artifact;
the two are complementary but do not overlap.
-->

# Brainstorm: pin apm dependencies in apm.yml

Path: architectural. The change replaces requirements in `openspec/specs/third-party-plugin-dependency/spec.md` and the archived design decision D11 (`openspec/changes/archive/2026-08-27-apm-skills-marketplace/design.md:99`), touches skill delivery to every harness on every machine, and changes how a dependency bump is done.
The operator reached consensus on the design and on D1-D4 on 2026-11-18, after a spike and two independent verification passes.

## Background

The trigger was the apm 0.35.1 → 0.36.0 bump.
apm 0.36 broke `apm-skills-compose` twice over: its git cache layout changed again (the compose fakes that layout), and it refuses superpowers' hook files outright (F3: `hook filename target routing was removed … APM refused to install these hooks`).
The interim fix (jj change `mnuvowxw`) turned each hand-seeded cache entry into a real git repository with a replace ref and deleted superpowers' `hooks/` from the seed.
It works, but it couples the compose more tightly to apm's private cache.

Stepping back from the fix showed where the duplication is.
For each of the 10 remote dependencies, one fact, the commit to use, lives in three or four places:

| Where | What it holds | Maintained by |
|---|---|---|
| `pkgs/by-name/agent-plugins/*`, `linear-cli.skillSrc`, `playwright-cli.src` | `rev` + `hash` | hand |
| plugin `apm.yml` | `ref:` | hand |
| root `apm.lock.yaml` (plus two stray plugin locks) | `resolved_commit` | apm relock, often stale |
| `apm-skills-compose/package.nix` | 10 copy-pasted pre-seed blocks plus 10 drift checks | hand |

The pre-seed blocks fake apm's private cache layout, which already broke at apm 0.31 and 0.36.
The drift checks exist only to keep copies in sync that need not be separate copies.
And the marketplace install of `planning-and-development` fails today (M1: plain apm 0.36 exits 1 on superpowers' hooks, and agency's `Stop` hook is written into the consumer's `.claude/settings.json`).

## The idea: a deps hash, as Nix does for Rust, npm and Go

`cargoHash`, `npmDepsHash` and `vendorHash` share one shape: the language's own manifest is the only place a human writes what to depend on, a fixed-output derivation lets the language tool download exactly that, and the offline build consumes the download.
Applied here:

- the plugin `apm.yml` files stay the only place a remote dependency's commit is written;
- one fixed-output derivation, `apm-deps-<digest>`, runs `apm lock` with network access and emits `apm_modules` plus a lock covering the remote entries only, under one `apmDepsHash`;
- `apm-skills-compose` runs plain `apm install` offline over that output, with no faked cache.

Rejected alternatives:
- Flake inputs as the source of truth, with `apm.yml` refs generated from `flake.lock`: `apm.yml` is published to marketplace users, so generating it adds a code-generation step and a check on published files.
- Nix selecting the skills itself: it would reimplement apm's skill subsets, `plugin.json` normalization and single-skill repositories, duplicating apm instead of removing duplication.
- Folding the 10 pre-seed blocks into one data-driven loop: the cheap fallback if offline reuse had failed. It keeps the coupling to apm's cache, so it was held in reserve and not needed.

## Spike, then independent verification

A throwaway spike (`/tmp/PROTOTYPE-apm-deps-spike.ZFIP/spike.nix`) answered the feasibility questions; a second agent re-verified every claim on stibnite (aarch64-darwin), and a third closed the sandbox and cross-platform risks on magnetite (x86_64-linux, `sandbox = true`).
Logs are under the repository's git-ignored `logs/` (`apm-verify-*-20261118-*`, `apm-sandboxlinux-*-20261118-*`, `apm-superpowersd1-*`).

| Code | Claim | Status |
|---|---|---|
| U1 | The fixed-output result is reproducible | Holds: two Nix builds and a non-Nix `apm lock` give `sha256-s1hdAZqb…` for the whole output (`q7pjih09…` is `apm_modules` alone, an earlier layout). |
| U2 | The offline consumer matches today's compose | Holds: no git on PATH, a dead proxy, 10/10 remote dependencies `(cached)`, `.agents` tree identical to the current compose, 175 skills equal to `skills.json`. |
| U3 | No second committed lock | Holds, provided every remote ref is a full 40-character SHA; a branch or tag ref would make the download time-dependent. |
| F5 | The consumer runs plain `apm install`, not `--frozen` | Holds. Corrected reason: the `apm lock` output records no deployed files, so `--frozen` fails after deploying (`does not record everything this install deploys`). |
| F6 | Edited downloads are detected and removed | Holds (`apm_cli/install/phases/integrate.py:281-300`: content-hash mismatch, then `safe_rmtree`). So deleting superpowers' `hooks/` from the download cannot carry over. |
| F7 | Narrowing superpowers to `targets: [agent-skills]` | Holds, but loses its skills from `.claude/skills` for marketplace Claude-target users; superseded by D1. |
| R1 | Offline under a real sandbox | Closed on magnetite: the consumer builds with only the Linux sandbox between it and the network; six negative controls fail with `Could not resolve host` or `git executable not found`. The download needs `cacert`, git and a writable `HOME` (ablations S2-S4). |
| R2 | Same hash on x86_64-linux | Closed: byte-identical NARs on x86_64-linux (two builds, one `--rebuild`) and aarch64-darwin, for the spike, the D1 manifest and the full-repo manifest with the D1 lines (`sha256-yc7ryXW1…`). |
| R3 | An apm bump changes the hash | Confirmed: apm 0.34.0 and 0.35.1 give `sha256-17mz…`, 0.36.0 and 0.36.1 give `s1hd…`; the only difference is 130 LICENSE files apm 0.36 carries into each skill directory. Narrower outputs either drop 49 LICENSE files from `.agents/skills` or need apm's normalization reimplemented. Accepted. |
| N1 / R4 | Silent stale reuse when pins change but the hash does not | Demonstrated, then closed by the guard below: Nix reuses a fixed-output path by name and hash, so a forgotten hash bump returned the old output and the consumer failed later with a misleading `git executable not found`. |

## Q1. Where do pins live?

Only in the plugin `apm.yml` files, which both plain apm (marketplace users) and Nix read.
Every remote `ref` is a full 40-character commit SHA, and evaluation fails otherwise.

## Q2. How does a pin change reach the download without anyone remembering the hash?

The stale-reuse guard.
The fixed-output derivation is named `apm-deps-<digest>`, where the digest is the first 32 hex characters of `sha256(toJSON { apm = apm.version; deps = sorted entries; })`.
It is computed at evaluation time from the committed plugin `apm.yml` files only (`readDir`, `readFile`, `pathExists`; no import-from-derivation, proved with `--option allow-import-from-derivation false`).

- Each entry carries every key, not only repository, path and ref: fresh-name probes showed `skills:` and `targets:` change the download (`xpdd…` and `q4BC…` against `s1hd…`).
- Each entry carries its declaring plugin, because the lock's `resolved_by: _local/<plugin>` is part of the content (inferred from the lock field, not probed).
- Comments, entry order and whitespace are excluded; `skills: [...]` is kept as its raw string, so re-flowing a list costs one harmless refetch.
- The parser is a hand-written YAML subset over the two dependency forms in use (`owner/repo[/path]#ref` and `git:` object form) and fails closed on any other shape.
- Proven on stibnite: a ref bump renames the derivation and fails with Nix's hash-mismatch error printing the new hash, even with the old output in the store; an apm version change does the same; unrelated edits (a first-party `SKILL.md`, a description, comments, entry order) keep the name and fetch nothing, and fresh-name probes confirm both variants really produce `s1hd…`, so keeping the name is correct and not merely cheap; `ref: main` and a short SHA fail evaluation.

## Q3 (D1). What happens to superpowers?

apm 0.36 refuses superpowers' hook pair for every hook-capable target, a `skills:` subset does not suppress hooks (E5), a deny declared inside a dependency is ignored (E7), and upstream closed apm support as NOT_PLANNED (obra/superpowers#2681, 2026-11-10).
Options weighed: narrow to `agent-skills` (Claude-target marketplace users lose the skills), drop superpowers from apm (two mechanisms, two pin locations), wait upstream (dead), whole package plus a consumer-side `executables` deny (every marketplace user must set it up first), and per-skill virtual subdirectory dependencies.

Decided: per-skill virtual subdirectory dependencies, `obra/superpowers/skills/<name>#22f0b463e7a5e579904dd6211a520321035526f7` (v7.0.2; the annotated tag object is `c62ffea8…`), one line per skill, 15 skills.
The package root becomes `skills/<name>`, so apm never sees `hooks/`; all 15 skills land in both `.claude/skills` and `.agents/skills`; the install succeeds for every target with no flags; and the two cross-skill links that today's whole-package install rewrites into dangling `../../../apm_modules/...` paths stay as working sibling links.

The same shape fixes agency: `srid/agency/.apm/skills/{hickey,lowy,fact-check}#81455051ccca654c57ad6088838c85e7248ac159` delivers the three skills without agency's `Stop` hook (E10; addendum `a1` versus `f1`).

apm accepts mixed refs across those lines without complaint (E11), so D1 carries a same-ref check: for `obra/superpowers` and `srid/agency`, one ref per repository, every ref a full SHA, no whole-repository entry, every path exactly one skill directory (`skills/<name>` or `.apm/skills/<name>`), and the superpowers list equal to upstream's `skills/` at that ref.
The last rule makes a bump that adds an upstream skill fail loudly instead of silently leaving it out; it does not apply to agency, whose subset is deliberate.

Verified with plain apm 0.36.0 (18 skills in each tree, the trees identical, no hook files, offline install from the `apm lock` output) and under the Linux sandbox (the D1 `apm_modules` hash `dnE0yxlJ…` equal on both platforms).

## Q4 (D2). Agency's subagents and rule

Per-skill agency entries deploy only the skill directories, so agency's `hickey` and `lowy` subagents (thin wrappers that invoke the skills) and its `apm-sources` rule are no longer delivered (H3).
Options: accept the loss; add two first-party wrapper agents; or keep the whole package plus a hook deny, rejected because marketplace users would get the hook back.
Decided: accept the loss. The skills remain. Home-manager delivery reads only `.claude/skills`, so the fleet's own machines lose nothing they use today.

## Q5 (D3). What does the guard key apm on?

- apm's version: no refetch on unrelated flake updates. Residual risk: a same-version apm rebuild whose dependencies change the bytes (for example PyYAML serialization) would not rename the derivation, so a machine holding the old output would reuse it; a cold build elsewhere would then report a hash mismatch rather than stay silent (inferred, untested).
- apm's store-path hash: no such risk, but a refetch and a hash re-confirmation on most nixpkgs, Python or llm-agents bumps.

Decided: apm's version, with the residual risk recorded.

## Q6 (D4). Mergify release alignment

Today `structure-mergify-release-alignment` compares `agent-plugins-mergify-cli.version` with `mergify-cli-bin.version`.
Once the fetcher stops feeding the compose, keeping it only for that comparison makes it a second pin.
Decided: `mergify-cli-bin` records its release's source commit (`passthru.sourceRev`), and the alignment check requires the `apm.yml` ref for `Mergifyio/mergify-cli` to equal it.
Each fact is pinned once, and the release stays declared by the binary.
Alternative not taken: keep the fetcher purely as alignment metadata.

Operator follow-up the same day generalized D4 into one rule for every CLI whose agent skill comes from the same upstream release: the binary's Nix source records the release commit (`mergify-cli-bin.passthru.sourceRev`, `linear-cli.skillSrc.rev`, `playwright-cli.src.rev`), and a structural check requires the `apm.yml` ref to equal it.
Those Nix sources stay only because the CLI builds or `flake.lib.linearSkills` need them, never as a second pin for the skill.
A second follow-up extended the rule to worktrunk and gh-stack, because its value is that it covers every CLI/skill pair from one upstream release, and both pairs already show the drift it prevents.
worktrunk: `worktrunk-bin` is 0.81.0 while the skill is pinned at v0.80.0 (`b49ca7ee…`); tag `v0.81.0` is the lightweight tag on `e42f0f6fef2fdbd98fc92e5cd6c3cbea55b65b38` ("Release v0.81.0 (#4534)"), reachable from `main`, and its `skills/` holds `worktrunk` and `wt-switch-create`.
gh-stack: the CLI is nixpkgs' `gh-stack` 0.3.0, built from `fetchFromGitHub { tag = "v0.3.0"; }` of the same repository, `github/gh-stack`; tag `v0.3.0` is the lightweight tag on `2a49e6751238633db504655d8a8eba3e433e827d`, and the skill's pin `14fc42ed…` is 42 commits behind it (GitHub compare API). Same repository and release line, so it is included; its source records only the tag, so the repository records the commit beside it.
The playwright byte-parity comparison (delivered skill against `playwright-cli.src` at the same commit) moves out of the compose into a structural check.

## Q7. R3

Accepted: some apm upgrades change `apmDepsHash` (one change in four versions observed).
The guard makes the change loud: the derivation is renamed, and the build prints the new hash.

## Q8. What the bump workflow becomes

Edit the `ref:` (all lines of a repository together, for superpowers and agency), then update `apmDepsHash` from the printed mismatch.
`just agents-relock` re-solves the root `apm.lock.yaml` from GitHub `main` (`modules/apps/apm-skills-install.sh`), so it cannot see an unmerged edit; the root-lock refresh stays a post-merge follow-up, as the existing Mergify requirement already states.

## Trade-offs and limits recorded

- The guard's YAML reading is a pattern matcher over two forms; quoted values or inline maps fail evaluation loudly instead of being skipped.
- worktrunk's hooks still reach the composed `.claude/settings.json`, as they do today. Home-manager never consumes that file. Out of scope; noted.
- The `agent-plugins/*` fetchers that other consumers use stay (the Claude Code plugin marketplaces for cognee, cloudflare, dagster, duckdb, huggingface and ouroboros). The eight that only fed the compose or the Mergify check go.
- superpowers' SessionStart bootstrap hook is not delivered, which is already true today (`rm -rf "$CK/hooks"`). Marketplace users who want it install superpowers natively and should not install both.
- The explicit superpowers allowlist means a new upstream skill needs a manifest line; the same-ref check makes the omission fail rather than pass silently.
