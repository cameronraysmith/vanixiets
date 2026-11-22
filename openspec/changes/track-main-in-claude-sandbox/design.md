## Context

`bootstrap-claude-sandbox` (CAM-118, archived 2026-11-21) gave Claude Code cloud sessions the operator's agent environment from one closure pinned in the cloud environment's setup step.
This change makes the environment follow `main` instead, by default, and keeps the pin as an option.
It is the follow-up the operator accepted as Q97 option 1 on 2026-11-22, after Q98 archived the pinned design as delivered.

Sources:
- the archived change `openspec/changes/archive/2026-11-21-bootstrap-claude-sandbox/` (world facts A167–A183, decisions D1–D5 and Q91);
- the Q97 probe of 2026-11-22 00:55 UTC (`logs/claude-sandbox/q97-probe.md`, a local copy; its report branch will be deleted, so the measurements relied on are quoted here and in `specs/world-assumptions` A184–A186);
- #4126 (flake input trim) and #4127 (`checks.x86_64-linux.flake-input-sources`), both on `main`.

### State of the two environments on 2026-11-22

- Default (`env_011CULN8FWHtshNCrzLVdbp4`) runs the generated pinned script for `7c2a300ba97299b7f5c1d4453b3f0225ddaf0e72`, closure `d96f192x7b6r0gwahpdy877nsv2a6ad9-home-manager-generation`, since `bootstrap-claude-sandbox` task 7.2.
- `nix-sandbox-test` (`env_01GcXHMR3GM8Nv2encoaVjvs`) runs session 4's pinned script for `8c41bceba1e75f12c9fb9906eda0d3fa0346dc55`, closure `i6f12svdd7j8xcj85vdk6avimkfzwy0b-home-manager-generation`.

### What the Q97 probe measured

The probe ran in a cloud session on Default (the operator picked it by accident) and changed no environment state, so its result applies directly to the environment tracking targets.

| Step | Result (quoted) |
|---|---|
| Context | `nix (Nix) 2.34.6`; `substituters = https://cache.nixos.org/`; `accept-flake-config = false`; 56 GB free; 15 GiB memory |
| Revision | `nix flake metadata` of `git+https://github.com/cameronraysmith/vanixiets?ref=main&shallow=1` gave `5967d3ab41d4659a9ef37280d018e20dde15aead` in 3.5 s; stderr showed only the shallow git clone (`Receiving objects: 100% (4126/4126), 9.89 MiB`) |
| Lock | 77 distinct locked sources |
| Evaluation | `nix eval --raw` of `homeConfigurations."claude-sandbox@x86_64-linux".activationPackage.outPath`: `elapsed_s=46 peak_VmHWM_kB=964788`, `/nix/store/d96f192x7b6r0gwahpdy877nsv2a6ad9-home-manager-generation`, `rc=0` |
| Sources | 19 `copying path …-source` lines, 18 from `cache.scientistexperience.net` and 1 from `cache.nixos.org`; no `403`, `forbidden`, `unable to download` or `error` line |
| Dry run | `nix build --dry-run` listed nothing to build or fetch, `rc=0` in 8.0 s, because `d96f192x…` was already the installed generation; this step does not show what a changed profile would need |
| Quoting | `O="--option substituters $S …"` expanded unquoted failed with `error: unexpected argument 'cache.scientistexperience.net-1:…'`; `O=(--option substituters "$S" --option trusted-public-keys "$K" --option accept-flake-config false)` worked |
| Git configuration | `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_0`–`_2`, `GIT_CONFIG_VALUE_0`–`_2` set; `/root/.gitconfig` (398 bytes, 22:48) beside `/root/.config/git/config` (the home-manager link, 22:47); `git config --show-origin --get-all ghq.root` gave `file:/root/.config/git/config /home/user/ghq` |

The git-configuration observation left open by `bootstrap-claude-sandbox` is resolved by the last row: the profile's file supplies `ghq.root`, and the harness's own file and three environment overrides carry its commit identity and signing (A186).

### Designation index

Terms are defined in `specs/world-assumptions`, requirement `Grounded vocabulary for behavioral requirements`.
This change adds `main branch` and `input source` (both shared); every other content noun of the behavioral delta resolves to an existing row (the lint is in tasks.md 0.2).
`main` in the interface delta is the git ref `refs/heads/main`, the machine side of `main branch`.

### World facts relied on

