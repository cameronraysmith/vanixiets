---
name: session-plan
description: Tactical-to-operational transition skill that transforms scope understanding into an operational execution buffer of atomic issues with dependencies, acceptance criteria, and Cynefin classification.
---
# Session planning

Symlink location: `~/.claude/skills/session-plan/SKILL.md`
Slash command: `/session-plan`

Session planning protocol that transforms tactical-level understanding into an operational execution buffer of atomic issues with explicit dependencies, acceptance criteria, and Cynefin classification.
This skill operates at the tactical-to-operational planning horizon, decomposing scope into an implementation buffer at high resolution.

This is the default planning command for repositories with the full stigmergic workflow installed.
For repositories without the full workflow (no session-layer skills, small utility repos, quick fixes), use `/issues-beads-seed` and `/issues-beads-evolve` directly.

## Composed skills

This skill orchestrates a higher-level protocol that uses the following skills as components.
Do not duplicate their functionality; delegate to them.

- `/issues-beads-seed` creates an issue graph from architecture and specification documents.
  Delegate to this skill for new issue creation from `docs/development/` artifacts.
- `/issues-beads-evolve` refines issue graph structure.
  Delegate to this skill for restructuring existing graph topology (splitting, merging, re-parenting, dependency rewiring).
- `/stigmergic-convention` provides the signal table schema, field definitions, and read-modify-write protocol for writing signal tables on new and updated issues.

Load `/issues-beads-prime` for core beads conventions and command quick reference before running planning commands.

## Protocol

Execute the following steps in order.

### Step 1: AMDiRE readiness gate

Before any planning activity, validate that the `docs/development/` AMDiRE artifacts are sufficient to generate well-formed issues.
This gate enforces the contract that only tactical-resolution specifications in `docs/development/` serve as planning input.
The gate is a pure read operation: it examines filesystem state and produces a structured result without modifying any files.

The gate's stringency modulates by Cynefin domain.
Clear-domain work requires rigorous specifications because it is fully analyzable from documents.
Complex-domain work accepts less-formal specifications because it is emergent; the gate generates probe-oriented issues rather than implementation-detailed ones.

#### Required artifacts

Two AMDiRE categories must have substantive content for planning to proceed.

`docs/development/context/` must contain at least one document beyond `index.md`.
Context provides the problem domain understanding from which planning derives Cynefin classification, scope boundaries, and the rationale for why work items exist.
Without context, issues cannot be classified by domain and the resulting graph lacks information for planning-depth modulation.

`docs/development/architecture/` must contain at least one document beyond `index.md`.
Architecture provides the component decomposition and interface contracts from which planning derives epic boundaries, story breakdowns, and dependency relationships.
Without architecture, there is no structural basis for the issue graph.

#### Strengthening artifacts

Two additional AMDiRE categories improve planning output quality when present but do not block planning.

`docs/development/requirements/` enables attaching acceptance criteria and verification commands to issues.
When absent, planning generates issues with descriptive acceptance criteria inferred from architecture and emits a warning that acceptance criteria lack verification commands.

`docs/development/traceability/` enables validating that the issue graph covers all specified requirements.
When absent, planning cannot perform coverage analysis and emits a warning that completeness is unverifiable.

`docs/development/work-items/` is not an input to planning.
It is the output location for tracking implementation progress after seeding and is not checked by the gate.

#### Content quality checks

Presence alone is insufficient.
The gate examines content within required directories for the information planning consumes.

*Context quality criteria* require three elements.
First, a problem domain description: prose explaining what the system operates within, what constraints exist, and what objectives the work serves.
Planning uses this to generate issue descriptions that explain why each work item matters.
Second, a Cynefin domain classification: explicit classification of major components or subsystems as clear, complicated, complex, or chaotic.
This may appear as frontmatter (`cynefin: complicated`), as inline classification within the document, or as a dedicated section mapping components to domains.
Detection checks three locations in order: YAML frontmatter (`cynefin:` field), a dedicated section heading containing "cynefin" or "domain classification," and inline prose containing classification language; the first match wins.
Third, scope boundaries: explicit statement of what is in scope and out of scope for the current planning horizon.

When context lacks Cynefin classification, the gate defaults all components to the complicated domain and emits a warning stating which components lack classification and what default was applied.
Complicated is the safest default: it requires analysis but not probing, producing reasonably detailed plans without the rigidity of clear-domain specifications.

