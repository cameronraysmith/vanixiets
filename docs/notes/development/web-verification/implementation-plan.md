# Implementation plan

Each increment updates these notes alongside its implementation.
Increments 1–5 and the registry part of 6 merged to `main` in #3265.
Increment 9 adds live publication; its live verification and deployment remain pending.

| Increment | Deliverable | State |
| --- | --- | --- |
| 1 | Pinned CLI/browser package, shared capability, and devshell wiring | Implemented; reviewer confirmed targeted Darwin/Linux checks at the published head |
| 2 | APM-owned upstream skill with offline composition and updated consumer checks | Merged; the root `apm.lock.yaml` records the skill after relocking against `main` |
| 3 | Requirements, architecture, decisions, and verification ledger | Initial working design written |
| 4 | Docs journey, completed-report producer, required verdict check | Integrated; fresh positive runs pass on Darwin and Linux |
| 5 | Negative controls for failure detection and report integrity | Assertion and missing-link controls pass on both platforms with retained evidence and negative verdicts |
| 6 | build_finished registry support and publisher sidecar rehearsals | Registry prerequisite integrated; `publish-evidence` and its rehearsal pass on Darwin and Linux; registered as an effect in increment 9 |
| 7 | CLI reproduction, diagnosis, correction, and re-verification receipt | Mobile hero overflow repaired: strengthened scenario fails the Linux gate with a kept report, then passes on Linux and Darwin after the CSS correction; review pending |
| 8 | Independent review, integrated lint/checks, atomic commit organization | Review findings closed before #3265 merged |
| 9 | Live publication: `browser-evidence` effect, R2 upload with prefix-scoped temporary credentials, `sciexp` adoption and lifecycle, serving Worker, PR comment | Implemented; upload and comment rehearsal passes on Darwin and Linux against a credential-verifying S3 stub; live verification pending |

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
Live publication is implemented (increment 9); applying its Terraform, deploying the Worker with wrangler, and observing a live run remain separately authorized steps.
