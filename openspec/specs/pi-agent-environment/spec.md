# pi-agent-environment Specification

## Purpose
Defines the Nix-managed Pi agent environment, including resource composition, runtime boundaries, safety policy, activation, verification, and rollback.

## Requirements

### Requirement: Nix-owned Pi resources

The system MUST obtain Pi 0.84.1, enabled executable resources, the policy baseline, theme, global instructions, and canonical skills from Nix and Home Manager.

#### Scenario: Home Manager evaluates the Pi environment

- **WHEN** the Pi Home Manager module is evaluated
- **THEN** its compact value reports package version `0.84.1` and its resource and ownership fields equal the literal Nix-owned oracle

### Requirement: Mutable settings seed

The system MUST replace `settings.json` during Home Manager activation with a Nix-generated mutable copy.

#### Scenario: Settings ownership is inspected

- **WHEN** the evaluated activation step and confirmed live target are inspected
- **THEN** `settings.json` is installed as a mutable copy rather than an immutable store symlink

### Requirement: Runtime state boundary

Within Pi-managed paths, the system MUST preserve Home Manager's mutable `settings.json` copy and MUST NOT convert runtime-managed settings, sessions, compaction, authentication, project trust, model selection, thinking preferences, or extension state into immutable executable-resource links.
It MUST keep executable policy, theme, extensions, and global instructions immutable without claiming to enumerate every possible Pi runtime path.

#### Scenario: Pi records allowed runtime state

- **WHEN** structural declarations and representative confirmed live targets under Pi-managed paths are inspected
- **THEN** the settings copy and runtime-managed categories are not converted into immutable executable-resource links, while executable policy, theme, extensions, and global instructions remain immutable

### Requirement: Source-only extension package

The system MUST provide exactly one new by-name package, `pi-agent-extensions`, from `rytswd/pi-agent-extensions` commit `c700f300707db5345727052682c88e3064030aa2` with hash `sha256-RLtDi9ahKONSJBuuYkYo/oIIxDX6PWiZ7rlevOStUUk=`, without npm installation, `node_modules`, or a new flake input.

#### Scenario: Extension package is realized

- **WHEN** the existing ordinary package map realizes `package-pi-agent-extensions` and the pre-activation scope and diff scan inspects package and flake-input changes
- **THEN** the derivation uses the exact fixed-output source, installs a source-only tree, rejects `node_modules`, and the diff contains exactly one new by-name package and no new flake input

### Requirement: Selected extensions

The `pi-agent-extensions` package filter MUST load exactly `direnv/index.ts`, `permission-gate/index.ts`, `questionnaire/index.ts`, `slow-mode/index.ts`, `stash/index.ts`, and `statusline/index.ts` as positive extension selectors.

#### Scenario: Selected extension resources are evaluated

- **WHEN** the compact evaluated package filter is compared with its literal oracle
- **THEN** the positively selected extension paths equal the ordered six-path oracle

### Requirement: Nix-owned runtime executables

Home Manager MUST place exactly `direnv`, `diffutils`, `git`, `jujutsu`, and `rip2` from Nix on Pi's added runtime PATH.

#### Scenario: Added runtime executables are evaluated

- **WHEN** the compact `programs.pi-coding-agent.extraPackages` value is inspected
- **THEN** its ordered package-name value equals the five-name literal oracle

### Requirement: Excluded extension resources

The package filter MUST explicitly exclude `fetch/index.ts` and `notify/index.ts`, and MUST select no skills, prompts, or themes from `pi-agent-extensions`.

#### Scenario: Excluded resources are evaluated

- **WHEN** the compact package filter is compared with its literal oracle
- **THEN** both negative selectors are present and every unselected resource-kind list is empty

### Requirement: Retained compaction extension

The system MUST retain `pi-openai-server-compaction` as a separate enabled package.

#### Scenario: Compaction package remains configured

- **WHEN** the compact evaluated package entries are inspected
- **THEN** the existing compaction package remains a separate entry beside `pi-agent-extensions`

### Requirement: Canonical skill sink