*Architecture quality criteria* require two elements.
First, a component decomposition: identification of major subsystems, modules, or services that constitute the solution, each described with enough specificity to derive an epic boundary.
A list of component names without descriptions is insufficient; planning needs to understand what each component does to generate meaningful story descriptions.
Second, dependency relationships: explicit identification of which components depend on which.
When dependencies are absent, planning can only generate a flat graph of independent epics, which is structurally valid but loses critical-path information.
Interface contracts between components are beneficial but not required.
When present, planning uses them to generate integration stories at component boundaries.
When absent, planning generates placeholder integration stories with acceptance criteria requiring interface definition during implementation.

*Requirements quality criteria* (when present) check for acceptance criteria (testable conditions defining when a requirement is satisfied) and verification commands (concrete commands or procedures for testing, e.g., `cargo test --features auth`, `curl -s http://localhost:8080/health | jq .status`).
When verification commands are present, planning attaches them to issues.
When absent, issues receive acceptance criteria without verification commands and a warning is emitted.

#### Blocking versus warning classification

The gate classifies deficiencies using expected rework cost as the decision criterion.
A blocking deficiency produces an issue graph requiring fundamental restructuring; a warning deficiency produces a valid but degraded graph that can be incrementally refined via `/issues-beads-evolve`.

*Blocking deficiencies* (halt planning):
- `docs/development/context/` does not exist or contains only `index.md`.
- `docs/development/architecture/` does not exist or contains only `index.md`.
- Architecture specification contains no identifiable component decomposition (a document exists but describes high-level vision without naming discrete components).

When a blocking deficiency is detected, emit the diagnostic, cite the documentation promotion workflow as the remediation path, and refuse to proceed.

*Warning deficiencies* (allow planning with degraded output):
- Context lacks Cynefin classification (severity: low). Default to complicated.
- Context lacks explicit scope boundaries (severity: moderate). Plan for all identified components.
- Architecture lacks dependency relationships (severity: moderate). Generate independent epics.
- Architecture lacks interface contracts (severity: low). Generate integration placeholders.
- Requirements directory absent (severity: moderate). Infer acceptance criteria from architecture.
- Requirements lack verification commands (severity: low). Omit verification commands.
- Traceability directory absent (severity: low). Skip coverage analysis.

Each warning includes severity and recommended remediation.
Warnings are collected and presented as a summary before planning proceeds.

#### Signal derivation

The gate derives two planning parameters from the context specification that control how issues are generated.

*Cynefin classification* propagates from context to generated issues and determines issue shape.
For clear-domain components: detailed step-by-step acceptance criteria, specific file paths, concrete verification commands; issues designed for execution without interpretation.
For complicated-domain components: analytical acceptance criteria describing expected outcome and analysis approach, leaving implementation details to the worker; verification commands included.
For complex-domain components: probe-oriented issues describing what uncertainty to resolve rather than what to build, including sense-making checkpoints and time-boxed exploration; acceptance criteria is "documented findings that inform next steps."
For chaotic-domain components: no issues generated; the gate emits a warning that chaotic-classified components are excluded from seeding and should be addressed through act-sense-respond cycles first.

*Planning depth* derives from Cynefin classification.
Clear-domain components decompose to fine granularity (epics, stories, tasks).
Complicated-domain components decompose to medium granularity (epics and stories, no tasks).
Complex-domain components decompose to coarse granularity (epics with probe stories only; further decomposition after probe completion via `/issues-beads-evolve`).

#### Diagnostic output template

The gate produces output in the following structure.
Render pass, blocked, or pass-with-warnings as appropriate.

```
Readiness gate: {PASS | BLOCKED | PASS with warnings}

Required artifacts:
  [{pass|blocked}] docs/development/context/ — {N documents found | not found | index.md only}
  [{pass|blocked}] docs/development/architecture/ — {N documents found | not found | index.md only}

Strengthening artifacts:
  [{pass|absent}] docs/development/requirements/ — {N documents found | not found}
  [{pass|absent}] docs/development/traceability/ — {N documents found | not found}

Content quality:
  [{pass|blocked|warn}] Context: problem domain description
  [{pass|warn}] Context: Cynefin classification {: domain | (default: complicated)}
  [{pass|warn}] Context: scope boundaries
  [{pass|blocked}] Architecture: component decomposition {: N components}
  [{pass|warn}] Architecture: dependency relationships
  [{pass|warn}] Architecture: interface contracts

{Only when requirements/ present:}
  [{pass|warn}] Requirements: acceptance criteria
  [{pass|warn}] Requirements: verification commands

{Only when warnings exist:}
Warnings from absent strengthening directories:
  [warn] {directory} absent (severity: {low|moderate})
    {Remediation guidance}

Derived parameters:
  Cynefin classification: {domain} ({scope note})
  Planning depth: {shallow|medium|deep} ({decomposition description})

{When blocked:}
Planning cannot proceed. Address blocking deficiencies by promoting
working notes from docs/notes/ to docs/development/ following the
documentation promotion workflow specification.

{When warnings exist:}
{N} warnings found. Proceed with degraded output, or address warnings
first? [proceed/address]
```

