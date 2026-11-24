<!--
Raw capture of the decision chain that settled this change.

The exploration ran in the session that produced the harborize 0.2.0 and 0.2.1 repair rounds and the
dispatch brief for this change; the decisions below arrived settled rather than open, and this file
records them in the decision-log shape the artifact expects. It is not a transcript.

design.md reorganizes this material into Context, Goals, Decisions, Risks and Migration; the two
files are complementary and do not duplicate each other.
-->

# Background

The harborize skill is a measurement instrument that compiles agent skills into runnable evaluation packages.
It has been through two repair rounds in one day: 0.2.0 fixed documented instructions that could not run at all, and 0.2.1 fixed claims that were true on the host and asserted about the container.
`CHANGELOG.md` records what moved in each.

Three things are true at 0.2.1 and together they define the problem this change addresses.
No package emitted by the instrument has ever been validated: the three iteration-1 packages under `~/Downloads/harbor-skill/harborize-workspace/iteration-1/` failed the oracle inhabitation invariant, two ship a fixture script the instrument forbids, and one declares a separate-mode verifier that cannot run.
No per-run cost figure exists, so every budget the instrument's Phase 5 asks the user to choose between is presented without arithmetic behind it.
And the repairs themselves are unwitnessed: the 0.2.1 round asserts a set of container-boundary facts about skill injection that nothing has yet exercised end to end.

A marketplace-wide evaluation program is drafted in `references/marketplace-program.md` with five stages, and every one of its figures multiplies a per-run cost that has not been measured.
Running that program before the instrument produces a package that demonstrably injects is how the earlier iteration produced three unusable artifacts.

# Decision chain

## Q1 — what is the unit of ablation?

Settled: the skill, materialized from the deployed tree.
A plugin unit is a derived aggregate, the union of its member skills' deployed directories, resolved through an explicit skill-to-plugin membership map shipped beside the census.
The map is required because the deployed tree is flat: one directory per skill, no plugin directories and no `.apm/` paths, so membership cannot be recovered from directory structure.

The census covers both subjects and reports both.
The deployed tree is the evaluation subject because it is what a harness loads, currently 172 skill directories under `~/.claude/skills`.
The first-party source tree is the refactor subject because it is the only place a fix can be written, currently 129 skills across 18 plugin groups per the bundled `census.json` provenance block.

## Q2 — mechanical contracts or judge-graded ones?

Settled: mechanical by default, and exactly one judge-validation package is a hard gate before any judge-based stratum enters a budget.
The gate is warranted by the surrounding ecosystem rather than by taste: all 87 tasks shipped in SkillsBench declare `verifier.type: test-script` and none uses a judge verifier.
That gate is out of scope here and belongs to the dependent change, because building it costs a human-labeled validation set and this change has to establish that a mechanical package works at all first.

## Q3 — how is a budget costed?

Settled: every figure is costed at metered API rates.
Subscription-authenticated cells are permitted for interactive exploration and never appear in a batch whose numbers are reported, because metered costing is robust to the unresolved credential-use-policy question in either direction and because a subscription cell confounds the measurement independently through nondeterministic rate-limit throttling and single-account concurrency caps.
Enforcement is an explicit environment scrub rather than the absence of a flag: Pi injects `ANTHROPIC_OAUTH_TOKEN` whenever the variable is present and non-empty in the resolved environment, with no force flag of the kind claude-code and codex require.

## Q4 — what happens to the three iteration-1 packages?

Settled: reference material for shape, regenerated under the repaired instrument, never cited for results.
None of them passed oracle inhabitation, so promoting any of them would carry an unvalidated package into a measured program.

## Q5 — how does instrument versioning interact with a round?

Settled: results are indexed by instrument version, and the instrument is not modified while an evaluation is being authored or run.
Revisions happen between rounds.
This change runs against 0.2.1 throughout.
A defect found mid-change is recorded and deferred to the next revision rather than fixed in place, because a fix mid-round makes the round's results unattributable to any version.

## Q6 — given Q1 through Q5, what does this change deliver?

Settled: the smallest thing that turns the instrument's claims into evidence and produces the one number every later budget multiplies.
Three deliverables.
An injection canary package that stays in the corpus permanently as a regression test, so the container-boundary facts 0.2.1 asserts are exercised on every later round rather than assumed.
One real mechanical evaluation package, so the dual-head authoring path, the static gates and the oracle inhabitation invariant are demonstrated on a task that measures something.
And the measured per-run cost constant.

## Q7 — in what order, given that most of the risk is free to retire?

Settled: a seven-rung ladder numbered 0 through 6, free rungs before metered ones, each rung with an executable pass criterion.
The ordering is not a preference about thoroughness; it follows from where the failures actually sit.
Every silent-null class the instrument documents is detectable at zero marginal cost except the adapter registration copy, which is built inside each adapter's `run()` and is therefore unreachable without a real agent invocation.
So the metered rung is last and it is one short trial per cell, and everything upstream of it — prerequisites, the adapter allowlist, host-side resolution, static task validation, and the two oracle rungs that cost Docker time and zero model calls — retires the rest.

The prerequisites rung is a real rung rather than an assumption.
OrbStack is stopped, the Docker socket is absent, and neither `harbor` nor `bench` is installed, so the ladder currently cannot start.
One prerequisite is blocking in a way that shapes authoring rather than merely delaying it: Harbor rejects any `no-network` policy at environment start when the daemon's kernel lacks `CONFIG_NFT_FIB_INET`, and the resulting failure surfaces at the reward level indistinguishably from an injection failure.
`no-network` is the harborize instrument's own authoring default rather than Harbor's, whose default is `public`, so the probe decides what a package may declare rather than whether the change can proceed.
Probing it before any task is authored is what keeps a daemon capability from being read as an authoring error.

## Q8 — one package directory or two?

Settled: two, with the BenchFlow-native tree authored and the Harbor head derived by `bench tasks export` into a sibling directory.
Three independent validators force the split rather than merely preferring it, and the SkillsBench corpus is uniformly native.
Deriving rather than maintaining two trees is what keeps the heads from drifting.

## Q9 — what about the canary's answer key?

Open, and deliberately left open.
Any delivery canary that asserts a token has to place the same literal in the verifier and in the SKILL.md, which the instrument's own leakage audit flags by construction as a quoted expectation string recoverable from skill content.
The flag is correct on its own terms and the package is still sound, because the canary is an instrument-integrity test rather than a capability measurement: the answer key living in the skill is the delivery mechanism being tested.
Adding an exemption to the audit is the obvious resolution and D5 forbids it, since that is a modification to the instrument during a round.
So the change records how it handles the flag and defers the instrument-side question.

# Design trade-offs

Scope against confidence.
A wider first change — several packages, a condition lattice, a plugin-level screen — would produce more measurement per unit of setup, and it would repeat the iteration-1 failure of building on an instrument whose delivery path has never been demonstrated.
The narrow change buys a permanent regression asset and a cost constant, and it defers everything that multiplies them.

Docker time against model spend.
Rungs 4 and 5 are the strongest evidence available for free, because both runners' oracle paths execute the full deployment machinery with no model materialized: BenchFlow asserts the in-container skill catalogue against the host-computed one, and Harbor's oracle uploads a solution and execs it.
They cost image builds and container time, which is why they sit ahead of the metered rung rather than being skipped as merely cheap.

Canary permanence against corpus noise.
Keeping the canary in the corpus forever adds a task that measures no capability, and that is the point: it is the only artifact that fails when the injection path regresses, and a regression there voids every measurement taken after it.