The system MUST continue using `~/.agents/skills` without adding `~/.pi/agent/skills`.

#### Scenario: Skill locations are inspected

- **WHEN** evaluated Home Manager files and the confirmed live links are inspected
- **THEN** `~/.agents/skills` remains canonical and no Pi-specific shadow sink exists

### Requirement: Catppuccin source provenance

The first-party theme copy MUST equal `aldoborrero/pi-agent-kit` commit `128c4c08396961ea8f934111ba1aad0b33c525b2` file `themes/catppuccin-mocha.json` with SHA-256 `5858d086e155246d48e5b7a2ac372988fe2d1a028d2b77b5f0a7670088a8642b`.

#### Scenario: Theme source and digest are checked

- **WHEN** the file is acquired from the pinned source coordinates and its checked-in content is hashed
- **THEN** source review confirms the commit and path and the structural digest equals the literal SHA-256 oracle

### Requirement: Catppuccin theme delivery

The system MUST select `catppuccin-mocha` from the immutable first-party file `modules/home/ai/pi/themes/catppuccin-mocha.json` without creating a standalone theme package.

#### Scenario: Theme delivery is evaluated

- **WHEN** the compact evaluated theme file, target, selected name, and package inventory are inspected
- **THEN** the file is immutable, `catppuccin-mocha` is selected, and no standalone theme package exists

### Requirement: Permission-gate reuse

The system MUST use the pinned rytswd permission-gate shell parser, built-in rules, project-trust boundary, and headless behavior as the Bash enforcement engine.
This choice rests on the `world-assumptions` capability's assumption that Pi ships no native permission system (`world-assumptions` A1); should that assumption be falsified, this requirement's discharge argument for building Bash enforcement into an external parser rather than a native mechanism no longer holds.

#### Scenario: Shell command enters policy

- **WHEN** the pure policy harness evaluates shell and untrusted project-config cases through the pinned parser and rule API
- **THEN** semantic commands and project attempts to weaken protected behavior receive the literal expected decisions

### Requirement: Additional shell policy

Nix-owned permission-gate rules MUST classify dangerous commands, semantic mutating HTTP requests, direct `rm`, worktree creation, and Pi package mutation, with direct `rm` and package mutation blocked and interactive mutating HTTP and worktree requests prompted.
The prompted decision class for mutating HTTP and worktree requests names the same UI-present-no-human assumption as `Fail-open policy` below (`world-assumptions` A2); the two requirements are reconciled, not in tension, because a session without a UI channel never reaches an interactive prompt at all — the pinned permission-gate engine blocks a prompt-class match immediately when no UI is present, before ever presenting a dialog — so this requirement's Bash prompt class and `Fail-open policy`'s no-interactive-answer clause, scoped to the first-party non-Bash decision core, govern disjoint reachable conditions.

#### Scenario: Shell mutation reaches custom rules

- **WHEN** a parsed command matches a declared shell-policy table row
- **THEN** policy returns the literal allow, prompt, or block decision with `rip` or Nix-pin guidance where applicable

### Requirement: Non-Bash edit and write policy

A compact first-party pure decision core with a thin Pi adapter MUST evaluate non-Bash `edit` and `write` tool calls and classify each outcome as allow, notify-and-allow, or block.
It MUST refuse only a mutation version control could not recover, and MUST announce rather than refuse every condition whose target is inside a repository.
The exported adapter factory or handler seam MUST be directly executable as policy evidence.
The extension is scoped to Pi, and the system MUST declare that scope to atomic rather than relying on either agent's default discovery, under the `world-assumptions` capability's assumption that atomic inherits Pi's configuration root and loads Pi's extension directory unconditionally (`world-assumptions` A6).
The policy MUST normalize a tool path exactly as Pi resolves it, covering the `@` prefix, a leading `~`, a `file://` URL, and Unicode space variants, so the path the policy judges is the path the tool opens, under the assumption that this enumeration is exhaustive of Pi's own path resolution (`world-assumptions` A7).
This requirement's announce-rather-than-refuse discharge additionally rests on the assumptions that Pi has no native permission system (A1), that an unanswerable dialog stalls a session with UI but no human present (A2), that policy failure carries no safety evidence (A3), that refusing on ambiguity has a real cost and prevents nothing (A4), and that a target inside a repository is recoverable from its history (A5) — the last of which has a known sharp edge for untracked, gitignored targets, per `world-assumptions` A5's own scenario.

