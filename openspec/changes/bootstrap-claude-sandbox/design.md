## Context

A Claude Code cloud session runs in a container on Anthropic's platform, started from claude.ai/code, the command line or another cloud session.
It starts without the operator's user context, skill corpus or required tools, and the GitHub gate refuses every `github:` flake input, so the main flake cannot be evaluated there.
This repository already generates the user context (`programs.agents-md` with `agent-context`), composes the skill corpus (`apm-skills-compose`, delivered by `ai-capabilities`), packages the required tools, compiles repository context (`apm-context-compile`), and runs a sandbox profile without systemd (`ubuntu@x86_64-linux`, bootstrapped by `home-bootstrap`).
The change delivers those to cloud sessions through one pinned setup line, and records what the platform was measured to do.

Sources:
- the record of session 99972732 (2026-11-21), cited as V*, C*, G*, O*;
- probe session 1 (19:12) and probe session 2 (19:22–19:36) in cloud environment `nix-sandbox-test`, whose scripts and prompts are in `logs/claude-sandbox/` (`setup-v0.sh`, `setup-v1{a,b,c}.sh`, `prompt-session{1,2}.md`), and whose probe flake is `bootstrap/claude-sandbox` on branch `claude-sandbox-dev` at `7fffbd2c2464f7663348fde7882541b430507714`;
- a prior-art survey (PA1–PA6 below);
- a read-only map of this repository's machinery (M1–M8 below).

The measurements this design relies on are quoted in `specs/world-assumptions` (A167–A179) rather than linked, because the probe report branches are scratch branches that will be deleted.

### Stakeholders

The operator, who uses cloud sessions and approves every environment change.
The `ubuntu` profile's users (Devin sandboxes), whose profile D1 refactors.

### Designation index

The terms are defined in `specs/world-assumptions`, requirement `Grounded vocabulary for behavioral requirements`; this table is the index for this change.

