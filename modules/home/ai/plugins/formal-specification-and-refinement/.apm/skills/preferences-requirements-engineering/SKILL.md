---
name: preferences-requirements-engineering
description: >
  Meta-requirements discipline for requirements-like documents and the bridge from them to a formal
  spec, grounded in the WRSPM reference model of Gunter, Gunter, Jackson and Zave. Load when
  authoring or reviewing a requirements document, deciding whether a statement belongs in the world,
  the requirements, or the specification stratum, grounding a term in a designation table, separating
  indicative assumptions from optative goals, restricting a specification to shared phenomena,
  running obstacle analysis to find where a satisfaction argument fails, specialising to a physical
  world via Parnas' four-variable model, or reconciling an AMDiRE-shaped document tree against the
  world/machine boundary. Owns the satisfaction argument as a maintained artifact. Defers the
  program-refines-spec leg to refinement-driven-development, the audit procedure to
  satisfaction-argument-audit, contract and institution algebra to preferences-theoretical-foundations,
  and confidence calibration to preferences-validation-assurance.
---

# Requirements engineering

This skill owns the layer above a formal specification: what a requirements document must contain, what may not be smuggled into it, and how the claim that the specification actually delivers the requirement is stated and maintained.

The framework is WRSPM, the reference model of Gunter, Gunter, Jackson and Zave, built on Zave and Jackson's four dark corners of requirements engineering and on Jackson's world-and-the-machine distinction.
Its value over a good-requirements checklist is that its meta-requirements are entailment obligations rather than stylistic advice, which makes them checkable.

## The pentad

Five artifacts, distinguished by whose vocabulary they are written in and what they are for.

*W*, the world: what is true of the environment regardless of what we build, including domain knowledge and the constraints nature and the organisation impose.
*R*, the requirements: what we want, stated in the vocabulary of the world.
*S*, the specification: what the machine must do, stated at the machine's interface alphabet.
*P*, the program: the artifact that implements *S*.
*M*, the machine: what executes *P*.

The distinction that does the work is not the number of artifacts but the vocabulary each is confined to.
*R* speaks of the world and may name phenomena the machine can never observe.
*S* speaks only of phenomena shared between world and machine, because a specification that references unobservable world state is not implementable.

## The two obligations

$$W \wedge S \Rightarrow R$$

The satisfaction argument: the specification, in the presence of the world's actual behaviour, discharges the requirement.
This is the obligation this skill owns.

$$P \Rightarrow S$$

Refinement: the program meets the specification at their shared alphabet.
`refinement-driven-development` owns this leg, including its mechanical Lean-to-Rust round trip and the position that mechanical proof is the precise ideal rather than a requirement.

Three side conditions make the pair honest rather than decorative.
*W* and *S* together must be consistent, since a specification that contradicts the world discharges everything vacuously.
*S* must be implementable using only interface phenomena.
And no requirement may be smuggled into *S* that references world state the machine cannot observe — the most common failure, because it looks like progress.

## The four dark corners, as checkable discipline

Zave and Jackson's four dark corners become four things to check on any requirements document.

Every term in *R* must be grounded in a designated world phenomenon.
Ungrounded nouns are where requirements documents rot, because two readers resolve them differently and neither notices.

*W* must be explicitly separated into indicative and optative.
Indicative statements are true regardless of the machine; optative statements are what we want.
Fusing them is the most consequential of the four failures and the hardest to see, because a justification clause inside an optative requirement reads as prose rather than as an assumption. When the assumption later becomes false, nothing notices.

*S* may mention only shared phenomena.

And the boundary between *R* and *S* must be drawn deliberately rather than by drift, because the natural pull is toward *S*: interface vocabulary is concrete and testable, so requirements silently migrate into it.

## The designation table

The designation table is the artifact that makes the grounding condition mechanical.
One row per term: the term, the world phenomenon it denotes, and whether that phenomenon is world-only or shared with the machine.

It is the highest-leverage item in this whole framework because checking it is a lexer pass rather than a semantic one.
Extracting the content nouns from a requirement and resolving each against the table needs no understanding of what the requirement means.
Nothing else here is that cheap to check, which is why a project adopting one piece of this framework should adopt this piece.

A designation table is also where domain ambiguity becomes visible instead of latent.
A term with two rows is a term the project is using in two senses, and that is worth knowing before it reaches a specification.

A corpus of maintained requirements has the same stability concern for a requirement's own cross-references: a requirement may reference another requirement already grounded in the corpus, since that identity persists, but never the change that introduced it, because a change's own record is transient by design and the reference dangles the moment it moves on.

## Obstacle analysis

Above *R* sits the goal layer, and the discipline for it is van Lamsweerde's KAOS: goals refine through AND/OR graphs down to requirements assignable to agents.

The part worth importing is obstacle analysis, which systematically negates goals to find the world behaviours under which $W \wedge S \Rightarrow R$ fails.
This matters because it is a *generator* rather than a review.
The trust-boundary and open-questions sections of a design document are otherwise produced by taste, which means they contain what the author happened to think of.
Negating each goal in turn produces them by construction.

An obstacle, once found, has a natural home: it is the violation condition of an indicative assumption.
Recording it as such turns a one-time analysis into a standing monitor, because the assumption now states what would falsify it.

