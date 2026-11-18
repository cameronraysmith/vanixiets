---
linear_story_id: 87427573-4d17-43f0-8b6c-c56979c4c089
linear_story_identifier: CAM-110
linear_story_title: "Pin apm dependencies once, in apm.yml"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-110/pin-apm-dependencies-once-in-apmyml
linear_story_state: In Review
linear_team: CAM
linear_project: pi-agent-environment
last_synced_state: In Review
last_synced_at: 2026-11-18T19:51:09Z
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-18T17:42:09Z", transition: "Backlog->Todo", outcome: "posted", note: "T1 bind: issue created in CAM and project Agent environment (d7d743a19249), description seeded from proposal.md, moved to Todo, one comment posted; state confirmed by read-only API" }
  - { at: "2026-11-18T19:50:40Z", transition: "Todo->In Progress", outcome: "observed", note: "T2: Linear already read In Progress at verify; the write was made outside this ledger and posted no comment" }
  - { at: "2026-11-18T19:51:09Z", transition: "In Progress->In Review", outcome: "posted", note: "T3 on verify.md (PASS WITH WARNINGS): state set by name, one comment posted, In Review confirmed by read-back" }
---

## Why

Each remote apm dependency's commit is written in three or four places: a Nix fetcher's `rev` and `hash`, the plugin `apm.yml` ref, the root lock, and a hand-seeded cache block in `apm-skills-compose`. Ten drift checks hold the copies together, and the seeding fakes apm's private cache layout, which broke at apm 0.31 and again at 0.36. The marketplace install of `planning-and-development` fails today because apm 0.36 refuses superpowers' hooks, and agency's `Stop` hook leaks into consumers' settings. A spike and two independent verifications (2026-11-18, both platforms, real sandbox) showed apm can download its own dependencies reproducibly in one fixed-output derivation and install offline from it. Pinning once in `apm.yml` removes the copies, the drift checks and the cache coupling together.

## What Changes

**Where a remote dependency's commit is written**
- From: the commit is written in the plugin `apm.yml` and again in a `pkgs/by-name/agent-plugins/*` fetcher (or `linear-cli.skillSrc`, `playwright-cli.src`); the compose pre-seeds apm's cache from the fetcher and fails when the two disagree.
- To: the commit is written only in the declaring plugin's `apm.yml`, as a full 40-character SHA. One fixed-output derivation downloads exactly what apm resolves, under one `apmDepsHash`; its name digests every remote entry and apm's version, so a changed pin cannot reuse a stale download. The compose installs offline from that download.
- Reason: one fact, one place, read by both plain apm and Nix; no dependence on apm's private cache layout.
- Impact: non-breaking for delivered skills; the eight fetchers that only fed the compose or the Mergify check are removed; the compose's ten pre-seed blocks and drift checks are removed.

**How superpowers and agency are consumed**
- From: whole-repository dependencies; superpowers at v6.3.0 with its `hooks/` deleted from the Nix seed, agency with a `skills:` subset that still installs its `Stop` hook.
- To: one virtual-subdirectory dependency per skill directory, at one shared ref per repository: superpowers v7.0.2 (15 skills), agency's `hickey`, `lowy` and `fact-check`. A same-ref check enforces one full SHA per repository, skill-directory paths only, and the superpowers list equal to upstream's `skills/` at that ref.
- Reason: apm never sees either repository's hooks, so plain `apm install` succeeds for every target and installs no hook from either.
- Impact: marketplace installs work again and gain `diagnosing-superpowers`; agency's `hickey`/`lowy` subagents and `apm-sources` rule are no longer delivered (the skills remain); superpowers' SessionStart bootstrap stays undelivered, as today.

**CLI and skill release alignment**
- From: one check compares the Mergify fetcher's version with `mergify-cli-bin`'s; the compose compares the linear-cli and playwright-cli refs with their Nix sources; worktrunk and gh-stack have no alignment, and both skills lag their CLIs today.
- To: for every CLI whose agent skill comes from the same upstream release (mergify-cli, linear-cli, playwright-cli, worktrunk, gh-stack), the CLI's Nix source records the release commit and a structural check requires the `apm.yml` ref to equal it. The playwright byte-parity comparison moves out of the compose into a structural check.
- Reason: the release stays declared once, by the binary, and the skill cannot silently drift from the CLI it documents.
- Impact: the worktrunk skill moves to v0.81.0 and the gh-stack skill to v0.3.0, matching their CLIs.

**How a dependency is bumped**
- From: edit the fetcher, the `apm.yml` ref and the compose's expectations together, then relock.
- To: edit the ref (all of a repository's lines together), update `apmDepsHash` from the printed mismatch; `just agents-relock` refreshes the root lock after the change reaches `main`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `third-party-plugin-dependency` (stratum: `interface`): remote dependencies are pinned in the declaring plugin's manifest and fetched by one guarded fixed-output download; superpowers and agency are consumed per skill directory at one ref per repository; CLI and skill release alignment covers every same-release pair; a bump is one reviewed manifest edit plus a hash update. Supersedes archived design decision D11.
  Trust boundary: evaluation and build results establish where pins are written, that a changed pin or apm version renames the download, that the compose installs offline from it, which skills and hook files the composed trees contain, and that each CLI's recorded release commit equals the skill ref. They do not establish that an upstream commit is benign, that a same-version apm rebuild produces the same bytes, that a marketplace user's own apm and harness behave as tested, or that a harness loads the delivered skills.
- `world-assumptions` (stratum: `world`): adds A136-A141, the apm 0.36.x and GitHub behaviours the interface requirements rest on (offline install from a locked `apm_modules`, the virtual-subdirectory dependency form, removal of edited packages, version-bound download bytes including carried LICENSE files, the `apm lock` shape, and GitHub's shallow fetch by SHA). Each is voided when the pinned apm leaves 0.36.x before its evidence is re-run, or when the behaviour is observed to change.

## Impact

- `pkgs/by-name/apm-skills-compose/`: new fixed-output derivation and evaluation-time guard; compose rewritten as an offline consumer; `skills.json` regenerated.
- `modules/home/ai/plugins/{planning-and-development,version-control-and-forge}/apm.yml`: per-skill superpowers and agency lines; worktrunk and gh-stack refs moved to their CLIs' release commits; comments rewritten to the new mechanism.
- `pkgs/by-name/agent-plugins/{superpowers,agency,worktrunk,mattpocock-skills,unslop,gh-stack,greptimedb-dashboard,mergify-cli}`: removed. The remaining six stay for the Claude Code plugin marketplaces.
- `modules/home/ai/skills/compose.nix`, `modules/home/ai/claude-code/default.nix`: source and rev options and comments removed.
- `pkgs/by-name/{mergify-cli-bin,worktrunk-bin,linear-cli}`, a `gh-stack` overlay, and their updaters: record and rewrite the release commit.
- `modules/checks/structure/`: the Mergify alignment check becomes one CLI/skill release-alignment module over five pairs, plus a playwright byte-parity check.
- `modules/home/ai/plugins/README.md`, `.github/plugin/marketplace.json` consumers: marketplace notes on the per-skill superpowers dependency and the absent hook.
- Root `apm.lock.yaml` relocked after merge; the two stray plugin-directory locks removed.
- Out of scope: worktrunk's hooks, which still reach the composed `.claude/settings.json` that home-manager never reads.
