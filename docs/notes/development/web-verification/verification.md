# Verification ledger

This file distinguishes inherited evidence, current implementation checks, and planned demonstrations.
No entry below claims live deployment or evidence publication.

## Requirement traceability

| Requirements | Intended evidence | Current state |
| --- | --- | --- |
| R1 | Committed journey with independent expected outcomes and required verdict | Implemented; real browser checks pass |
| R2 | Completed negative report retains attachments and is discoverable by named check | Report and negative control pass; live API retrieval pending |
| R3 | CLI reproduction and reviewed correction followed by independent rerun | Pending |
| R4 | Relevant-input identity and cache-reuse receipt | Pending; whole-build reuse does not emit build_finished |
| R5 | Isolated browser/profile/fixture cleanup checks | CLI smoke has isolation; harness integration pending |
| R6 | Trusted publisher rehearsal, malformed metadata rejection, no PR evaluation | Existing docs precedent; browser publisher pending |
| R7 | Deliberate defect rejected for the expected reason | Controlled guide-heading mutation rejected with retained trace and screenshot |
| R8 | Documented lifecycle seam, later exercised by a second application | Design only |

## Prior evidence and its limits

Before the latest rebases, the Playwright CLI smoke passed on native aarch64-darwin and x86_64-linux through Magnetite.
It exercised browser launch, a real button click, rendered text, nonzero font height, snapshot output, and cleanup.
The Linux run first failed because rendered text was empty; supplying a default font configuration made it pass.
The smoke clears inherited browser-control variables so it cannot accidentally attach to a live profile.
These results do not validate the proposed report/verdict split or APM skill route.

`nix develop --accept-flake-config -c just lint` passed gitleaks and treefmt on the prior base `7b7d78d3609dadb43e5a5c6d8c5fb3083d0044f2`.
The implementation checkout was then rebased onto `af98cc44c25664c5658b36f4d8f5251aa2022188`.
New changes require new validation.

## Initial implementation history

After that rebase and addition of this design tree, `nix develop --accept-flake-config -c just lint` completed with exit status 0: gitleaks and treefmt passed.
Nix emitted a nonfatal evaluation-cache SQLite contention warning.
This run covers the parent checkout's design and existing capability changes, not the isolated workers' unfinished APM, report, or registry changes.
That was the state at this particular lint run, not the current integration status; subsequent entries record their integration.

### Registry prerequisite

The isolated registry worker reports exit status 0 for:

```sh
nixfmt --check modules/effects/vanixiets/registry.nix modules/checks/effects-interpreter.nix
nix build .#checks.aarch64-darwin.effects-interpreter \
  .#checks.aarch64-darwin.effect-run-context --no-link --builders '' -L
```

The effects interpreter rebuilt; effect-run-context was reused from cache.
The worker first observed the missing buildFinished option, then independently the missing build_finished mapping before implementing each.
Its 18 script cases and two structural comparisons exercise the actual registry mapping, literal arguments, secret isolation, defaults, and absence of the main-only guard.
Linux effect derivations were evaluated for metadata, not built or run.
The parent reviewed the two-file diff and reran both native Darwin checks after integration; both completed with exit status 0 using cached outputs.
`git diff --check` also passed.
This evidence does not cover artifact publication.

### APM skill integration

The parent reviewed the source/manifest drift guards and confirmed that root `apm.lock.yaml` has no diff.
After integration, native Darwin builds of `playwright-cli-consumers` and `omnigent-worker-capabilities` completed with exit status 0.
The worker additionally reports successful x86_64-linux versions using only Magnetite/Pyrite builders, clean frozen APM installation for both targets, recursive upstream skill/reference comparisons, and rejection of package-version and source-revision mutations.

The planning plugin's generated lock migrated from APM 0.24 to 0.32.
Its large deployment ledger also reconciles older resolutions to the already-declared Superpowers and mattpocock pins and adds the previously missing Linear dependency.
Those manifest pins were not changed by this task.
The root consumer follows published remote plugin refs, so it cannot record the unpublished local manifest honestly; its relock is deferred until publication.
This does not block local Nix composition or the plugin's frozen-install check.

### Browser report and verdict

After integration and jj snapshotting of the new files, the parent ran:

```sh
nix build .#checks.aarch64-darwin.docs-e2e-wiring \
  .#checks.aarch64-darwin.package-vanixiets-docs-test-e2e \
  .#checks.aarch64-darwin.package-vanixiets-docs-test-e2e-negative-control \
  .#checks.aarch64-darwin.package-vanixiets-docs-test-unit \
  --no-link --builders '' --cores 4
```

All passed using the worker's cached outputs.
The initial parent evaluation correctly rejected untracked new files; snapshotting them made the flake complete.
Integrated `just lint` and `git diff --check` passed.

The worker's final native Darwin run exercised 20 browser scenarios across Chromium and WebKit, 25 report-protocol tests, and 20 existing Vitest tests.
The protocol tests include real pinned-runner launch failure, global setup failure, and zero-test selection.
The isolated negative journey produced exactly one intended assertion failure with its original trace and screenshot retained; validating its evidence succeeded while its verdict returned 1.
Its output is `/nix/store/9n8s3icgic8gjx24w7251czhli76vdlx-vanixiets-docs-e2e-negative-report-0.0.0-development`.

Linux exercised 30 scenarios across Chromium, Firefox, and WebKit.
The positive report ran on Pyrite and the negative report on Magnetite with Rosetta excluded.
Those runs preceded final formatting, README changes, and the additional unit-runner controls; final Linux revalidation remains outstanding.

