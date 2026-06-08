# Codex review (the roborev sub-gate binding)

This runbook binds the abstract roborev sub-gate to a concrete inline codex review.
The board re-cast onto Linear (references/board-and-gates.md) decomposes In Review into two ordered human-steered sub-gates, roborev first and documenter second; delegation.md states roborev is the code-review point linking out from the superpowers-bridge apply and verify stage, and records that automation hooks may later compose into the gate without introducing a fourth agent.
This file is that automation hook for roborev only.
It does not wire the documenter sub-gate, and it does not touch any schema.yaml.

The reviewer is the codex CLI driving a different model family than the Claude author, so the review is genuine cross-model evidence rather than a self-check.
The binding is advisory in all three execution modes (AFK, HIL, Manual): codex produces a verdict and findings as evidence, and a human or the orchestrating session always makes the advance-versus-re-queue decision.
Even AFK pauses at In Review for human adjudication and does not auto-advance on a codex pass; the existing currently-human-steered clauses in board-and-gates.md and delegation.md stay, and codex layers under them as the evidence generator.
This augments superpowers:requesting-code-review rather than replacing it: the superpowers apply-phase review continues alongside, and codex is the board-level roborev binding presented when the unit reaches the roborev sub-gate.

## Resolve the review range from the change's bookmark

codex reviews exactly the change's own commits, expressed as a two-SHA `git diff BASE TIP`.
The repository runs jujutsu in colocated mode, so a bookmark is a git branch and the range is recomputed live from that bookmark.
Recompute BASE and TIP at every invocation and never cache them: the diamond development join reshapes mid-session as chains are added, routed, or linearized, and a cached SHA silently reviews the wrong range.

Precondition: the change's bookmark must be a current join parent, one of `parents(@-)`.
The robust BASE revset below isolates the chain's own commits by excluding the sibling join-parents' ancestries and main; that exclusion only holds while the bookmark is still a join parent.
If the chain has already been linearized or detached from the join, the exclusion set does not hold; derive BASE differently and confirm the derivation with the orchestrator before proceeding.

