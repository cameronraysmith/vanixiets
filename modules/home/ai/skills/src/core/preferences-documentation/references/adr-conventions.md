# ADR authoring conventions

Architecture Decision Records capture the reasoning behind architecturally significant choices.
These conventions govern the structure, lifecycle, and authoring discipline for ADRs stored in `docs/development/architecture/adrs/`.
Source material: Richards/Ford, *Fundamentals of Software Architecture* ch 21.

## Section structure

Every ADR contains seven sections in this order.
Maintain this structure consistently across all ADRs to enable comparison and review.

1. *Title* — a sequential number and short descriptive phrase that removes ambiguity about the nature and context of the decision. Use YAML frontmatter `title: "ADR-NNNN: Descriptive Phrase"` per the markdown formatting conventions in SKILL.md. Example: `ADR-0042: Use of Asynchronous Messaging Between Order and Payment Services`.

2. *Status* — one of: Proposed, Accepted, or Superseded. Include the date. Optionally include Scope and Related fields as structured metadata following the repo's established pattern (see existing ADRs for format).

3. *Context* — the forces and constraints driving the decision. Describe the situation creating the decision pressure, the area of architecture being decided upon, and the alternatives under consideration. Concise but sufficient for a reader encountering this decision for the first time.

4. *Decision* — the decision itself, stated in affirmative commanding voice ("We will use..." not "I think..."). Include both technical and business justification. Understanding *why* the decision was made matters more than describing *how* to implement it. Business justifications typically fall into four categories: cost, time to market, user satisfaction, and strategic positioning. If a business justification cannot be articulated, reconsider whether the decision should be made.

5. *Consequences* — trade-off analysis covering positive, negative, and neutral impacts. Organize using labeled subsections (Positive, Negative, Neutral) as established in the repo's existing ADRs. This section forces evaluation of whether negative impacts outweigh benefits.

6. *Compliance* — how the decision will be measured and governed. Specify whether compliance is verified through manual review or automated checks. In a Nix infrastructure context, automated compliance maps to `nix flake check`, NixOS module system assertions, CI workflow validations, or property-based tests rather than traditional software fitness functions like ArchUnit.

7. *Notes* — metadata: original author, approval date, approved by, superseded date, last modified date, modified by, last modification description.

## File naming and storage

Store ADRs in `docs/development/architecture/adrs/` with zero-padded four-digit numbers and descriptive kebab-case slugs: `0042-asynchronous-messaging.md`.
Maintain an `index.md` in the same directory as a categorized navigation hub.
For decisions that span multiple repositories, store the ADR in the repository that owns the primary implementation and cross-reference from affected repositories.

## Status lifecycle

ADRs progress through a defined lifecycle.

*RFC* is an optional pre-stage used when a decision benefits from structured feedback before formal proposal.
Set a deadline for the RFC period.
After the deadline, analyze comments, adjust the decision, and advance to Proposed or Accepted.

*Proposed* indicates the decision awaits approval from the relevant governance or review process.

*Accepted* means the decision is ratified and ready for implementation.

*Superseded* marks a decision that has been replaced by a subsequent ADR.
When superseding, update both records: mark the old ADR "Superseded by ADR-NNNN" and the new ADR "Accepted, supersedes ADR-NNNN."
This bidirectional link prevents re-litigating previously-rejected alternatives.
Only Accepted ADRs can be superseded; Proposed ADRs are modified in place rather than superseded.

## Commanding voice

State decisions in affirmative commanding voice throughout the Decision section.
Write "We will use asynchronous messaging between services" rather than "I think asynchronous messaging would be the best choice."
The commanding voice makes clear that a decision has been made, by whom, and what it entails.
This convention applies to the Decision section specifically; the Context section naturally uses descriptive rather than commanding language.

## What constitutes an architecturally significant decision

Not every technical choice warrants an ADR.
In an infrastructure-as-code context, architecturally significant decisions include changes to deployment topology, module composition patterns, secrets management strategy, network configuration, and platform selection.
Individual package additions, routine configuration adjustments, and implementation details within an established pattern do not qualify.

The qualification test from Richards/Ford applies: if the decision cannot be justified with both a technical and business rationale in the Decision section, it may not be architecturally significant enough to warrant an ADR.
Use ADRs to qualify whether a proposed standard should exist. If the architect cannot articulate the justification, reconsider the standard.

## Antipatterns

Three antipatterns undermine effective architectural decision-making.

*Covering Your Assets* occurs when decisions are avoided or deferred out of fear of being wrong.
The countermeasure is deciding at the last responsible moment: the point where the cost of deferring exceeds the risk of deciding with incomplete information.
When presenting architectural options, identify where on the cost-risk curve the decision currently sits.
If sufficient information exists, recommend a decision.
If not, identify what information would reduce risk and propose how to gather it.

*Groundhog Day* occurs when people endlessly re-discuss a decision because they do not understand why it was made.
The root cause is insufficient justification, particularly missing business justification.
This is the primary reason every Decision section must include business rationale, and the primary value of maintaining ADRs at all.

*Email-Driven Architecture* occurs when decisions are communicated via email or chat rather than linked from a single system of record.
This creates multiple inconsistent copies and makes updates unreliable.
When communicating decisions, reference the ADR location (file path in the repository) rather than inlining the full decision content.
Notify only directly impacted stakeholders.

## Reconciling existing ADR collections

The repository currently contains two ADR collections with divergent conventions: 17 formal ADRs in `docs/development/architecture/adrs/` (conforming to these conventions) and 6 working-note ADRs in `docs/notes/development/kubernetes/decisions/` (simpler structure, different naming).
These conventions prescribe the formal structure.
The working-note ADRs follow the `docs/notes/` lifecycle described in SKILL.md: they should eventually be migrated to the formal structure or discarded when no longer relevant.

## Relationship to architecture diagrams

ADRs and architecture diagrams are complementary perspectives on the same architectural artifact.
Diagrams visualize the structure and relationships; ADRs document the reasoning behind those structures.
When an ADR describes a decision that affects system topology, deployment architecture, or component relationships, cross-reference the relevant architecture diagrams.
When architecture diagrams depict structures resulting from deliberate decisions, reference the governing ADR.
For diagramming conventions, see `preferences-architecture-diagramming` when available.