An attempted full `just check-fast auto off x86_64-linux` warm-up reached 11 successful checks and no observed failures before the 200-second terminal limit.
It did not complete and is not evidence that the full Linux check surface passed.
The draft review checkpoint must disclose that limit.

## Independent review and corrections

The independent `omp` review covers published head `d9d44f5c5c8d94412021e1f46386a9dccb211b56` in draft PR #3265.
Its eight findings are recorded in tuicr session `gh:cameronraysmith/vanixiets/pr/3265`.
Review finding identifiers R1–R8 are distinct from the requirement identifiers in the table above.

The reviewer reports successful targeted Darwin and Linux checks at that head, mostly from cached outputs, and an actual reproduction of lost evidence for a missing-element action timeout.
This supplements the initial implementation history; it is not a full check sweep or a fresh browser-suite run.

The correction work has passed this integrated native Darwin selection, with remote builders disabled:

```sh
nix build .#checks.aarch64-darwin.docs-e2e-wiring \
  .#checks.aarch64-darwin.playwright-cli-consumers \
  .#checks.aarch64-darwin.docs-evidence-cache \
  .#checks.aarch64-darwin.effects-interpreter \
  .#checks.aarch64-darwin.effect-run-context \
  .#checks.aarch64-darwin.deployment-safety \
  --no-link --builders '' --cores 4
```

- R2: the evidence-epoch check rejects invalid epochs, requires identical epochs to reuse the report, and requires a new epoch to change the report and verdict without changing the site derivation.
  Native report outputs for epochs `0` and `1` were realized and their provenance read back.
  Ordinary nixbot restart and Nix `--rebuild` semantics were inspected in pinned source; neither is documented as a replacement mechanism for an existing negative report.
- R3: credentialed `buildFinished` definitions now require write/admin permission metadata.
  Real registry evaluation covers unsafe configurations; seven direct assertions against the pinned nixbot matcher cover permission behavior.
  Those assertions ran without pytest, which was unavailable in the research Python environment.
- R5: a successfully built verdict reading another producer is rejected despite matching enumeration identities.
  Removing the dependency predicate made the negative fixture fail, demonstrating that the fixture exercises that predicate.
- R6: consumer tests evaluate the real `ai` and `agents` aggregates without named-user enrollment lists.
  Injecting the package into the lighter aggregate made its exclusion check fail.
- R7: the required verdict no longer links to the report and enforces `allowedReferences = [ ]`.
  A measured empty verdict closure was 96 bytes with no references; the separately enumerated report intentionally retains its provenance closure.

The same six-check selection passed for x86_64-linux with `--max-jobs 0` and only the configured Magnetite/Pyrite builder entries supplied.
The effects interpreter and wrong-producer fixture emitted build logs; these results do not imply every selected derivation executed afresh.
`nix develop --accept-flake-config -c just lint` passed gitleaks and treefmt for this intermediate integrated state.

After R1/R4 integration, the following five checks passed on both platforms with the actual source-defined epoch wiring:

```text
package-vanixiets-docs-test-e2e
package-vanixiets-docs-test-e2e-negative-control
package-vanixiets-docs-test-e2e-action-negative-control
package-vanixiets-docs-test-e2e-runner-controls
package-vanixiets-docs-test-unit
```

Build logs show fresh positive browser execution: 20 passed on Darwin and 30 passed on Linux, with no flaky or skipped tests.
Both negative controls retained reports and attachments and independently checked verdict exit 1.
The removed-link control failed at the unchanged reader journey's click after its 5000ms action timeout, rather than reaching the whole-test deadline.
Separate native-browser controls cover accepted locator timeouts and rejected launch, hook, closed-page, and whole-test failures.
The unit check remains browser-free; independent policy tests reject omission of each required browser engine.
Linux again used only Magnetite/Pyrite builder entries and `--max-jobs 0`; Darwin used `--builders ''`.

Positive report outputs:

- Darwin: `/nix/store/m8w4hnmvjx0gn6ryd5hmjwvqkgrg4d2w-vanixiets-docs-e2e-report-0.0.0-development`.
- Linux: `/nix/store/vyl60h11xsq8jzw13xbn6cr55xyxja14-vanixiets-docs-e2e-report-0.0.0-development`.

No correction adds a live publisher, deployment, or current-revision receipt for whole-build reuse.

## Required negative cases

- Intended navigation outcome is broken: verdict fails for the specified assertion.
- Runner exits before producing a valid report: producer or verdict fails closed.
- Report is empty, malformed, unexpectedly skipped, or missing attachments: no passing verification claim.
- Report is valid JSON but omits a required project, journey, or discovered test: reject as incomplete.
- An assertion passes only on retry: retain and report its flaky outcome rather than label it first-attempt success.
- Required verdict export is removed or consumes a different producer: the structural gate check rejects the fixture.
- Aggregate build fails but report producer succeeds: evidence lookup remains possible.
- Report output cannot be realized: publisher reports unavailable evidence without executing PR code.
- Artifact metadata contains traversal/absolute paths, symlinks, executable upload instructions, or a wrong build identity: publisher rejects it before publication.
- Publication is retried: no duplicate or stale success receipt.
- Nix output reuse in a new build versus whole-build reuse: preserve original execution identity and do not claim a new event receipt where none was emitted.
- Correction changes assertions rather than satisfying them: review rejects the purported repair.

## Recording results

For each completed increment, record the command, platform, relevant input or derivation identity, observed outcome, and remaining limitations here.
Keep large reports, recordings, credentials, and mutable remote URLs out of this source tree.
Link durable evidence only after its storage and access policy is approved.
