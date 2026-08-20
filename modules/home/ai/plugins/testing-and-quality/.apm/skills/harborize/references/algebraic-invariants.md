# Algebraic invariants (review gate)

Each invariant states the mathematical form, the operational check, and what
breaks if it fails. Audit every package against all seven; record pass/fail
with one line of evidence in the package README.

## 1. Truncation — verifier as decidable proposition on final state

Form: φ = (−1)-truncated predicate on States, composed with the reflection
Traj → State. Path data is discarded by construction.

Check: the verifier reads only final filesystem state and declared artifacts;
no transcript parsing; grep verifier/ for reads outside /app, /logs/artifacts.
If graded (Reward Kit), each criterion is still a function of final state;
judge criteria are flagged as the approximate nucleus and quarantined in the
separate verifier container.

Failure mode: a path-dependent verifier measures the harness's style, not the
skill's efficacy, and breaks cross-harness comparability.

## 2. Inhabitation — oracle as witness

Form: the task type is inhabited; oracle : ⊤ → φ.

Check: oracle passes 5/5 under both runners before any agent run counts.
Flaky oracle ⇒ the reward channel has noise floor ≥ flake rate; fix first.

## 3. Non-triviality — □_S ⊬ φ

Form: the skill-graded context lowers the derivation cost of φ without
containing a derivation.

Check: `scripts/audit_leakage.py` — no verifier expectation string-recoverable
from skill content; no complete solution embedded in the skill; verifier in
separate environment so grading logic is invisible to the agent. If the skill
ships a script that IS the solution, parameterize task inputs so running the
script still requires correct invocation, adaptation, or composition.

Failure mode: measurement is vacuous — you measured copying.

## 4. Coupling — paired evaluation shares the task, not the randomness

Form: contrasts are estimated under a coupling in the Markov category: joint
over tasks, marginalized to conditions.

The coupling is exact at the task level and positional within a task. Neither
Harbor nor BenchFlow exposes a per-trial seed at the revisions this skill pins,
so replicate k of one condition and replicate k of another share the task and
the ordinal, not a randomness object. Trial ordinals are assigned by
`collect_rewards.py`. Do not claim a shared seed; state the pairing that
actually holds.

Check: every reported delta is computed per-(task, trial) then aggregated;
identical instructions, images, and verifier across conditions; conditions
differ ONLY in the materialized skills directory. Never compare condition means
computed over different task subsets. `analyze_lattice.py` intersects the
(task, trial) keys of every arm and prints what each arm contributed and what
was dropped; that line is the evidence this invariant cites.

## 5. Grade discipline — conditions are points of the lattice, nothing more

Form: E : 2^𝒫 → [0,1]; the interpretation varies only in the coeffect grade.

Check: `materialize_conditions.py` is the only mechanism that varies between
conditions. No condition-specific Dockerfiles, instructions, or verifiers.
Non-monotonicity is expected, not an anomaly: never infer E(A∪B) from E(A),
E(B). Second difference Δ_uv = E({u,v}) − E({u}) − E({v}) + E(∅) is the
interaction; Möbius inversion over observed subsets gives attribution when the
design covers them.

Two structural facts about the units and about dir(C) hold this invariant up.

A plugin unit is derived through the skill-to-plugin membership map the census
emits, never by directory structure: the deployed tree a harness reads is flat,
one directory per skill, with no plugin directories and no `.apm/` paths, so a
plugin unit has no directory to point at. A design that resolves plugin units
by walking the filesystem silently gets a different unit set on the deployed
tree than on the source tree.

dir(C) must contain skill directories and nothing else. Harbor's
`_find_skill_dirs` raises on a root holding a non-hidden child directory
without a `SKILL.md` (harbor `src/harbor/skills.py:382-416`), so a stray
directory turns the whole condition into a hard error. `materialize_conditions.py`
refuses to replace a destination holding anything but skill folders for this
reason, and refuses a destination a Dockerfile above it would COPY into an
image, since baking dir(C) into a build context makes the image vary with the
condition.

## 6. Empirical naturality — portability as uniformity over cells

Form: the skill's benefit Δ should be (lax-)natural in the (model, harness)
index; the grid samples dinaturality at finitely many objects.

Check: report per-cell Δ side by side. Same sign and comparable magnitude ⇒
the portability claim is supported at the sampled objects. Sign flips ⇒ the
skill's value is model- or harness-idiosyncratic; say so, do not average it
away.

## 7. Nucleus hygiene — know which closure operator you are using

Form: exact nucleus where φ is decidable; approximate nucleus (LLM judge,
ε-idempotent under stochastic verification) only where it is not.

Check: the package README lists, per criterion, exact vs judge. Judge criteria
carry k ≥ 3 trials and report agreement; a judge criterion that disagrees with
itself across trials at rate ≥ ε is noise, not signal — tighten the rubric or
demote the criterion to qualitative.