#### Scenario: Non-Bash mutation reaches policy

- **WHEN** the policy harness runs pure-core rows and directly invokes the exported adapter seam with synthetic edit/write allow, notify, and block calls, an unrelated tool, malformed tool input, atomic's headerless `edit` input shape, and core or capability exceptions
- **THEN** the core returns the literal decisions, the adapter translates block and passes allow and notify through, passes unrelated tools through, converts malformed input into a diagnostic block, converts exceptions into permission, and starts no Pi process per row

#### Scenario: Pi-only scope is declared to atomic

- **WHEN** the generated atomic settings are inspected
- **THEN** every Pi-only extension is named as a force-exclude relative to the inherited Pi configuration root, in the spelling atomic matches against that root

#### Scenario: Tool path is normalized as Pi resolves it

- **WHEN** the policy normalizes `@`-prefixed, `~`-prefixed, `file://`, Unicode-space, and ordinary relative paths
- **THEN** each result equals the path Pi's own resolution produces, and a path that normalizes to nothing is rejected as malformed

### Requirement: Git default-branch boundary

The first-party policy extension MUST announce, and allow, a non-Bash edit or write while the target Git repository is on `main` or `master`.
It MUST block a target the identified Git repository does not contain.
The Git branch of repository inspection MUST remain reachable when the jj probe reports an outside-repository diagnostic followed by additional advisory lines.
This requirement's announce-rather-than-refuse discharge for the default-branch case rests on the same failure-carries-no-safety-evidence and recoverable-history assumptions as `Non-Bash edit and write policy` (`world-assumptions` A3, A5), scoped here to Git default-branch history specifically.
Its fallback to Git branch inspection additionally rests on the assumption that a target's identified containment is measured through Pi's own exhaustively enumerated path forms (A7) and that jj emits a stable outside-repository diagnostic with trailing `Hint:` lines (A8).

#### Scenario: Edit is proposed on a Git branch

- **WHEN** injected repository capabilities report a feature branch, `main`, or `master`
- **THEN** feature-branch mutation is eligible to continue, default-branch mutation is announced and eligible to continue, and a target outside the repository is blocked

#### Scenario: Jj reports outside a repository with trailing advice

- **WHEN** the jj root probe exits non-zero with the outside-repository diagnostic followed by the trailing `Hint:` lines jujutsu emits inside a Git repository
- **THEN** inspection falls through to the Git branch rather than treating the probe as indeterminate

### Requirement: Jj diamond boundary

The first-party policy extension MUST consume typed, discriminated repository state and admit both healthy ordinary and healthy diamond-managed jj repositories before non-Bash edits and writes.
Every unhealthy jj condition other than target containment MUST be announced and allowed rather than refused, under the `world-assumptions` capability's assumption that its target is inside a repository whose history can recover it (`world-assumptions` A5).
Common jj health MUST require canonical repository identity and target containment; unambiguous, conflict-free `@`; a non-divergent current `@` change identity; neither `main` nor `master` pointing directly to `@`; and successful, unambiguous parsing of every read-only probe, each invoked with `jj --ignore-working-copy`.
A separate bookmark-listing classification probe MUST report the `wip` convention, including a divergent `wip` indicator, before the repository is classified as diamond-managed.
Only a repository already classified as diamond-managed MUST run the unique `wip`-resolution probe and admit absent, moved, or divergent `wip` failure outcomes.
A repository with no `wip` report MUST remain eligible for ordinary classification and MUST NOT reach a missing-`wip` failure.
Diamond health MUST additionally require `@` to be the nonconflicted, nondivergent `[wip]` commit with exactly one parent and exactly one non-divergent `wip` bookmark pointing to it.
It MUST probe `@-` separately as the `[merge]` join, require that join to be nonconflicted with at least two parents, and probe `parents(@-)` separately to require conflict-free immediate parents whose count matches the join report.
Neither `@` nor `@-` MUST be required to be empty, and diamond health MUST impose no working-copy-cleanliness requirement.
Ordinary jj health MUST impose no `wip`, diamond-topology, emptiness, or working-copy-cleanliness requirement.
This requirement's announce-rather-than-refuse discharge additionally rests on the assumption that policy failure carries no safety evidence (A3), and its repository-identity and containment probes rest on the assumptions that Pi's path forms are exhaustively enumerated (A7) and that jj emits a stable outside-repository diagnostic with trailing `Hint:` lines (A8), the latter shared with `Git default-branch boundary`.