| ID | Fact | Status |
|---|---|---|
| A167, A168, A172, A173, A178, A180, A181, A182 | the platform's setup step, snapshot and shell behaviour | observed 2026-11-21 (archived change) |
| A169 | a 360 s setup step is snapshotted | observed once; this change's walk budget relies on it |
| A170 | a non-zero setup exit is fatal | observed; the script still ends in `exit 0` |
| A175 | the GitHub gate refuses archives; anonymous git reads, the channels and the allowlisted caches are served | observed |
| A177 | Nix 2.34.6, root trusted | observed |
| A184 | a session evaluates `main` from the caches in 46 s, without the GitHub gate | observed 2026-11-22 (new) |
| A185 | the platform rebuilds a snapshot after about seven days | documented only (new); task 3.3 measures it |
| A186 | the harness applies its own git configuration beside the profile's | observed 2026-11-22 (new) |

### Assumptions not yet measured, with falsification triggers

| ID | Assumption | Falsified when | Relied on by |
|---|---|---|---|
| T1 | Evaluating each further commit in the walk costs much less than the first, because most input sources are already in the store. | A walk of 5 commits exceeds 300 s with every source cached. | R2 |
| T2 | `git+https://…?rev=<sha>&shallow=1` fetches a commit by SHA through the GitHub gate's anonymous lane (A141 shows GitHub serves it; the gate's lane is A175). | The walk's evaluation of a non-tip commit fails with a fetch error. | R2 |
| T3 | `curl` with the proxy's CA reaches `cache.scientistexperience.net` narinfos from the setup step. | The walk records every commit as `narinfo` misses while the closures are published. | R2 |
| T4 | A snapshot made between a push and nixbot's publish is rare enough that walking back 5 commits covers it. | A snapshot's marker shows all 5 commits missed while the build service was healthy. | R2 |

## Goals / Non-Goals

**Goals:**
- The restated `One closure defines the environment`, `Sessions report how far behind the main branch they are` and `Every input source stays in the binary cache` (`specs/claude-sandbox-bootstrap`).
- Switch `nix-sandbox-test`, then Default, to track mode.

**Non-Goals:**
- Activating a newer `main` during a session.
- Building anything in the cloud session.
- Changing the profile itself.

## Decisions

All decided by the operator on 2026-11-22.

### D1: the setup step evaluates `main` itself — DECIDED 2026-11-22 (Q97 option 1)

- **Choice**: the setup step evaluates `claude-sandbox@x86_64-linux`'s activation package path from `main` over anonymous git, with `cache.scientistexperience.net` and `cache.nixos.org` and their keys as substituters, so every input source is substituted by its narHash (A184).
- **Alternatives withdrawn**:
  - a CI-written pointer branch naming each commit's closure, published by an effect: a third copy of the commit-to-closure function, beside the flake and CI's build;
  - reading nixbot's API for the newest built closure: a new service dependency, coupling the setup step to nixbot's schema.
- **Boundaries**: source-versus-delivered: the setup step consumes the delivered closure; evaluation in the sandbox only names it.

### D2: fixed script text from a track mode of the existing app — DECIDED 2026-11-22

- **Choice**: `nix run .#claude-sandbox-setup-script` gains a track mode that prints fixed text (no revision, store path or date).
  It passes the substituters and keys as a bash array (the probe showed an unquoted string word-splits), activates unless the accepted path is already the current home-manager generation, appends the marker line, and always exits 0.
  An optional `PIN=` line, when set, bypasses evaluation and fetches that store path as the pinned mode does; the pinned mode stays, to produce PIN values.
- **Rationale**: a script change is what triggers an approval card and a snapshot rebuild, so following `main` needs text that does not change per commit.
- **Boundaries**: source-versus-delivered: the script is generated and never committed; the `claude-sandbox-setup-script` check is its regulator, now for both modes.

### D3: substitute only, and walk back `main`'s first-parent history — DECIDED 2026-11-22

- **Choice**: realisation uses `--max-jobs 0` and `--option builders ''`, so nothing is built in the session.
  From `main`'s tip, the step fetches first-parent history to depth 5 (a temporary shallow clone), evaluates each commit's activation package path through `git+https://…?rev=<sha>&shallow=1`, and accepts the first whose narinfo `cache.scientistexperience.net` answers with 200; a failed evaluation counts as a miss (a lock change whose sources are not uploaded yet).
  The walk stops after 5 commits or about 300 s, then the step degrades and activates nothing.
  The marker records the commit used, its distance from the tip and each skipped commit with its reason (`eval` or `narinfo`).
  `PIN=` bypasses the walk.