| Term | Status | Note on the nix-versus-world ambiguity |
|---|---|---|
| cloud session | shared | not the `session` rows (autonomous episode, Pi's stored record) |
| cloud environment | shared | the platform's named definition, not a nix `environment` attribute |
| container | shared | the platform VM, not an OCI container or `modules/checks/containers.nix` |
| setup step | shared | the platform's script slot; the one pinned line lives there |
| environment snapshot | shared | the platform's disk copy, not `automatic snapshot` (ZFS) |
| first prompt | shared | |
| user context | shared | world sense; the machine artifact is `~/.claude/CLAUDE.md` from `programs.agents-md` |
| skill corpus, skill | shared | world sense; the machine artifact is `apm-skills-compose`'s output |
| required tool | shared | |
| agent's shell | shared | |
| attached repository | shared | |
| repository context | shared | world sense; the machine artifact is a repository's `AGENTS.md`/`CLAUDE.md` |
| harness-owned state | shared | |
| GitHub gate | world-only | |
| pinned revision | shared | |
| bootstrap run, bootstrap report | shared | |
| controller session, approval card, operator action | shared, shared, world-only | |
| Linear workspace | world-only | |
| profile | — | used here only in the nix sense: a home-manager configuration, `homeConfigurations."<name>@<system>"`; never a world term in the specs |
| operator, secret, operator credential, binary cache, working tree, overlay network | existing rows | reused unchanged |

### World facts (indicative), with evidence

Each is stated in full, with its evidence and violation condition, in `specs/world-assumptions`.

| ID | Fact | Evidence |
|---|---|---|
| A167 | Setup-written `/root/.claude/CLAUDE.md` and `/root/.claude/skills/<n>/SKILL.md` are loaded and listed in the first prompt. | Session 1 P3; session 2 children A, A2, B, B2 each reported the context marker loaded and the skill listed and loaded. |
| A168 | Later sessions start from the environment snapshot without running setup, about 10 s after `create_session`. | A2 (booted 19:23:32, one setup run 19:22:17–19:22:52); B2 (booted 19:32:44, one run 19:25:26–19:31:27). |
| A169 | A 360 s setup is not cut off and is snapshotted; the documented ~5 min bound is contradicted; the real ceiling is unknown. | B: `nix_run_rc=0 secs=360`, agent at 19:31:35; B2 started from it. |
| A170 | Non-zero setup exit is fatal: `last_init_error` "Setup script failed", `recoverable=false`, Claude never starts; `CCR_SETUP_SCRIPT_FAILURE_CONTINUES` did not change it. | D: exit 3 at 19:34:36, pending through 19:35:42, `num_turns=0`. |
| A171 | Setup runs twice on first use: in the session container and in a checkpoint builder (`setup_source=building_checkpoint`). | A's run ended 19:22:40; the snapshot's run started the same second and ended 19:22:52. |
| A172 | Setup runs as root, cwd `/home/user`, after attached repositories are cloned, and cannot read variables or secrets. | Session 1 P6 `id=root pwd=/home/user repos=/home/user/vanixiets/`; C7. |
| A173 | The agent's shell is non-login from a shell snapshot; `/etc/profile.d` and `.bashrc` do not reach it; `CLAUDE_ENV_FILE` is unset outside hooks; `NIX_PROFILES` and `NIX_SSL_CERT_FILE` are set; `USER` is unset. | Session 1 P4. |
| A174 | One filesystem, about 64 GB free; a 35 GB write succeeded. | Session 1 P9. |
| A175 | `github:` inputs are refused by the GitHub gate; anonymous git smart-HTTP works; registry `nixpkgs` resolves to channels.nixos.org; allowlisted caches answer. | V11, V12, V22; session 1 P8. |
| A176 | A pinned `nix run git+https://github.com/cameronraysmith/vanixiets?rev=<sha>&shallow=1&dir=bootstrap/claude-sandbox` ran in setup in 23 s (50 paths, 30.6 MiB from cache.nixos.org). | Session 2 A. |
| A177 | Nix 2.34.6, nix-installer, no daemon, local store, `trusted-users = root`, only cache.nixos.org configured. | V8, V13, V14; session 1 P6. |
| A178 | The platform owns `launcher-settings.json` (edit denied), its hook scripts, `skills/session-start-hook` and `skills/synced` (rewritten at boot); setup-written files beside them survive. | V6, C18; A2's `synced` at 19:23:38 against its skill at 19:22:52. |
| A179 | A controller session can `create_session`, swap the setup script with `update_environment` (one approval card each) and read pushed reports; sessions push new branches of any name. | Session 2 controller; session 1 pushed `claude/sandbox-reports` and `sandbox-reports-plain`. |

The proxy re-terminates TLS and its CA is in the system bundle Nix uses (V15, C3); this is relied on by every fetch but is not separately listed.

### Prior art (PA) and machinery (M) relied on

- PA1: mizchi/vibe-lang and kumewata write `PATH` into `CLAUDE_ENV_FILE` from a SessionStart hook gated on `CLAUDE_CODE_REMOTE`.
- PA2: standalone home-manager activates as root in a container when `USER` is set (home-manager issue 3944; kumewata); its systemd reload step skips when no user manager runs.
- PA3: reports from 2026-03 to 2026-09 describe different preinstalled Nix installers and profile paths, so the base image drifts.
- PA4: the gate strips user `Authorization` headers on GitHub requests (claude-code issue 86828), so Nix `access-tokens` cannot pass it.
- PA5: locked flake inputs can be substituted by narHash (Nix 2.32+; V21 shows it from a `file://` cache).
- PA6: the registry `nixpkgs` entry avoids GitHub entirely (also A175).
- M1: `programs.agents-md` (option module `agents-md`, content module `agent-context`) writes the user context to `~/.claude/CLAUDE.md` and seven other harness paths, with no platform dependency.
- M2: `ai-capabilities` (`agent-settings`, `ai-skills-compose`, `ai-skills`, `playwright-cli`) delivers the skill corpus without sops; Claude Code skills land only when `programs.claude-code.enable` is true, one directory per skill under `~/.claude/skills/`.
- M3: the composed skill corpus needs github at build time through a fixed-output derivation unless it is substituted.
- M4: the devshell and `apm-context-compile --auto` choose the repository-context tier by whether `$HOME/.claude/CLAUDE.md` exists, so with the user context present the repository context holds only the repository's own tier.
- M5: `ubuntu@x86_64-linux` handles a root-less, systemd-less sandbox (bash off, ssh-agent off, C.UTF-8, `sopsInstallWithoutSystemd`, sops on `/dev/shm`, a `session-env.sh` hook seeded from `SOPS_AGE_KEY`), but imports neither `agents-md`, `agent-context` nor `ai-capabilities`, and lives at `/home/ubuntu`.
- M6: the `ai` aggregate assumes macOS paths and declares sops secrets for MCP servers and wrappers; it does not evaluate without them.
- M7: `modules/home/ai/claude-code/hooks.nix` calls hook commands by bare name.
- M8: the skills' required tools (see the spec's `Required tools present`); bd and but are installed by no module; wt, hunk, tuicr and herdr need a live TUI; cb and the fleet commands cannot work in a cloud session.
- M9: the Linear skills require `~/.config/linear/credentials.toml` with a default workspace and refuse to run when `LINEAR_API_KEY` or `LINEAR_WORKSPACE` is set; `mkLinearCredentialsTemplate` renders that file from sops secrets, as `crs58` and `ubuntu` do.

