# Closed-loop web verification

This working design uses the Astro Starlight documentation site as a reference application for an agent-assisted verification loop.
The intended loop connects declared behavior, browser execution, retained evidence, diagnosis, correction, and re-verification.
It does not equate an agent's successful interaction with a passing acceptance test.

## Status

Implementation is in progress.
The Playwright CLI capability now uses APM composition rather than direct Home Manager skill injection.
The first harness increment now separates completed browser reports from their pass/fail gate and includes an isolated failing journey.
Neither evidence publication nor a complete agent repair demonstration has been implemented or verified yet.
No deployment or publication is authorized by these documents.

## Reading order

- [Requirements](requirements.md): desired outcomes, assumptions, operating envelope, and interface obligations.
- [Architecture](architecture.md): ownership, data flow, trust boundaries, and caching.
- [Decisions](decisions.md): choices, alternatives, and unresolved operational decisions.
- [Implementation plan](implementation-plan.md): reviewable increments and current state.
- [Verification](verification.md): traceability, evidence, and limitations.

These are active working notes, not documentation-site content.
Update them with implementation changes rather than retrospectively claiming that the design was satisfied.
After the reference implementation is reviewed, promote its stable contracts into the development documentation and retain only useful research here.