- **Rationale**: local builds would meet the GitHub gate on fixed-output sources such as the composed skills' dependencies (A175) and could run long; and a snapshot lives about seven days (A185), so losing the push-to-publish race would cost a week of sessions without the profile, not one.
- **Accepted risk**: all 5 commits missing; the marker is its detector.
- **Budget**: 300 s of walk plus about 31 s to realise and activate (session 4) stays inside the 360 s A169 observed; T1 is what keeps 5 evaluations inside 300 s.

### D4: freshness through the snapshot, refreshed by a text edit — DECIDED 2026-11-22

- **Choice**: a tracking environment picks up a newer `main` when its snapshot is rebuilt: on a script-text or allowed-hosts change, or after about seven days (A185, documented, to be measured: task 3.3).
  Refreshing now means any edit to the script text, such as a dated refresh comment, through an approval card or the claude.ai UI.

### D5: a read-only staleness notice — DECIDED 2026-11-22

- **Choice**: a SessionStart hook in the profile compares the commit the snapshot's marker records with `main`'s tip (`git ls-remote`), and appends one `staleness` line to `run.log` with that commit, the distance the marker recorded (for example `main~2`) and whether the tip has moved; it prints nothing, fetches no history and never activates.
- **Alternative rejected**: a catch-up hook that activates `main` at session start: sessions would run with mixed versions, and the catch-up would repeat in every session.

### D6: the 30-day renewal applies only while pinned — DECIDED 2026-11-22

- **Choice**: a tracking environment names no store path, so niks3's 30-day expiry of an unreferenced closure no longer applies to it; the renewal rule stays for pinned environments.

### D7: the input-sources check is load-bearing — DECIDED 2026-11-22

- **Choice**: every lock change must keep all input sources in niks3; `checks.x86_64-linux.flake-input-sources` (#4127) holds them there.
  A miss shows in the setup step's marker as an `eval` miss for that commit, and the hourly cache-completeness timer on magnetite fails if the check's output is not served.
- **Boundaries**: vendored-versus-first-party: the sources are vendored flake inputs; the check is first-party and copies none of them, only references them.

## Risks / Trade-offs

Obstacles, each the negation of a goal:
- [Risk] None of `main`'s 5 newest commits is published when the snapshot is made (negates R2). → Accepted; the marker records every miss, and a script-text refresh retries.
- [Risk] A lock change lands before its sources are in niks3 (negates R2, the input-sources requirement). → D7; the walk skips that commit as an `eval` miss.
- [Risk] Evaluation slows as the flake grows (negates R2 within 360 s). → The marker records seconds per step; T1 and the 300 s bound.
- [Risk] The snapshot outlives `main` by up to a week (negates freshness). → D5's notice, and D4's refresh by a text edit.
- [Risk] The harness shadows a git key the profile relies on (A186). → Re-check per key when the profile adds git settings.
- [Trade-off] A tracking environment changes without an approval card → accepted: each change still passes CI and review before it reaches `main`.

## Satisfaction argument (W ∧ S ⇒ R)

| R | Discharged by S | Resting on W (A) and assumptions (T) |
|---|---|---|
| One closure defines the environment | interface: track-mode text, walk, substitute-only, marker; PIN mode | A175, A177, A181, A184, A185; T1–T4 |
| Sessions report how far behind the main branch they are | interface: the staleness hook, the marker | A167, A172 (hooks run at start, observed as S7 in the archived change) |
| Every input source stays in the binary cache | interface: `Every lock source is in the cache` | A175, A184 |

## Migration Plan

1. Implement the track mode and its check (tasks group 1), and the staleness hook (group 2); land through CI.
2. From a controller session on `nix-sandbox-test`, swap its setup step to the track-mode script (one approval card) and run a cold start from `main` (group 3).
3. Only after a passing cold start there, switch Default the same way (one approval card).
4. Measure the snapshot expiry on one environment (task 3.3).

Rollback: replace the setup step with a pinned script printed by the pinned mode, or set `PIN=` in the track-mode script (one approval card); the snapshot is rebuilt from it.

## Open Questions

- The snapshot's real expiry (A185), measured by task 3.3.
- Whether a walk that reaches `main~4` in practice calls for a deeper or longer walk, judged from the markers once tracking runs.