### Assumptions not yet measured, with falsification triggers

| ID | Assumption | Falsified when | Relied on by |
|---|---|---|---|
| S1 | The snapshot is rebuilt when the setup script or allowed hosts change and expires after about seven days (C12, documented). | A session after a script change starts from the old snapshot, or a snapshot outlives the documented expiry with stale content the operator did not expect. | R2 |
| S2 | Home-manager activation as root, with `USER` exported and no systemd, completes (PA2). | The first bootstrap run's activation exits non-zero or its report shows a skipped required step. | R1, R12 |
| S3 | Root, as a trusted user, can name `cache.scientistexperience.net` and its key with `--option` and substitute from it (A177, V21). | The first bootstrap run's substitution refuses the substituter or the signature. | R1, R4 |
| S4 | The activation package's store path does not depend on the bootstrap sub-flake's pointer file or on the commit, so a revision can carry its own pointer. | The pointer check fails on a commit that changes only the pointer. | R2 |
| S5 | The profile's closure, substituted and activated, fits the 360 s and 64 GB measured bounds. | The first bootstrap run exceeds 360 s or the disk fills. | R4 |
| S6 | `/root/.nix-profile/bin` (or the profile home-manager activates) is on the agent's shell PATH (PA1 found it was not, in 2026-09). | Probe P4 shows it missing. | R12 |
| S7 | A SessionStart hook declared in a setup-written `~/.claude/settings.json` runs in cloud sessions, and `CLAUDE_ENV_FILE` is set inside it (PA1, C13). | Probe P4 shows the hook did not run. | R8, R14 |
| S8 | The environment's variables, including `SOPS_AGE_KEY`, are present in the processes of a cloud session, hooks included (C7: "Variables … apply the next time the session starts"). | The first D5 session's hook finds `SOPS_AGE_KEY` unset. | R14 |
| S9 | `api.linear.app` is reachable once added to the cloud environment's allowed hosts; it is absent from the current list (V31). | `linear auth whoami` fails with a proxy denial after the host is added. | R14 |
| S10 | The platform's proxy forwards the Linear CLI's own `Authorization` header to `api.linear.app` (PA4 concerns GitHub only). | `linear auth whoami` returns an authentication error with a correct key. | R14 |

### Probe P4 (open; runs within the first bootstrap test)

P4 measures, in one cloud session started on the first bootstrap revision:
the agent's shell `PATH` and whether each required tool runs by bare name;
whether a SessionStart hook declared in the setup-written `~/.claude/settings.json` runs, with its `PATH` and whether `CLAUDE_ENV_FILE` is set inside it;
whether a variable set on the cloud environment is visible to the hook and to the agent's shell (names only).
P4 gates D3's hook wiring and settles S6, S7 and S8.

## Goals / Non-Goals

