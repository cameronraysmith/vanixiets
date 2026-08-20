## ADDED Requirements

### Requirement: Environment prerequisites are established before authoring

The Docker daemon and both runner CLIs SHALL be available, and the daemon's kernel support for enforcing `no-network` MUST be probed before any task package is authored, with the probe's exit status deciding what the packages may declare.
Installing either CLI MUST NOT write into the read-only ghq reference clones.

#### Scenario: kernel supports enforced no-network

- **WHEN** the daemon is running and an anchored kernel probe for `^CONFIG_NFT_FIB_INET=[ym]` exits 0
- **THEN** authoring proceeds with `network_mode = "public"` at each package's environment baseline and `no-network` on its `[agent]` phase

#### Scenario: kernel explicitly lacks the option

- **WHEN** the anchored probe exits 1, meaning `/proc/config.gz` records the option as unset
- **THEN** the `[agent]` phase override is dropped and every package is authored fully `public`, which is Harbor's own default and the declared mode of 86 of the 87 corpus tasks, and the loss of egress control is recorded rather than treated as a reason to halt

#### Scenario: kernel configuration is unreadable

- **WHEN** `/proc/config.gz` is absent, so the probe cannot decide
- **THEN** the outcome is recorded as indeterminate and authoring proceeds, because Harbor's own probe short-circuits to success in exactly that case, and a later rejection at environment start is taken as the deciding evidence

#### Scenario: the probe's exit status is its criterion

- **WHEN** a kernel probe is written for this requirement
- **THEN** its pattern is anchored and quiet, because an unanchored search matches the line recording the option as not set and would report success for the negative reading

#### Scenario: runner CLIs installed outside the reference clones

- **WHEN** `harbor` and `bench` are installed
- **THEN** both resolve on `PATH` and report a version, and no file under `~/ghq/github.com/harbor-framework/harbor` or `~/ghq/github.com/benchflow-ai/benchflow` is created or modified

---

### Requirement: The evaluation corpus does not break flake evaluation

The corpus SHALL live at `modules/home/ai/evals/harborize/` under version control, co-located with the first-party skill sources it evaluates, and no file inside it MUST carry the `.nix` extension.

#### Scenario: job output stays outside the tracked corpus

- **WHEN** a runner writes a job tree
- **THEN** it writes into the already-ignored `logs/harborize/` rather than into the corpus, so the tracked corpus holds authored packages, generated task heads, condition directories and recorded results and nothing else

#### Scenario: a fixture never carries the nix extension

- **WHEN** a fixture, an expectation file or a generated task head is written into the corpus
- **THEN** it carries an extension other than `.nix`, or it sits under an underscore-prefixed directory, because the flake's module discovery imports every `*.nix` file anywhere under the modules tree with no custom filter and would evaluate that file as a flake-parts module rather than read it as a fixture

#### Scenario: the constraint is checked rather than trusted

- **WHEN** the corpus root is first written, and again once the package directories and the generated task heads exist
- **THEN** an extension audit reports no `.nix` file inside the corpus and the flake's machine configurations still evaluate to an attribute list, and the audit covers the generated heads because they are produced by an exporter rather than authored by hand

---

### Requirement: Harbor cells name only skill-consuming adapters

Any Harbor cell definition used by this change SHALL name an adapter that reads the injected skills directory, and a cell naming a non-consuming adapter or an ACP registry shorthand MUST be refused before any container starts.

#### Scenario: non-consuming adapter is refused

- **WHEN** a cells definition names a Harbor adapter outside the consuming set and the adapter check runs
- **THEN** the check exits nonzero, names the adapter and the reason, and emits no run manifest

#### Scenario: ACP registry shorthand is refused

- **WHEN** a cells definition names a Harbor agent whose name begins with `acp:`
- **THEN** the check exits nonzero, because Harbor routes every such name through the non-consuming ACP adapter, which drops the injected skills on the Harbor arm while the BenchFlow arm for the same agent works

#### Scenario: consuming adapter is accepted

- **WHEN** a cells definition names a Harbor adapter inside the consuming set
- **THEN** the check exits zero and the manifest is emitted

---

### Requirement: Host-side skill resolution is proven before any container starts

The condition directory passed to either runner SHALL resolve on the host to exactly the expected skill set, each entry carrying a content digest, and this evidence MUST be recorded as host-side resolution rather than as delivery.