#### Invocation modes

The gate supports two modes.
Since this skill is a prompt template read by an AI agent rather than a CLI tool, the mode distinction is expressed as a conditional instruction activated by a parameter in the invocation prompt.

*Interactive mode* (default): present findings (blockers, warnings, derived parameters) and wait for user confirmation before proceeding.
This is appropriate when a human is coordinating the planning session.

*Automated mode* (activated by "mode: automated" in the prompt context): halt on blockers, proceed through warnings without prompting, and log the full diagnostic.
This is appropriate when planning is invoked programmatically by an orchestrator agent.

#### Incremental scoping

The seed skill recommends seeding one epic at a time rather than creating the entire structure upfront.
The gate supports this by accepting a component filter parameter in the invocation prompt.
When a component filter is provided, content quality checks are restricted to sections of context, architecture, requirements, and traceability documents pertaining to the named component.
Artifact presence checks still apply to the top-level required directories.
If component-scoped evaluation is not feasible (e.g., monolithic documents without per-component sections), treat the gate as evaluating readiness for the full planning pass and rely on incremental seeding to determine which epics to create from validated input.

### Step 2: assess current operational buffer

Count ready, unblocked issues in the current scope.

```bash
bd status
bd blocked
bv --robot-capacity > /tmp/bv-capacity.json
jq '.capacity' /tmp/bv-capacity.json
rm /tmp/bv-capacity.json
```

Compare the ready count against the buffer sizing heuristic to determine whether planning is warranted.

#### Buffer sizing heuristic

The target buffer size is:

```
B* = (k / p) * (1 + CV_p)
```

where:
- *k* is agent throughput: issues completed per unit time (estimated from recent completion rate).
- *p* is planning rate: issues planned per unit time (estimated from recent planning sessions).
- *CV_p* is the planning variability coefficient: standard deviation of planning rate divided by its mean.

Interpretation:
- If the ready (unblocked) issue count is below B*, the buffer is depleted and deeper planning is warranted.
  Proceed through the remaining steps.
- If the ready count meets or exceeds B*, planning capacity should shift to implementation.
  Report the buffer status and recommend proceeding to implementation rather than further planning.

The formula captures the insight that the operational buffer should be large enough to absorb variability in planning throughput.
When planning is highly variable (high CV_p), a larger buffer prevents implementation stalls.
When planning is consistent (low CV_p), a smaller buffer suffices.

In practice, estimate k from `bd activity` (recent closures per session), estimate p from the number of issues created in recent planning sessions, and estimate CV_p conservatively at 0.5 if insufficient data exists.
As the project accumulates history, refine these estimates.

### Step 3: decompose scope into atomic issues

Each issue must have:
- A description sufficient for a worker to self-direct without additional context beyond what the issue and its dependency closure context provide.
- Acceptance criteria with at least one executable verification command when the requirements specification provides them, or descriptive acceptance criteria when it does not.
- A Cynefin classification based on the knowability of cause-effect relationships for that specific work item.

Delegate issue creation to `/issues-beads-seed` for new issues derived from `docs/development/` artifacts.
When restructuring existing issues (splitting, re-scoping, re-parenting), delegate to `/issues-beads-evolve`.

Cynefin modulates decomposition granularity:
- *Clear* domain: light decomposition; issues are already obvious from the specification.
- *Complicated* domain: standard decomposition following the R_plan(d) model.
- *Complex* domain: iterative decomposition producing probe-based experiments as issues.
- *Chaotic* domain: minimal decomposition; stabilize first, plan later.

### Step 4: wire dependencies

Use parent-child relationships for containment (epic contains tasks) and blocks relationships for sequencing (task A must complete before task B can begin).
The dependency graph must be acyclic.

Delegate dependency wiring to `/issues-beads-seed` during initial creation (via `--parent` and `--deps` flags) and to `/issues-beads-evolve` for restructuring existing dependencies.

Refer to the containment-versus-sequencing discipline documented in `/issues-beads-seed` and the "Dependency type discipline" convention in `/issues-beads-prime` to avoid the common structural error of expressing containment as sequencing.

### Step 5: set signal tables on new issues

Each new issue receives a signal table following the schema from `/stigmergic-convention`.

```
<!-- stigmergic-signals -->
| Signal | Value | Updated |
|---|---|---|
| schema-version | 1 | YYYY-MM-DD |
| cynefin | {derived from step 1 gate or explicit classification} | YYYY-MM-DD |
| surprise | 0.0 | YYYY-MM-DD |
| progress | not-started | YYYY-MM-DD |
| escalation | none | -- |
| planning-depth | {derived from cynefin, or explicitly overridden} | YYYY-MM-DD |
<!-- /stigmergic-signals -->
```