**Goals:**
- R1–R14 in `specs/claude-sandbox-bootstrap`, on the operator's personal cloud environments.
- A development loop driven by a controller session (R10).

**Non-Goals:**
- Self-hosted environments (`ccpool_…`), which are Team and Enterprise only.
- Fleet access from cloud sessions: SSH, ZeroTier hosts, clan commands, the shared reference tree.
- TUI and clipboard tools (herdr, hunk, tuicr, wt, cb), bd and but.
- Secrets other than the Linear workspace keys; MCP servers that need secrets.
- Evaluating the main flake inside a cloud session.
- A warm devshell for attached repositories in this change (R8 names it as a later option).

## Decisions

All five decisions were authorized by the operator on 2026-11-21 as recommended.

### D1: a `claude-sandbox` profile and a shared `sandbox` aggregate — DECIDED 2026-11-21

- **Choice**: a new home configuration `claude-sandbox@x86_64-linux` (username `root`, home `/root`) importing `agents-md`, `agent-context`, `ai-capabilities`, a sandbox-safe subset of the Claude Code module that enables `programs.claude-code` so skills land, and the required-tool set of R12.
  The parts of `modules/home/users/ubuntu/default.nix` that handle a systemd-less sandbox (bash off, ssh-agent off, C.UTF-8, `sopsInstallWithoutSystemd`, the tmpfs sops directory and the session hook) move into a shared `sandbox` aggregate that `ubuntu` and `claude-sandbox` both import, parameterised by the tmpfs directory name.
  The identity defaults (`/home/<user>`) are overridden for root; `flake-shape.nix` gains `claude-sandbox@x86_64-linux`.
- **Rationale**: M5 and M6: `ubuntu` lacks the agent modules and lives at `/home/ubuntu`; `ai` does not evaluate without crs58's secrets.
  Factoring keeps one copy of the sandbox handling (R13).