#### Scenario: condition directory resolves to the expected skill set

- **WHEN** Harbor's host-side skill resolution is run over the materialized condition directory
- **THEN** it returns one entry per expected skill name, each with a sha256 content digest, and the entry count equals the number of skill directories the condition declares

#### Scenario: a malformed condition directory fails on the host

- **WHEN** the condition directory contains a non-hidden child directory without a `SKILL.md`, or the path does not exist, or the path is not a directory
- **THEN** resolution raises on the host before any container starts

#### Scenario: the trial lock is not accepted as delivery evidence

- **WHEN** a trial's lock file is inspected and found to carry the full skill list with digests
- **THEN** that evidence is cited as host-side resolution and request only, because the lock is written in the trial constructor before the skills are resolved and long before they are uploaded

---

### Requirement: Both task heads pass their static gate

Each task package SHALL be authored BenchFlow-native and exported to a sibling Harbor head, and each head MUST pass the static gate that can run against its own layout before any oracle run.

#### Scenario: BenchFlow head passes structural validation

- **WHEN** `bench tasks check <task-dir> --level structural` is run against the authored native tree
- **THEN** it exits zero and reports no issues

#### Scenario: Harbor head passes schema construction

- **WHEN** the exported `<task-id>-harbor` directory is constructed as a Harbor task model in Python
- **THEN** construction succeeds, and the gate's limits are recorded: it validates field names, types and enum membership only, and it returns early without checking for a test script whenever a verifier environment is configured

#### Scenario: no Harbor CLI validation command is used

- **WHEN** a static gate for the Harbor head is selected
- **THEN** `harbor task check` and `harbor tasks check` are not used, because both reach one command that prints an error and exits 1 unconditionally, and the redirect that stub prints is not followed either, because the command it names is a metered rubric run defaulting to a real agent and model

---

### Requirement: Skill delivery is proven in the container with no model call

Every distinct condition-directory shape SHALL be proven to deliver its skills inside the container through an oracle run that materializes no model, before any metered batch uses that shape.
Every package this change authors, including the canary that carries this proof, MUST route its agent-to-verifier channel through a surface both runners execute identically.

#### Scenario: the verifier fork is the one both runners execute

- **WHEN** a task package's verifier environment fork is chosen
- **THEN** it is shared and the package writes its deliverable into the verifier log directory rather than the agent workspace, because one runner refuses at launch to run a package declaring a separate verifier sandbox rather than falling back to shared, and the other empties the verifier log directory before a separate verifier runs, so a package declaring separate either does not launch or scores every agent zero, and a workspace path would in addition pass under one runner and fail under the other

#### Scenario: the recorded fork is verified against the exported head

- **WHEN** a package README records its verifier fork
- **THEN** the fork is confirmed by resolving the mode from the exported Harbor head's declared keys rather than inferred from the source directory layout, because the resolver reads only the verifier environment mode and the verifier environment table, so shipping a verifier Dockerfile alone leaves the package resolving to shared

#### Scenario: oracle rollout delivers the declared skills

- **WHEN** `bench eval run --tasks-dir <pkg> --agent oracle --skill-mode with-skill --skills-dir <dir> --sandbox docker --jobs-dir <jobs>` is run
- **THEN** the rollout reaches the agent phase, reward equals 1, no rollout raises a skill-deployment-missing fidelity error, and each rollout's effective skills directory is the host directory that was passed

#### Scenario: the canary is shown to be falsifiable

- **WHEN** the same command is run in the no-skill mode, with no condition directory passed
- **THEN** reward is 0, which establishes that the passing run is evidence rather than a constant, and no fidelity error is raised, because with no condition directory the expected skill set is empty and the fidelity assertion is skipped

#### Scenario: a diverging in-container catalogue raises the fidelity error

- **WHEN** the same command is run against a throwaway package whose environment image already bakes a different skill set, so the in-container catalogue cannot match the host-computed one
- **THEN** the run raises the skill-deployment-missing fidelity error naming the expected skill set, and the batch does not proceed

---

### Requirement: The oracle inhabits the task under Harbor

Each task package's oracle SHALL pass the verifier under Harbor across five trials with no errored trial, and the pass criterion MUST distinguish a broken oracle from a genuine zero.

#### Scenario: oracle passes five of five

