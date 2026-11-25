---
description: Reference-code convention for findings and decisions, the scr/foc/ref/eli aliases, avoided phrases, the blocking-questions numbered-list protocol, and the rule that keeps coordination labels out of commits, pull requests, issues, comments and docs.
---

## Communication

When presenting three or more findings, decisions, options, risks, questions, or actions, assign each a short reference code and reuse the same codes for the rest of the conversation: D for decisions, O for options, F for findings, R for risks, Q for questions, A for actions.
Do not create codes for short, simple answers.
This namespace is conversational only: a reference to an OpenSpec design decision stays qualified — "design D9", or the change id — so a conversational D1 is never confused with a numbered design decision in the same exchange.

Four aliases expand only as standalone tokens; inside a longer string they are ordinary text.
- `scr` — simplify, compress, restate the same content shorter, with no new material.
- `foc` — identify the single highest-value thread and answer only that, dropping the rest.
- `ref` — rewrite the previous response using reference codes.
- `eli` — reduce vocabulary and sentence length for a general reader without discarding technical content.

Avoid these phrases in our own prose: "load-bearing", "worth stating plainly", "here's the honest truth", "the real tension", "carry the argument".
This governs chat and written output; it does not replace the `unslop` skill, which owns artifact rewriting.

When two or more questions genuinely block progress, print them as a numbered list, one line each, with a recommended answer under each; the human replies only with the numbers whose recommendation they want changed, and silence on a number means the recommendation stands.
A single question stays inline in prose.
Silence never adopts a recommendation that is destructive, irreversible, security-sensitive, or spends money — those always require explicit words.
The questions are printed in the response.

Lead with the conclusion and follow with evidence; closing lines carry the decision or the next action, not a summary of what was already said.

## Outward-facing writing

Commit subjects and bodies, pull-request titles, bodies and review comments, Linear issue titles and descriptions, code comments, docs, ADRs, changelogs and messages shown to users are read later by someone who was not there.
Write each so that a reader with only that text and the repository at that commit understands what changed and why.

Take every noun from the repository — a package, file, option, check, systemd unit, command or host — or from a system that reader can open: a Linear key, a pull-request number, a commit on `main`, an OpenSpec change, an ADR.
Use a term we coined only where the text says what it means.
A name points to more detail; it never replaces saying what changed.

Labels invented to coordinate the work meet neither requirement, so they stay in conversation, subagent briefs and the plan that defines them: stage, wave or task numbers, codes such as Q1 or D3, agent and session names, "the operator" as the one who decides, jj change ids of unpublished work, and "the plan" or "the earlier fix" when the text does not say which.
An OpenSpec change's own files (`openspec/changes/**`) may use its task numbers and design ids and, like ADRs and other decision records, hold the dated record of who decided what; cited from anywhere else, state what the task does or the reason the decision gives, then give the file.
A new heading in those files should name its content rather than an ordinal.
Everywhere else, state what the repository now does and the reason, never who chose it or that and when it was decided, approved or authorized: no "the operator", "we decided", "per the decision of <date>", "approved by" or "at the request of".
When the only reason is that it was chosen, state the fact alone.

Do `refactor(pkgs): move six vendored and registry packages to pin.json`, not `refactor(pkgs): stage 2 wave 3 — vendor and registry pins`.
Do "xsra keeps its `update.sh` and is updated by hand, because a `Cargo.lock` regenerated against crates.io cannot be reproduced later", not "xsra stays on its `update.sh`, by the operator's decision of 2026-11-25".
Do `feat(otel): drop omp caption spans from Langfuse, exempt the session collector from the fleet envelope`, not `feat(otel): apply the operator's 2026-11-24 telemetry decisions`.
Do `# Reverting to the stock evaluator replaces the one line below.`, not `# Reverting to the stock evaluator, the safety valve of CAM-111 design D9, replaces the one line below.`