#### Scenario: Edit is proposed in a jj repository

- **WHEN** the literal policy table evaluates ordinary healthy states, including a nonempty `@`, with no `wip` report; ordinary conflict, divergence, and protected-bookmark states; an actual healthy empty `@` `[wip]` over an empty six-parent `@-` join; healthy nonempty `[wip]` and conflict-resolved nonempty join states; classified-diamond absent, moved, or divergent unique-`wip` resolution; non-single-parent `[wip]`; single-parent or conflicted join; conflicted immediate join parent; join-parent count mismatch; and malformed or failing join probes
- **THEN** the ordinary healthy rows and all three healthy diamond rows are eligible to continue, the ordinary no-`wip` rows never reach missing-`wip` failure, every unhealthy row is announced diagnostically and eligible to continue, every indeterminate row is eligible to continue while still classifying its diagnostic, a target the repository does not contain blocks, and every recorded read-only jj argv exactly matches the ordered `jj --ignore-working-copy` argv oracle

### Requirement: Fail-open policy

Parser errors, core or adapter exceptions, ambiguous repository state, and missing or throwing capabilities MUST permit the affected tool call rather than refuse it, under the `world-assumptions` capability's assumptions that policy failure carries no safety evidence and that refusing on ambiguity has a real cost and prevents nothing (`world-assumptions` A3, A4).
This requirement, in both clauses, is scoped to the first-party pure decision core and its Pi adapter that `Non-Bash edit and write policy` names, and does not extend to the pinned rytswd permission-gate engine `Permission-gate reuse` names as the Bash enforcement engine: that upstream engine's own rule-evaluation exception handling fails closed rather than open, turning a throwing rule into a block rather than a permit, and its prompt-class behavior is governed by `Additional shell policy`, not this requirement.
Malformed tool input remains the one refusal drawn from an unreadable request rather than an unrecoverable target.
The policy MUST NOT require an interactive answer to permit a mutation, under the assumptions that Pi has no native permission system and that an unanswerable dialog stalls a session with UI but no human present (`world-assumptions` A1, A2).
This clause and `Additional shell policy`'s prompted decision class for mutating HTTP and worktree requests are reconciled: scoped as above, this clause governs only the first-party non-Bash decision core, which never prompts by construction, while `Additional shell policy`'s prompt class governs the separate Bash engine.

#### Scenario: Policy cannot decide safely

- **WHEN** the policy harness injects each parser, decision, adapter, repository, or capability failure
- **THEN** the result is permission rather than a block or an uncaught exception, and the repository classification still reports its diagnostic

#### Scenario: Announcement channel is unavailable

- **WHEN** the notification capability is absent or throws on a notify-class decision
- **THEN** the mutation remains permitted rather than becoming refused

### Requirement: Secret-safe direnv

The system MUST configure runtime environment indirection through direnv while keeping sentinel secret values absent from Nix expressions, store files, and generated configuration.
This requirement does not claim or test upstream direnv value-supply behavior.

#### Scenario: Direnv indirection is secret-safe

- **WHEN** structural runtime-indirection configuration and aggregate generated and store-backed content are inspected with a sentinel value
- **THEN** runtime indirection is configured and the sentinel value is absent from Nix, store-backed, and generated configuration

### Requirement: Opt-in slow mode