- **Alternatives considered**: extend `ubuntu` (changes Devin's profile and keeps the wrong home and secret declarations); import `ai` with stub secrets (macOS paths and MCP servers would still be wrong).
- **Boundaries**: source-versus-delivered: the profile is source; the activation package is what cloud sessions receive.
  Vendored-versus-first-party: the skill corpus keeps its vendored skills exactly as composed for other hosts; no vendored skill is edited.
  `ubuntu`'s activation package should be unchanged by the refactor except for store-path churn; that is checked, not assumed.

### D2: CI-built activation package, substituted by a pinned bootstrap sub-flake — DECIDED 2026-11-21

- **Choice**: one `checks.x86_64-linux` attribute builds `claude-sandbox@x86_64-linux`'s activation package, so nixbot builds it and its binary-cache uploader publishes it to `cache.scientistexperience.net`.
  `bootstrap/claude-sandbox` (channels-only input, as in the probe flake) carries a generated pointer file holding that store path; a check fails when the pointer differs from the evaluated store path.
  The bootstrap app realises the store path with `cache.scientistexperience.net` and its key passed as options, exports `USER=root`, runs the activation, writes the bootstrap report under `/var/log/claude-sandbox-bootstrap/`, and exits 0 on every path.
  The setup step is one line: `nix run "git+https://github.com/cameronraysmith/vanixiets?rev=<sha>&shallow=1&dir=bootstrap/claude-sandbox"; exit 0`.
  No evaluation of the main flake and no secret in the sandbox.
  On a cache miss or any failure, it degrades: it activates nothing partial, writes a report naming the failure, and exits 0.
- **Rationale**: A175 rules out `github:` inputs; A176 shows the outer half works in 23 s; prefetching 94 inputs and evaluating cost 75 s plus 37 s and three inputs mismatched (V18–V20), and M3 would still need github for the skill corpus.
  A170 makes exit 0 mandatory.
- **Alternatives considered**: prefetch and evaluate in the sandbox (slow, GitHub-dependent, mismatches); a branch ref instead of a revision (never invalidates the snapshot, S1); an environment variable as the revision switch (setup cannot read variables, A172).
- **Boundaries**: source-versus-delivered: the pointer file is a generated, committed artifact derived from the profile; it is never edited by hand, and the check is its regulator.

### D3: repository context from a SessionStart hook — DECIDED 2026-11-21 (wiring gated on P4)

- **Choice**: the profile declares a SessionStart hook that, for each attached repository under `/home/user` with an `apm.yml`, runs `apm-context-compile --auto` from the activated closure.
  With the user context present it compiles only the repository's own tier (M4, R9).
  The hook always exits 0 and appends its outcome to the session's bootstrap report.
- **Rationale**: attached repositories differ per session, so this cannot be in the snapshot; the devshell cannot be entered without evaluating the repository's flake.
- **Alternatives considered**: compile in the setup step (attached repositories are cloned before setup, A172, but the snapshot would carry one session's repositories to the next); commit generated context to every repository (duplicates the user tier for repositories without it).
- **Boundaries**: source-versus-delivered: the compiled `AGENTS.md`/`CLAUDE.md` are generated in the attached repository's working tree and are not committed by the hook.

### D4: hooks call absolute store paths — DECIDED 2026-11-21

- **Choice**: `modules/home/ai/claude-code/hooks.nix` refers to each hook command by its store path instead of a bare name.
- **Rationale**: M7 and A173: the agent's shell and hooks may not have the profile on PATH; a missing command breaks every tool call.
  The change also makes local hosts independent of PATH order.
- **Alternatives considered**: write PATH through `CLAUDE_ENV_FILE` (only reaches the agent's shell, not every hook context, and depends on S7).

### D5: a scoped age recipient and sops file for the Linear workspace keys — DECIDED 2026-11-21

- **Choice**:
  - a dedicated age recipient `claude-sandbox-user`, derived like `ubuntu-user` with ssh-to-age from a new Bitwarden SSH key `sops-claude-sandbox`;
  - the operator creates the key and supplies only the public recipient; its private key goes straight into the cloud environment's `SOPS_AGE_KEY` variable and never passes through chat or the clipboard;
  - done by the operator on 2026-11-21: `claude-sandbox-user` = `age1sfddwr9waenu8du9mpxj7l4cfz7w3pkng4tc6xk4k4z09wj9tu8smr9xcf` (public), derived from `sops-claude-sandbox.pub`, and `SOPS_AGE_KEY` set in `nix-sandbox-test`; adding the recipient to `.sops.yaml` and encrypting the file are implementation steps run on stibnite with the admin key;
  - a scoped file `secrets/home-manager/users/claude-sandbox/secrets.yaml`, encrypted to `admin`, `admin-user` and `claude-sandbox-user`, holding only the Linear workspace keys (`linear-api-key-{personal,work}`, `linear-workspace-{personal,work}`);
  - the profile renders `~/.config/linear/credentials.toml` with `mkLinearCredentialsTemplate`, decrypting at session start through the `sandbox` aggregate's session hook into `/dev/shm`, as `ubuntu` does (M5, M9);
  - `api.linear.app` is added to the cloud environment's allowed hosts (S9);
  - revocation removes the recipient from `.sops.yaml` and re-encrypts that one file, then clears the variable.
- **Exposure**: the private key is readable by the model and by every process in every cloud session on that environment, and it decrypts every value in the scoped file.
  The file therefore holds nothing but the Linear workspace keys, so a disclosure exposes those keys and nothing else; the keys can be rotated in Linear.
- **Rationale**: M9: the Linear skills need a local credentials file and refuse `LINEAR_API_KEY`, so platform network secrets (header injection) cannot serve them.
  The setup step cannot read secrets (A172), so decryption happens at session start, and R6 forbids writing them to disk.
- **Alternatives considered**: no secrets in the first version (leaves the Linear-bound workflow unusable); network secrets (rejected by M9); reusing `ubuntu-user` (would expose Devin's secrets, which include signing keys).

## Risks / Trade-offs

Obstacles, each the negation of a goal:
- [Risk] The platform rewrites or claims files under `~/.claude` that the profile writes (negates R1, R5). → Mitigation: the profile writes only `CLAUDE.md`, per-skill directories and `settings.json`, none of which the platform was seen to own (A178); the bootstrap report lists harness-owned paths before and after, and a session-start line checks the user context is still present.
- [Risk] The activation package misses the cache (negates R1, R4). → Mitigation: D2's check makes it a CI output on every revision; the pointer check stops a stale pointer from merging; the bootstrap degrades and reports.
- [Risk] The setup step exits non-zero (negates R3). → Mitigation: the line ends in `exit 0`, the app wraps every step, and a deliberately broken revision is part of the integration tests.
- [Risk] Hook commands are not on PATH (negates R8, R14). → Mitigation: D4; P4 measures it before D3's wiring is relied on.
- [Risk] The snapshot holds a stale pointer (negates R2). → Mitigation: the pointer is in the pinned revision, a revision change is a setup script change, and a setup script change rebuilds the snapshot (S1); the bootstrap report records the revision it ran.
- [Risk] The closure exceeds the measured 360 s (negates R4). → Mitigation: measure in the first bootstrap test; trim the tool set before raising the bound.
- [Risk] The base image's Nix changes (A177, PA3). → Mitigation: the report records `nix --version` and the configuration it saw.
- [Trade-off] The age key is readable by anything in the session (D5) → accepted because the file it opens is scoped to keys the operator can rotate.
- [Trade-off] Each environment update costs one approval card → accepted; it is what makes the update reviewed.

## Satisfaction argument (W ∧ S ⇒ R)

S is the specification the machine meets: D1's profile, D2's sub-flake, check, pointer and shim, D3's hook, D4's paths and D5's secret path.

| R | Discharged by S | Resting on W (A) and assumptions (S) |
|---|---|---|
| R1 Context and skills from the first prompt | D1 writes `~/.claude/CLAUDE.md` and `~/.claude/skills/<n>` at activation; D2 activates in setup | A167, A168, A172, A174, A178; S2, S3 |
| R2 One pinned line defines the environment | D2's one-line shim and in-revision pointer | A175, A176, A177; S1, S4 |
| R3 Setup never prevents a session from starting | D2's `exit 0` and degrade-on-failure | A170 (why it is needed) |
| R4 Setup finishes within the snapshot window | D2 substitutes instead of evaluating | A169, A176, A174; S3, S5 |
| R5 Additive to harness-owned state | D1 writes only its own paths | A178 |
| R6 No secret at rest | D2 carries no secret; D5 decrypts into `/dev/shm` at session start | A172; S8 |
| R7 Every bootstrap run reports | D2's report; D3 appends to it | A179 (the controller reads it) |
| R8 Attached repositories get their repository context | D3 | A172, A175; S7 |
| R9 User context is not repeated | D3 runs `--auto` with the user context present (M4) | A167 |
| R10 One operator action per iteration | the controller-session loop | A179 |
| R11 Idempotent, no external side effects | D2 realises and activates only; no push or upload | A171 |
| R12 Required tools present | D1's tool set; D4 | A173; S6 |
| R13 One source | D1 imports the same modules other hosts import | — (a property of the repository, checked by evaluation) |
| R14 Linear skills in cloud sessions | D5 | A172; S7, S8, S9, S10 |

R8 and R14 are not discharged until P4 settles S7 and S8.

## Migration Plan

1. Land D1 and D4; `ubuntu`'s behaviour is unchanged, checked by comparing its rendered files before and after.
2. Land D2's check and sub-flake; wait for nixbot to build and publish the activation package.
3. Run the first bootstrap test from a controller session on `nix-sandbox-test`, including P4.
4. Land D3, wired as P4 allows.
5. The D5 key, recipient and `SOPS_AGE_KEY` exist (2026-11-21); add `api.linear.app` to the allowed hosts; on stibnite, add the recipient to `.sops.yaml` and create the scoped file; land the profile's secret declarations.
6. Switch the operator's default cloud environment to the pinned line.
Rollback: replace the setup step with the previous line (one approval card); the environment snapshot is rebuilt from it.

## Open Questions

- P4 (S6, S7, S8), run within the first bootstrap test.
- The setup step's real time ceiling above 360 s.
- The activation package's closure size and substitution time.
