# Implementation plan

Each increment updates these notes alongside its implementation.
Commits remain local to the isolated Delta checkout; publication, deployment, and changes to other agents' working copies are excluded.

| Increment | Deliverable | State |
| --- | --- | --- |
| 1 | Pinned CLI/browser package, shared capability, and devshell wiring | Implemented in working change; revalidation needed after rebases |
| 2 | APM-owned upstream skill with offline composition and updated consumer checks | Integrated; native consumer/worker checks pass; remote root lock follows publication |
| 3 | Requirements, architecture, decisions, and verification ledger | Initial working design written |
| 4 | Docs journey, completed-report producer, required verdict check | Integrated; targeted native Darwin checks pass |
| 5 | Negative controls for failure detection and report integrity | Implemented and exercised on both platforms; final Linux unit additions await rerun |
| 6 | build_finished registry support and publisher sidecar rehearsals | Registry prerequisite integrated and checks pass; publisher not implemented |
| 7 | CLI reproduction, diagnosis, correction, and re-verification receipt | Planned |
| 8 | Independent review, integrated lint/checks, atomic commit organization | Draft review checkpoint being prepared; integrated lint and focused Darwin checks pass |

## Execution constraints

- Refresh applicable instructions and source before changing a component.
- Use local ghq reference sources at relevant revisions rather than reasoning from product names.
- Use native Darwin or explicit Magnetite/Pyrite builders; do not schedule work on the stopped Rosetta VM.
- Record actual test results, not commands suggested for future execution.
- Preserve the stable docs-test browser train independently of the CLI's alpha browser train.
- Rebase only this task's isolated changes when origin/main advances.
- Keep sensitive runtime artifacts outside source control and public Nix outputs.

## Completion criterion

The reference slice is complete when a real baseline passes, an isolated broken behavior produces the expected negative verdict with retained evidence, the publication contract is rehearsed, and a correction is reverified without weakening the expectation.
Live publication remains a separately authorized deployment step.