The system MUST load slow-mode while leaving it inactive until the operator invokes its command or flag.

#### Scenario: Slow mode configuration is evaluated

- **WHEN** the compact selected-resource and settings values are inspected
- **THEN** slow-mode is selected without any setting that activates it by default

### Requirement: Consolidated custom regulators

The flake MUST expose exactly two custom Pi derivations, `pi-agent-environment-policy` and `pi-agent-environment-smoke`, while the unmodified `modules/checks/packages.nix` automatically maps `pi-agent-extensions` to `package-pi-agent-extensions`.
The policy regulator exercises system-independent decision code and MUST be defined for `x86_64-linux` only; the smoke regulator observes platform-dependent loading and MUST be defined on every checked system.
Declaration claims that relate Pi's evaluated settings to atomic's, Pi-only scope, and the absent Pi-specific skill sink belong to `atomic-agent-environment-structural` rather than to a Pi-only structural derivation, and no check restates a literal oracle of the Pi module's own declared values.

#### Scenario: Pi checks are enumerated

- **WHEN** `x86_64-linux` and `aarch64-darwin` checks are enumerated externally
- **THEN** the `x86_64-linux` custom Pi check set equals the two-name oracle, the `aarch64-darwin` set contains only `pi-agent-environment-smoke`, and ordinary package coverage includes `package-pi-agent-extensions`

### Requirement: Offline aggregate smoke

The smoke regulator MUST execute the evaluated deployed Pi wrapper once in a hermetic fresh home with `PI_OFFLINE=1`, test-owned settings and model fixtures, and extension and canonical-skill resources supplied through first-class evaluated derivation paths rather than parsed Home Manager activation shell.
It MUST use an explicit synthetic model from a deterministic local mock-provider registration and bound both stdin closure and process exit.
It MUST assert only distinct cross-platform runtime compatibility evidence observable from the Pi process or RPC protocol: startup and successful RPC responses, no `extension_error`, required extension and canonical-skill commands, the explicit synthetic model selection, no reported session file under `--no-session`, and exit status zero after stdin closure.
Structural declarations, policy behavior, activation, credentials, resource ownership, and fixture contents remain outside this smoke regulator's envelope.

#### Scenario: Deployed wrapper reaches bounded RPC readiness

- **WHEN** the hermetic fixture starts the evaluated wrapper with explicit `--model smoke-local/smoke-model`, requests `get_state` and `get_commands`, and closes stdin
- **THEN** Pi reports the selected synthetic model without a session file, exposes the required extension and canonical-skill commands without `extension_error`, and exits zero within the bound

### Requirement: Rollback preservation

After activation, `/nix/var/nix/profiles/system` MUST point to the new active `system-N-link`, and the immediately previous generation `system-(N-1)-link` MUST remain present and resolvable for rollback.

#### Scenario: Activated system profile is inspected

- **WHEN** the nix-darwin system profile links are queried after activation
- **THEN** the active link resolves to a `system-N-link`, and the immediately previous `system-(N-1)-link` remains present and resolvable for rollback

---

### Requirement: Activation requires explicit permission

An agent MUST NOT run system activation unless given explicit permission to do so.
Before asking the human operator to run activation, the agent MUST record the current `/nix/var/nix/profiles/system` link and its resolved store path.
This requirement and `Post-activation confirmation gate` below claim nothing broader than activation and post-activation probing.

#### Scenario: Activation is proposed without explicit permission

- **WHEN** an agent has not been given explicit permission to run system activation
- **THEN** the agent does not run activation, and instead records the complete, nonempty single-line outputs of `readlink /nix/var/nix/profiles/system` and `readlink -f /nix/var/nix/profiles/system` before asking the human operator to run it

### Requirement: Post-activation confirmation gate

An agent MUST NOT begin any post-activation live-state probe until the human operator explicitly confirms that the activation succeeded.

#### Scenario: Activation success is unconfirmed

- **WHEN** the human operator has not explicitly confirmed that activation succeeded
- **THEN** the agent runs no live-state probe, and no post-activation task is marked complete

---