Resolve TIP and BASE from the bookmark (replace `BOOKMARK` with the change's bookmark name).
Both commands pass `--ignore-working-copy` so resolution is read-only and does not snapshot the working copy: a bare `jj log` snapshots `@` and writes the op-log by default, which would mutate state during a review that must observe only.

```bash
TIP=$(jj log --ignore-working-copy --no-graph -r 'BOOKMARK' -T 'commit_id')
BASE=$(jj log --ignore-working-copy --no-graph -r 'parents(roots(::BOOKMARK ~ ::(parents(@-) ~ BOOKMARK) ~ ::main))' -T 'commit_id')
```

The robust revset is required because the naive merge-base or fork-point base is wrong under diamond stacking.
`roots(::BOOKMARK ~ ::(parents(@-) ~ BOOKMARK) ~ ::main)` takes the bookmark's ancestry, subtracts every sibling join-parent's ancestry and main's ancestry, and takes the roots of what remains, leaving only the chain's own first commit; BASE is that commit's parent.
A merge-base against main instead leaks the sibling chains that share the working copy: on a live diamond the merge-base base produced a 44-file diff (sibling chains pulled in) where the robust revset produced the clean 7-file chain scope.
A two-SHA `git diff BASE TIP` is independent of the working copy, the index, and HEAD (verified stable while `@` was dirty), which is what makes the review diamond-safe even though sibling chains coexist in the one working copy.

Validate each SHA separately before running codex; each must resolve to a commit object:

```bash
git cat-file -t "$BASE"   # must print: commit
git cat-file -t "$TIP"    # must print: commit
```

Validate them one at a time. `git cat-file -t "$BASE" "$TIP"` errors with too-many-arguments and is not a substitute for two separate checks.

Non-jj fallback: in a plain git repository with no diamond, resolve `BASE=$(git merge-base main BRANCH)` and `TIP=$(git rev-parse BRANCH)`.
There the merge-base base is correct because no sibling chains share the working copy, and codex's own `--base` handling is acceptable.
Inside the jj diamond it is not; use the robust revset above.

## The codex invocation

Use plain `codex exec` with `--output-schema`, not the native `codex review` or `codex exec review` subcommand.
The native review subcommand does not return a machine-parseable typed verdict: it drops the ExitedReviewMode event from `--json` and writes lossy prose to `-o`, so the gate cannot read a structured result from it.
Plain `codex exec` with a strict output schema returns the typed JSON the gate needs.

The verified-working invocation (uppercase tokens are placeholders; the prompt is piped on stdin because codex reads the prompt from stdin in non-TTY contexts):

```bash
printf '%s' "$WRAPPER_PROMPT" \
  | codex exec -C "$REPO" -s read-only -m gpt-5.5 \
      -c model_reasoning_effort="$LEVEL" \
      --output-schema "$SCHEMA_JSON_PATH" \
      -o "$OUT_JSON_PATH"
```

The flags are top-level `codex exec` options confirmed against codex-cli 0.137.0 and the openai/codex source, and precede the piped prompt: `-C, --cd` sets the working root, `-s, --sandbox read-only` is sufficient because codex runs `git diff` itself and performs no writes, `-m, --model` pins gpt-5.5, `--output-schema <FILE>` points at the JSON Schema file, and `-o, --output-last-message <FILE>` writes the agent's final message to `OUT_JSON_PATH`.
These flags and the `-m gpt-5.5` pin are verified against codex-cli 0.137.0; re-verify on a codex bump, since the model slug rotates and `-m` is optional (omitting it defers to codex's own default and degrades gracefully on a model deprecation).

The reasoning effort is set through the `-c, --config key=value` override; there is no dedicated reasoning-effort flag.
The verified key is `model_reasoning_effort`, whose `ReasoningEffort` enum in the codex config schema is `none | minimal | low | medium | high | xhigh`, so all four calibration levels below are valid values.

The orchestrating session calibrates `LEVEL` per invocation to the change's complexity and correctness-criticality, reading the signals the workflow already tracks (the Cynefin classification, the severity, and the diff size and file count); a human may override.

| Level | When to select |
|---|---|
| low | trivial, mechanical, or docs-only changes |
| medium | an ordinary feature or fix (the default) |
| high | large or complex diffs, or correctness-sensitive surfaces (secrets, deploy or terranix, schema, security-relevant logic, irreversible operations) |
| xhigh | archive-gating changes, or anything the workflow's Cynefin signal classifies Complex or Chaotic |

## The wrapper prompt

The wrapper prompt fixes the change set to the resolved range and carries the review rubric.
Build it with `BASE` and `TIP` already interpolated, then pipe it to codex as `WRAPPER_PROMPT`.
A reusable template:

```text
You are reviewing a single change set as a code reviewer from a different model family than the author.

Obtain the change set by running exactly these two commands and review ONLY their output:

    git diff BASE TIP
    git log --no-patch BASE..TIP

The first is the change's diff; the second is the in-range commit messages that state what the
change claims to accomplish.

Do not inspect uncommitted or working-copy changes, the HEAD commit, the index, or any commit
outside the BASE..TIP range. Sibling chains of unrelated work are present in this working copy
and are out of scope; reviewing anything outside the output of those two commands is an error.

Review for two things:
  1. Correctness bugs in the diff.
  2. Spec and scope discipline: does the change accomplish what its commit messages claim,
     no more and no less?

Set `overall_correctness` to EXACTLY one of the enum values "correct" or "incorrect", with no other phrasing.

Your final message MUST be a single JSON object matching the provided output schema, and nothing else.
```

Interpolate the resolved SHAs into both the `git diff BASE TIP` and `git log --no-patch BASE..TIP` lines before piping (for example with `printf` substituting `$BASE` and `$TIP`), so codex runs the exact two-SHA diff and reads only the in-range commit messages, both inheriting the diamond-safe isolation.

## The output schema

Write this schema to a temporary file under the job's tmp directory and pass that path as `SCHEMA_JSON_PATH`.
Do not create a separate tracked schema file; keep it inline here.
It is a strict OpenAI structured-output schema: every property is listed in `required`, and `additionalProperties` is `false` at every object level.

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": [
    "overall_correctness",
    "overall_explanation",
    "overall_confidence_score",
    "findings"
  ],
  "properties": {
    "overall_correctness": { "type": "string", "enum": ["correct", "incorrect"] },
    "overall_explanation": { "type": "string" },
    "overall_confidence_score": { "type": "number", "minimum": 0, "maximum": 1 },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["title", "body", "priority", "confidence_score", "code_location"],
        "properties": {
          "title": { "type": "string" },
          "body": { "type": "string" },
          "priority": { "type": "integer", "minimum": 0, "maximum": 3 },
          "confidence_score": { "type": "number", "minimum": 0, "maximum": 1 },
          "code_location": { "type": "string" }
        }
      }
    }
  }
}
```

`overall_correctness` is an enum constrained to exactly `correct` or `incorrect`; `priority` is an integer where 0 is the highest severity and 3 is the lowest; `code_location` is a `path:line` string or an empty string.

## Verdict handling as a triage surface

Parse `OUT_JSON_PATH` after the run.
Because the schema constrains `overall_correctness` to the enum `correct | incorrect`, match it by exact equality: a PASS signal is `overall_correctness == "correct"`, and a blocking changes-needed signal is `overall_correctness == "incorrect"`.
The enum makes exact equality the correct and safe check, with no string values such as `not correct` or `mostly correct but blocking` that a substring match would misclassify.

The findings are a triage surface, not an autonomous block.
The recommended-blocking set is the findings with `priority <= 1` (P0 plus P1) together with the overall `incorrect` signal.
Present all findings to the orchestrating session grouped by priority, with the recommended-blocking set flagged as the default must-address set, and use the priority as the sort key.

The orchestrating session, or a human, then chooses the subset to address and offers the explicit choice: address the chosen subset, accept the rest, and advance; or re-queue with the chosen subset as fix tasks.
The human or session triage decision drives the transition, not the raw threshold.
The threshold is a recommendation and a sort key, and a hook for a future opt-in policy that would let AFK auto-advance when no P0 or P1 finding is present; until that policy exists the gate stays advisory in all modes and never auto-advances on a codex pass.

## Panel mode (optional, for contested or high-criticality verdicts)

A determinism probe ran the same codex review five times against an already-approved commit: two runs returned `correct` with zero findings, while three returned `incorrect` with P1 findings, and the rejecting runs' findings were mostly distinct one-offs with only one finding recurring across two runs.
A single codex verdict is therefore non-deterministic and biased toward finding problems, so a single verdict in either direction is advisory only: a lone pass may be a lucky sample and a lone fail may be one-off noise.
Findings that recur across independent identical runs are credible while one-offs are likely noise, which is what justifies the advisory-everywhere framing, the bounded `review_round`, and the human-decides-the-transition design throughout this runbook.
Panel mode operationalizes that observation for the verdicts where it matters; it is optional and never the default.

The default is the single round already documented above; panel mode runs that identical round K times and aggregates.
Each panel sample reuses the exact single-round invocation unchanged: the same frozen wrapper prompt, the same output schema, the same `gpt-5.5` model, and the same `model_reasoning_effort` level, with the same BASE and TIP range resolved once and held across the K runs.
The aggregate verdict is the majority of the K `overall_correctness` values.
For an even K with a tied `overall_correctness` split, the aggregate resolves to the conservative verdict (treat as incorrect and re-queue), since the gate is advisory and biased toward surfacing problems.
The recommended-blocking set is the findings that recur in at least a strict majority `floor(K/2)+1` runs (at least 2 of 3, and at least 2 of 2 at K=2), matched by `code_location` together with title or topic; a finding appearing in fewer than `floor(K/2)+1` runs is demoted to advisory-only, surfaced to the orchestrating session but not flagged as recommended-blocking.
Default K is 3 when panel mode is invoked, and K is overridable.

There are two entry paths into panel mode.

The normal path is escalate-after-round-1.
Run the default single round first; the orchestrating session or a human may then escalate.
Round 1 counts as sample 1 because the runs are i.i.d., so escalation runs `K - 1` additional identical rounds to reach K and round 1 is not discarded.
Escalate specifically before a re-queue on findings, to confirm the blocking findings recur rather than being one-off noise, and before advancing a high-criticality change on a clean single pass, to confirm the pass is not a lucky single sample.
A low-stakes change with a clean round 1 needs no escalation.

The upfront path is for known high-criticality changes.
For archive-gating, security-relevant, irreversible, or Cynefin Complex or Chaotic changes the session or human may request panel mode at review-phase initiation, phrased like "run the third-party codex review via panel mode with K=3" (override for example "with K=2"); K defaults to 3 if unspecified.

Review mode and K scale with the same signal as the reasoning-effort calibration table above: a trivial or docs-only change takes a single round with no escalation, an important or correctness-sensitive change escalates-after-round-1 when the verdict is contested, and an archive-gating or critical change takes upfront panel mode with K at least 3.
The mode and the effort level read the same Cynefin classification, severity, and diff-size-and-file-count signals, so the `xhigh` row of the effort table and the upfront panel row select together for the same changes.

Panel mode multiplies the per-gate codex spend by K, so reserve it for consequential or contested verdicts rather than running it by default.

## Verdict to board mapping

The triage decision maps onto the board exactly as the existing roborev sub-gate already routes.

An accept decision advances the unit to the documenter sub-gate, which runs second and whose joint approval with roborev is the precondition for the archive gate.
codex plugs in strictly upstream of the existing In Progress to In Review to Done transitions and adds no new board state.

A re-queue decision routes through the shared re-queue node into In Progress above the mode fork (In Review to In Progress), carrying the chosen findings as fix tasks, exactly as board-and-gates.md describes for a sub-gate rejection.
A re-queue increments `review_round` in the change's proposal.md frontmatter; the ceiling is linear.yaml `defaults.max_review_rounds` (default 3, overridable per change in frontmatter).
This verify.md-checkbox recording plus the review_round increment is the HIL realization of the re-queue; the codex advisory verdict is generated identically in all three modes, but in AFK the re-queue is recorded against the plan completion record and in Manual via the human-rejection re-queue path at a session-checkpoint, neither of which carries a verify.md or a review_round counter.
On exhaustion, escalate to the human PM layer and stop auto-re-queue, parking the unit, per the bounded-retries policy.

To drive the existing machine-detected re-queue rather than inventing a new artifact or board state, a re-queue decision checks the existing verify.md decision checkbox.
Change the Overall Decision line from `- [ ] (fail) FAIL` to `- [x] (fail) FAIL`.
Both the re-queue logic in openspec-linear-sync and the superpowers-bridge retrospective PRECHECK grep the anchored, checked form (the rg/ERE pattern `^- \[x\] \(fail\) FAIL`, equivalently the BRE-literal `^- \[x\] (fail) FAIL` the schema PRECHECK uses; the escaped parens match under rg or grep -E but a plain BRE grep needs the literal-paren form); writing the bare string without checking the box is inert.
Preserve this exact vocabulary.

Linear receives the codex findings as a best-effort comment summarized to at most two sentences, honoring the openspec-linear-sync comment invariant, with the full detail kept in-repo (for example the out.json artifact retained in the change directory).
The comment obeys the existing drop-and-log graceful-degradation contract: if posting fails, drop the comment, log the drop, and proceed.
codex introduces no new Linear state.

## Preconditions and cautions

codex needs network egress to OpenAI to run.
This works on the host, where the user is already OAuth'd into codex locally, so no extra credential is needed for local runs; it fails inside a network-restricted nested sandbox.
`-s read-only` is sufficient because codex runs `git diff` itself and performs no writes.

A live smoke test this session is the evidence the mechanism works end to end: the `codex exec --output-schema` invocation returned valid schema-matching JSON, with `overall_correctness` of `incorrect`, three findings at priorities [1, 2, 2], and every `code_location` in scope (only files under the reviewed chain), which demonstrates both the schema coercion and the diamond-safe diff isolation that the robust BASE revset provides.