- **WHEN** `harbor run -p <task-dir> -k 5 -o <jobs> --job-name <name> -y` is run with the default agent
- **THEN** reward is 1.0 on all five trials, zero trials errored, and each trial's agent exit-code file is absent or contains 0

#### Scenario: a broken oracle is not read as a negative result

- **WHEN** a trial scores 0 and the trial's agent exit-code file exists with a nonzero value
- **THEN** the result is classified as a broken oracle rather than a genuine zero, and the task is repaired before any further rung runs

---

### Requirement: Adapter registration is asserted per adapter

For each metered cell, the change SHALL assert that the adapter registered the injected skill at that adapter's own destination, and it MUST NOT substitute an install-only run for that assertion.

#### Scenario: codex registration is asserted in-container

- **WHEN** one short metered trial completes on the codex cell via the ChatGPT-subscription path
- **THEN** the skill directory is present under the adapter's configured skills destination (`$HOME/.agents/skills/<name>/`), asserted from inside the container because that destination sits in no host bind mount

#### Scenario: install-only is rejected as a substitute

- **WHEN** an install-only run is proposed as evidence of registration
- **THEN** it is rejected, because every adapter's registration command is built inside the agent's run path and install-only skips the agent run and disables the verifier

#### Scenario: the metered cell's auth mode follows the settled decision

- **WHEN** a metered trial is run on a cell whose adapter would accept a subscription token
- **THEN** the trial authenticates through the settled codex ChatGPT-subscription path (`CODEX_FORCE_AUTH_JSON` or `CODEX_AUTH_JSON_PATH`), any Pi cell in the same batch still scrubs `ANTHROPIC_OAUTH_TOKEN` to the empty string or unset rather than merely leaving it unflagged, and Harbor telemetry is disabled for the run

#### Scenario: the metered cell's environment baseline permits the agent install

- **WHEN** a metered trial is about to run against a task head
- **THEN** that head's environment baseline is confirmed to be `public` before any spend, because the agent's install fetch runs during trial preparation outside every phase network policy, and a no-network baseline would fail the trial during install indistinguishably from an injection failure

---

### Requirement: The injection canary is retained in the corpus permanently

The injection canary package SHALL remain in the corpus after this change completes and MUST be re-run at the start of every later evaluation round.

#### Scenario: canary survives the change

- **WHEN** the change is archived
- **THEN** the canary package is present in the corpus, its README records the leakage-audit flag and the reasoning for it, and it is named as a per-round precondition rather than a one-time check

---

### Requirement: The per-run cost constant is recorded with its conditions

The change SHALL record one measured per-run cost constant together with the conditions it was measured under, and it MUST NOT project that constant into any program budget.

#### Scenario: cost constant carries its conditions

- **WHEN** the metered rung completes
- **THEN** the recorded figure names the cell, the model, the task, the trial length, the auth mode, the pricing basis and the instrument version, and the record states that a cost per run is a function of the cell and the task

#### Scenario: the figure is a rate computation, not a billed charge

- **WHEN** the metered cell's adapter has no billed-cost field of its own and derives the figure from token counts against a pricing table
- **THEN** the record says so, the figure is still reported as a metered-rate figure because the pricing table carries metered list rates and does not vary with how the trial authenticated, and an absent pricing entry yields no number rather than a zero

#### Scenario: no budget is derived here

- **WHEN** the constant is reported
- **THEN** no condition count, no cell count and no run total are multiplied by it inside this change

---

### Requirement: Packages and results are stamped with the instrument version, and the instrument is unmodified

Every package README and every results file SHALL stamp the instrument version that produced it, and the harborize skill directory MUST NOT be modified for the duration of this change.

#### Scenario: instrument version stamped

- **WHEN** a package or a results file is written
- **THEN** it carries the instrument version 0.2.1 and the three upstream revisions the claims were verified at

#### Scenario: a defect found mid-change is deferred

- **WHEN** a defect in the instrument is discovered while a package is being authored or run
- **THEN** it is recorded for the next revision and the instrument is left unchanged, so the round's results stay attributable to one version

#### Scenario: instrument directory unchanged at completion

- **WHEN** the change completes
- **THEN** a content digest of the harborize skill directory equals the digest recorded before any other task ran, and that digest rather than a working-copy diff is the check, because a diff of the working-copy commit against its parents would show nothing for an edit squashed into the chain this change routes onto