Write signal tables using the read-modify-write protocol from `/stigmergic-convention`.
The cynefin and planning-depth values come from the readiness gate's signal derivation (step 1) or from explicit per-issue classification during decomposition (step 3).

### Step 6: verify graph health

After all issues are created and wired, verify structural integrity.

```bash
# Cycle detection — must be zero
bd dep cycles

# Structural lint
bd lint

# Parent-child integrity — every epic should show non-zero children
bd epic status

# Tree view for visual verification
bd list --pretty
```

Perform critical path analysis to identify the longest dependency chain.
This determines which issues, if delayed, extend the total completion time.

```bash
# Dependency graph for each new epic
bd dep tree <epic-id> --direction both
```

If cycles are detected, resolve them before proceeding.
If lint warnings appear, address structural issues.
These checks are performed inline rather than delegating to `/issues-beads-audit` because they are a single step within the planning protocol rather than a standalone maintenance activity.

### Step 7: produce dependency-ordered execution plan

List issues in an order that respects dependency constraints.
Highlight the critical path: the longest chain of sequential dependencies determining minimum total completion time.
Identify which issues can be worked in parallel at each stage of the execution order.

The execution plan serves as the handoff to implementation.
A worker reading this plan should understand what to work on first, what can proceed concurrently, and where the bottlenecks are.

```bash
# Structured plan output
REPO=$(basename "$(git rev-parse --show-toplevel)")
PLAN=$(mktemp "/tmp/bv-${REPO}-plan.XXXXXX.json")
bv --robot-plan > "$PLAN"
jq '.plan.execution_order' "$PLAN"
jq '.plan.critical_path' "$PLAN"
jq '.plan.parallel_groups' "$PLAN"
rm "$PLAN"
```

## Replanning triggers

Four conditions trigger re-invocation of `/session-plan` to restock the operational buffer.

*Surprise accumulation exceeds replanning threshold.*
The `/session-checkpoint` skill detects this condition by computing the sum of surprise scores across session nodes and comparing against threshold theta.
When surprise is high, the existing plan has diverged from reality and requires revision.

*Validation gate completion.*
When `/session-review` completes integration verification at a DAG convergence point, findings may invalidate planning assumptions.
The worker detects this condition and invokes `/session-plan` if the review reveals structural issues.

*Specification change.*
When architecture or requirements documents are revised, the planning assumptions that produced the current buffer may be stale.
The worker detects this condition and invokes `/session-plan` to reconcile the buffer with the updated specifications.

*Buffer depletion.*
When the ready issue count drops below B*, the buffer can no longer sustain continuous implementation.
The `/session-checkpoint` skill detects this condition via buffer depletion alerts in the handoff narrative.

In all cases, begin with step 1 (readiness gate) to validate that the input artifacts remain sufficient, then proceed through the remaining steps to restock the buffer.

## Cynefin modulation within planning

Cynefin classification modulates how deeply this skill executes, not whether the worker enters the planning phase.

| Cynefin domain | Planning behavior |
|---|---|
| Clear | Light: issues are already obvious from the specification. Minimal decomposition, direct acceptance criteria. |
| Complicated | Standard: full R_plan(d) decomposition with buffer sizing, analytical acceptance criteria. |
| Complex | Iterative: probe-based experiments as issues. Each probe is time-boxed exploration with sense-making checkpoint. Further decomposition deferred until after probe completion. |
| Chaotic | Minimal: stabilize first, plan later. Only act-sense-respond issues are created. Long-term planning explicitly deferred. |

## Typical next steps

After planning completes, the worker proceeds to one of:

- Implementation if the operational buffer is now full and issues are ready with clear acceptance criteria and verification commands.
- `/session-orient` if scope changed during planning and re-calibration is needed before selecting work.
- Further `/session-plan` if the buffer is still depleted after the current planning pass (rare; usually indicates the scope is too large for a single planning session and should be narrowed).

---

*Composed skills (delegate, do not duplicate):*
- `/issues-beads-seed` -- issue graph creation from `docs/development/` artifacts
- `/issues-beads-evolve` -- graph structure refinement (splitting, merging, re-parenting, rewiring)
- `/stigmergic-convention` -- signal table schema and write protocol

*Related skills:*
- `/session-orient` -- strategic horizon session start, provides discovery findings as input
- `/session-checkpoint` -- all-horizon state capture, detects replanning triggers
- `/session-review` -- convergence-point validation, may trigger replanning
- `/issues-beads-prime` -- core beads conventions and command quick reference
