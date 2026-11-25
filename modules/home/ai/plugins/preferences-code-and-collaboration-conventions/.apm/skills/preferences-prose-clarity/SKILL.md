---
name: preferences-prose-clarity
description: Sentence-level prose discipline grounded in reader-expectations research (Gopen & Swan, Pinker, Williams, Thomas & Turner, McEnerney). Use when writing or editing any prose — documentation, commit messages, working notes, published AGENTS.md or CLAUDE.md files, reports, PR descriptions — when reviewing text for clarity or AI-writing patterns, when calibrating certainty of claims, or when making the smallest safe repair to someone else's text.
---

# Prose clarity

Every rule below serves one criterion: minimize reader processing cost.
The grounding is Williams, Gopen & Swan, Pinker, Thomas & Turner, and McEnerney; reason from those frameworks, not Strunk & White folklore.

## The rules

1. Curse of knowledge: before writing, name the intended reader.
    Define any term that reader would pause on.
    Give a one-sentence map before a multi-paragraph argument.
    A frequent case is an undefined internal reference: a stage, wave or task number, a conversational code such as Q3, an agent name, or "the plan", which the reader has no way to look up.
    Repair it by stating what the label stood for; keep a pointer only if the reader can follow it (see the outward-facing writing rule in `agent-context-core`).
2. Old before new: open sentences with information the reader already has (topic position); land the key new information at the end (stress position).
    Reorder before you cut.
3. Characters as subjects, actions as verbs: repair nominalizations ("the failure of X to act" becomes "X failed to act"), except technical terms and nouns serving as the established topic.
4. Locality: keep subject, verb, and object close; avoid center-embedding; split sentences over ~30 words; vary sentence length and structure.
5. Cohesion and coherence: within a paragraph, keep a consistent topic thread across sentence subjects, and make exactly one stated point.
    For multi-paragraph text, fix the point and structure first, sentences second.
6. Concreteness: prefer specific words over abstractions; replace vague evaluation with a mechanism, action, or measure.
7. Calibrated claims: match certainty to evidence.
    Keep hedges that carry information ("suggests", "n=3", "consistent with", confidence intervals); cut hedges that carry none ("it's worth noting", "arguably", throat-clearing openers).
    Never strip epistemic qualifiers from scientific or technical claims.
8. Passive voice is correct when the agent is unknown or irrelevant, or when it serves rules 2 or 5; otherwise prefer active.
9. No slop: no formulaic scaffolding ("In today's …", "Here's the thing", "Let's dive in"); no "it's not X, it's Y" tics; no stock phrases or dead metaphors ("game-changer", "leverage", "delve", "landscape"); no transition chains ("Additionally… Furthermore… Moreover"); no paragraph-closing recaps or moralizing codas; no converting prose to bullets unless the content is a genuine list; one consistent term per concept; never fabricate citations, numbers, or support.
10. Stance: default to classic style — direct, confident, prose as a transparent window, reader as an intellectual equal.
    Frame the text inside the reader's problem, not the writer's process.
11. Editing others' text: make the smallest repair that fixes a confirmed defect; preserve facts, quantities, names, dates, quotes, code, units, scope, attribution, register, voice, and epistemic qualifiers; add no claims; prefer a no-op over an uncertain edit.
12. Escape hatch: break any rule here sooner than write something awkward or ambiguous.
    When rules conflict, minimize reader processing cost.

## Conversational register

The rules above govern prose on the page; they govern a chat-style answer the same way, where the closing line is what the reader acts on.

A factual investigation, asked as a yes-or-no question.
Do: "No: `fetch_with_backoff` only retries on 5xx, a timeout raises immediately, and the caller in `sync.rs:112` doesn't catch it, so a slow network drops the sync silently."
Do not: "I traced through `fetch_with_backoff`'s retry logic; there's handling for several error categories, and timeouts might fall into one that isn't fully covered, though it's hard to say without digging further."
The do-not side never answers the question asked; the hedge substitutes for a decision the evidence already supports.

An engineering recommendation.
Do: "No. The handler is idempotent and the caller already retries with backoff; a second retry layer would double-process events on partial failure. Leave it as-is."
Do not: "That's a good question — there are real tradeoffs either way, since a retry queue adds resilience but also complexity. It depends on your priorities."
The do-not side opens with unearned agreement and closes by summarizing the tradeoff instead of choosing one.

## Highest-blast-radius prose

Published, binding, or long-lived prose — repo-level AGENTS.md and CLAUDE.md files, specs, API-adjacent docs — gets strong care under this skill, not fast decisions.
For such files, name the cold reader explicitly: an agent or human with no ambient context about the machines, conventions, or history the author takes for granted.

## Related skills

For bulk de-slopping of AI-generated text, use the `unslop` skill's audit and two-pass rewrite flow; this skill supplies the standing criteria it operates under.
For document structure, frontmatter, and provenance conventions, see `preferences-documentation`.
For file-level markdown formatting and naming, see `preferences-style-and-conventions`.
