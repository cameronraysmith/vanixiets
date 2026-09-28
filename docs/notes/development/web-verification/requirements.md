# Requirements

## Purpose and terms

Developers and reviewing agents need inspectable evidence for claims about a web application's behavior.
The docs site is deliberately a small first consumer; it is not a pretext for building a universal automation platform.

| Term | Designation | Boundary |
| --- | --- | --- |
| Reader journey | A reader's intended sequence of actions and outcomes on the site | World; selected actions and outcomes are observable |
| Scenario | A versioned executable description of selected observable outcomes | Shared |
| Execution report | Results and artifacts produced by one completed runner invocation | Shared |
| Verdict | The policy decision derived from a valid execution report | Shared |
| Evidence receipt | Association between a build, tested inputs, report, and publication | Shared |
| Correction | A proposed change reviewed against the original expectation | Shared |
| Acceptance | A stakeholder's judgment that the behavior meets their need | World; not implied by a green test |

## Environment assumptions

- W1: nixbot consumes the repository's named `checks.x86_64-linux` outputs and Hercules-style effects.
- W2: default-branch event code is trusted; tested PR content and its artifacts are not trusted executable publication code.
- W3: binary-cache uploads are best-effort, so a successful build does not guarantee later artifact availability.
- W4: browser reports may contain page contents, requests, and credentials; only synthetic, credential-free fixtures are eligible for public Nix outputs.
- W5: pinned software controls dependencies, not all scheduling and timing variation on a shared host.
- W6: screenshots and accessibility observations are incomplete proxies for a reader's experience.

Violation of an assumption narrows the claim rather than silently changing the expected result.
For example, absent report bytes mean evidence is unavailable, not that tests passed.

## Desired outcomes

| ID | Requirement |
| --- | --- |
| R1 | A reviewer can distinguish an observed interaction from an independently checked expected outcome. |
| R2 | A failed reader journey remains diagnosable without repeating the original execution merely to recover evidence. |
| R3 | An agent can investigate a failure, propose a correction, and demonstrate the corrected behavior without weakening its expectation. |
| R4 | Reuse of previous verification is visible and associated with the actual tested inputs. |
| R5 | Concurrent workers do not contaminate each other's browser sessions, fixtures, or evidence. |
| R6 | Evidence publication neither leaks private sessions nor executes untrusted application code with publication authority. |
| R7 | Deliberately broken behavior is rejected, demonstrating that the harness is not vacuously green. |
| R8 | A second application can adopt the lifecycle and evidence contracts without depending on Astro internals. |

## Interface obligations

- S1: committed scenarios assert literal, independently specified observable outcomes using project fixtures.
- S2: a report producer emits structured runner results and referenced attachments for a completed run, including a negative test result.
- S3: a separately required verdict check rejects failed, unexpectedly skipped, empty, malformed, or incomplete verification according to an explicit policy.
- S4: report-generation failure cannot be converted to a passing verdict by ignoring the runner exit status.
- S5: named report checks expose outputs through nixbot's build API; publication resolves those recorded outputs instead of evaluating PR code.
- S6: a trusted `build_finished` effect may publish a successful report producer's output even when the aggregate build failed; it does not replace the required verdict.
- S7: publication reports missing outputs, cache misses, and upload failures explicitly and is idempotent for a given build/report identity.
- S8: test derivations exclude PR numbers, publication destinations, and incidental CI timestamps from their inputs; receipts add build associations separately.
- S9: browser invocations use isolated profiles, bounded execution, deterministic test data, and run-scoped artifacts.
- S10: a negative control proves both rejection of a known broken behavior and preservation of its diagnostic report.

## Initial report and verdict policy

The report contract must be versioned and include runner exit status, completion status, global errors, the selected project set, discovered test identities, per-test expected status and attempts, retry outcomes, input provenance, and artifact references.
The completion inventory and result records must reconcile; a nonempty JSON file alone is not completion evidence.
The reference journey must also be present independently of discovery, so accidentally dropping it from discovery cannot pass unnoticed.
The producer validates artifact references against its retained output, not the builder's temporary paths.

| Observation | Producer | Required verdict |
| --- | --- | --- |
| Complete selected matrix, all first attempts pass, exit 0 | Valid report | Pass |
| Complete selected matrix, assertion failure followed by passing retry, exit 0 | Valid report retaining retry evidence | Pass with explicitly reported flaky outcome |
| Complete selected matrix, final ordinary assertion failure, matching nonzero test exit | Valid negative report | Fail |
| Runner exit contradicts reported outcome | Reject | Fail closed |
| Global error, interruption, incomplete inventory, or missing required project/journey | Reject | Fail closed |
| Zero tests, skipped tests, or non-passing expected statuses | Reject under the initial policy | Fail closed |
| Missing required report file or referenced attachment | Reject | Fail closed |

Retry-to-pass remains allowed to preserve the existing suite's retry policy, not because it is equivalent to a clean first-attempt pass.
There are no skip or expected-failure exemptions in this first reference slice.
A future exemption needs an explicit reviewed policy rather than an implicit parser fallback.
Structured failed expectation steps help distinguish completed assertion failures from infrastructure errors, but do not prove the absence of infrastructure causes inside an expectation.

The retained bundle includes HTML and machine-readable results plus the completion record.
Failure attempts require their configured screenshot and original-attempt trace; referenced video and other attachments must exist when the runner reports them.
Successful baseline runs need a complete result record, not a fabricated video.
Focused review media is a separate opt-in capture contract.

The preserved required check is `package-vanixiets-docs-test-e2e`.
The report producer is independently exported as `package-vanixiets-docs-test-e2e-report`.
An executable structural check must verify both exports and the verdict's dependency on that exact producer; a fixture removing the verdict must be rejected.

## Publisher acceptance boundary

The first publisher rehearsal is limited to an explicitly selected inert-file bundle: validated metadata and raster screenshots, not executable scripts, upload configuration, or served HTML.
The complete internal diagnostic report may retain HTML and traces, but hosting those requires a separate origin/access decision.
The publisher must reject absolute or traversal attachment paths, symlinks, unexpected file types, mismatched build/report identities, and artifact-supplied executable publication instructions.
It must not invoke a shell on report text.
An unavailable store output stops publication without PR evaluation or a build fallback.
This boundary does not itself prove that pixels or metadata contain no sensitive information; eligible inputs remain synthetic and credential-free.

## First operating envelope

The first application is the built documentation site with synthetic public content.
The initial journey covers finding the getting-started guide and navigating its content under explicitly selected browser and viewport conditions.
The exact scenario is derived from the existing site, not an assumed Starlight feature.
CI verification targets x86_64-linux; Darwin execution is a separately recorded developer-platform check.
Unsupported or unexecuted platforms must not inherit another platform's success claim.

Live credentials, external production services, model inference, and autonomous repair are outside the hermetic test envelope.
They require separate runtime receipts and trust decisions.

## Satisfaction argument and obstacles

S1 and S3 support R1 only when the expected outcome actually expresses the reader's need.
S2, S5, and S7 support R2 only while artifacts remain available.
S8 supports R4 only if source filtering includes every behavior-affecting input.
S9 supports R5 only if fixtures also isolate server-side state.
S5 and W2 support R6 only if publishers treat report metadata and files as untrusted data.
S10 supplies evidence for R7 but does not establish that every meaningful defect is detectable.

Obstacles to track are weak assertions, silent skips, missing attachments, unintended inference inside checks, secret-bearing traces, stale receipts, and repaired tests that merely accommodate a regression.
The [verification matrix](verification.md) records which obligations have executable evidence.