A world assumption that names a vendor's version carries a trigger that fires when the deployed version moves, such as an evaluation assertion on the version or a comparison against the running version at each change's close-out.
A dependency bump moves a vendor's version without anyone rereading the assumptions that name it, so a trigger that depends on someone noticing does not fire.

## Parnas' four-variable model

When the world is physical, specialise: Parnas' four-variable model splits the problem into monitored and controlled environmental quantities (NAT, REQ) and the input and output registers the software actually reads and writes (IN, OUT, SOF).

The reason to reach for it is that it makes the measurement gap explicit.
The machine never observes the monitored quantity, only a register that stands in for it, and the fidelity of that correspondence is an indicative assumption belonging in *W*.
A requirements document that omits it has assumed perfect sensing without saying so.

## The shear against AMDiRE

AMDiRE, the artefact-based approach of Méndez Fernández and Penzenstadler, is the industrially validated macro-form for organising these documents: an artefact model of a content model plus a structure model, with roles, milestones and a tailoring theory that WRSPM abstracts away.
The two compose, but the naive layer mapping is wrong in a way worth stating precisely, because it changes where documents belong.

AMDiRE's Context Specification is approximately *W* together with goals.
Its Requirements Specification is approximately the *R*-to-*S* interface zone, not *R*: a usage or use-case model describes user-system interaction at the interface, which is *S*-side vocabulary.
Its System Specification — component decomposition, behaviour automata — sits *below* *S*, in the territory WRSPM assigns to refinement toward *P*.

So the world/machine boundary falls in the middle of AMDiRE's Requirements layer, while AMDiRE's own problem/solution boundary falls lower.
Two consequences follow for any AMDiRE-shaped documentation tree.
Genuinely environment-referent requirements — statements about world phenomena the machine never touches — have no home in the Requirements layer and get exiled upward into goals, informally.
And a document titled "System Specification" is usually carrying *S*-stratum content and sub-*S* content in one file without marking the seam.

The cheapest high-leverage repair is to promote the glossary to a stratified designation table.
AMDiRE already requires a glossary; adding the phenomenon and the world-versus-shared column converts a list of definitions into the artifact the grounding condition needs.

## Institutions, and why the obligations are logic-independent

Both obligations are stated over an institution rather than over a particular prover: Lean's dependent types, Dafny's Hoare logic, Verus's linear ghost state and a row-typed language's record calculus are different institutions, and satisfaction is stable under signature morphism.
That is what lets one satisfaction argument span a system whose parts are verified by different tools.
`preferences-theoretical-foundations` owns that formalisation, along with the assume-guarantee contract algebra that composes heterogeneously verified components; see its `references/institution-theory.md` and `references/assume-guarantee-contracts.md`.

## What the evidence actually supports

The vericoding benchmark measures its specification-defect rate *conditioned on vericoding success*: among specifications for which an implementation and proof were successfully synthesised, roughly nine percent were too weak and a further fifteen percent were poor translations.
What that establishes is narrow and sufficient: specification defects survive the $P \Rightarrow S$ gate.
A green proof is evidence about the program, not about the specification.

Two things it does not establish, which must not be attributed to it.
It does not compare the difficulty of the intent-to-specification direction against specification-to-program; it declines to study the former at all.
The inference that the bridge is therefore the binding constraint is ours.
And the figures rest on manual inspection of roughly a hundred and twenty-five items with no stated aggregate sample size, which makes them suggestive rather than strong.
Cite them at that strength.

## Scope

Reach for this skill when a requirements document is being written or reviewed, when it is unclear which stratum a statement belongs in, when a term needs grounding, when a satisfaction argument needs stating or repairing, or when an AMDiRE-shaped tree needs reconciling against the world/machine boundary.

Do not reach for it to decide whether an implementation matches its specification — that is $P \Rightarrow S$ and belongs to `refinement-driven-development`.
Do not reach for it to run the audit that checks a specification against intent, inventories a trust surface, or produces external wording — that is `satisfaction-argument-audit`.
Do not reach for it to calibrate how much confidence a body of evidence warrants — that is `preferences-validation-assurance`, the home of the severity criterion.

This skill states obligations; it does not itself grade the evidence that discharges them.

## See also

- `satisfaction-argument-audit` — the operational sibling: the three-gate chain, blind informalization for specification-versus-intent, the trust-surface inventory, and safe external wording. This skill says what must hold; that one says how to check it and what may then be claimed.
- `refinement-driven-development` — owns $P \Rightarrow S$, the Lean-to-Rust round trip, and translation validation.
- `preferences-theoretical-foundations` — owns the institution-theoretic logic-independence these obligations rely on, and the assume-guarantee contract algebra for composing heterogeneously verified components.
- `preferences-validation-assurance` — owns severity, evidence quality, and the confidence promotion chain.
- `preferences-documentation` — owns the AMDiRE-shaped documentation tree this skill's shear analysis applies to.
- `preferences-discovery-process` — owns the discovery activity that produces the world vocabulary a designation table records.
- `ubiquitous-language` — owns the glossary audit whose per-term record a designation table extends.
- `atdd-outer-loop` — its spec-leakage audit, which removes anything naming the machine from an acceptance specification, is the shared-phenomena restriction enforced at the acceptance layer.
