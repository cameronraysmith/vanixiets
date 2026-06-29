# Process-compose checks

Process-compose is a regulator kind for the application-composition envelope: services start in dependency order on the developer's host, bind their ports, answer readiness probes, and talk to each other at the application layer.
It sits below the systemd-bearing regulators (nspawn container tests and full QEMU NixOS tests) on the integration-regulator escalation ladder.
This reference covers the architecture, the eval-gate pattern, the executed-test pattern, the envelope it covers, and the conditions under which a project should escalate to a heavier regulator.

## Architecture

process-compose is a host-process orchestrator that reads a YAML or nix-rendered configuration and supervises a set of long-running processes with dependency ordering, health probes, and TUI inspection.
The nix integration is provided by `process-compose-flake`, a flake-parts module that turns each `process-compose.<name>` definition into a `packages.<name>` derivation.
The resulting package is a runner script: invoking it from the developer shell starts the configured composition; building it as a derivation only checks that the configuration evaluates and the runner script links.

The flake-module wiring is conventional flake-parts: `process-compose."<name>" = { ... }: { settings.processes.<svc> = { command = "..."; depends_on.<dep>.condition = "process_healthy"; readiness_probe = { ... }; }; }` evaluates into a typed settings object, which the module then renders to YAML and embeds in the generated runner script.
Adding a new composition is a single attribute under `process-compose`; the package and its runner appear automatically in `packages.<system>` for the flake's declared `systems`.

The runner is OS-portable in the way that any nix-built script is: it works on Darwin, Linux, and inside a nix-built devShell across both platforms.
There is no kernel dependency, no systemd dependency, and no namespace dependency beyond what the underlying processes themselves require.
This is the defining property of the regulator kind: process-compose samples application-level composition without taking a position on the deployment target's init system or kernel.

## The eval-gate pattern

The lightest form of process-compose regulation wires a process-compose package into `checks.<system>.<name>` without executing it.

```nix
checks.dev-platform = self'.packages.dev-platform;
```

This is a legitimate but limited regulator.
It asserts that the process-compose configuration evaluates, that every referenced package builds, and that the runner script links without errors.
It does not assert that the composition actually starts, that services bind ports, that probes succeed, or that any service can talk to any other.
The runtime envelope is entirely unsampled.

ironstar uses this pattern at `modules/rust.nix` line 251, where `checks.dev-platform = self'.packages.dev-platform` exercises evaluation and build of the dev-platform process-compose composition without executing it.
The composition itself is defined in `modules/process-compose.nix` and `modules/services/signoz.nix`.
The pattern is appropriate here because the dev-platform composition is intended for the developer loop rather than as the production deployment shape: ironstar's actual deployed surface is NixOS-shaped (or, more broadly, container-shaped), so runtime sampling of the process-compose composition would tell us about the dev loop's well-formedness rather than about the deployed system.

The eval-gate pattern catches a real class of failures: a developer edits a service definition, a referenced package no longer builds, and the check fires.
It does not catch the class of failures that the executed-test pattern is designed for.
Use this pattern when the cost of an executed test outweighs the value, and when the composition is principally a development convenience rather than a target of severe regulation.

## The executed-test pattern

A stronger form of process-compose regulation wraps `process-compose up` (or the equivalent test-mode invocation) in a derivation that starts the composition, waits for readiness, exercises it, and asserts on observable results.

```nix
checks.dev-platform-smoke = pkgs.runCommand "dev-platform-smoke" {
  nativeBuildInputs = [ self'.packages.dev-platform pkgs.curl ];
} ''
  dev-platform &
  pc_pid=$!
  trap "kill $pc_pid" EXIT
  # Wait for readiness, exercise endpoints, assert on output.
  curl --retry 30 --retry-delay 1 --fail http://localhost:8080/health
  touch $out
'';
```

This sketch is illustrative rather than canonical.
Hermeticity is the central problem: process-compose was not designed for sandboxed assertion-driven testing.
It expects to manage host processes that bind real TCP ports, and the nix build sandbox restricts network namespaces in ways that interact poorly with the orchestrator's assumptions.
Strategies include binding to abstract Unix sockets, running with a per-test port range, and using process-compose's headless and exit-on-end flags to make the composition self-terminating once a probe succeeds.

Even with careful wrapping, the executed-test pattern under process-compose is harder to make hermetic than NixOS VM tests, which were designed for sandbox execution.
A project that finds itself fighting hermeticity at this layer should reconsider whether the artifact under test is genuinely host-process-shaped or whether its deployment target is service-on-NixOS, in which case the regulator should escalate to nspawn.

A pragmatic intermediate is to keep the executed-test invocation outside `nix flake check` (running it from a `just` recipe or a CI step that uses the dev shell) and to keep only the eval-gate variant inside the pure-derivation `checks` attrset.
This preserves hermeticity guarantees for the closure operator (`nix flake check`) while still exercising runtime behavior on demand.
The CCV framing in `preferences-compositional-continuous-verification` treats such out-of-closure regulators as legitimate when their absence from the closure operator is explicit and their results feed back into the same audit habit.

## Envelope coverage

The application-composition envelope that process-compose samples is well-defined.

The regulator can assert on process startup ordering through `depends_on` chains: service B starts only after service A reports ready, and the test can verify that the chain unwinds correctly even when an intermediate service is slow.
It can assert that processes bind their declared ports, that readiness and liveness probes return the expected codes, and that one service can reach another over loopback at the application layer.
It can assert on multi-language polyglot compositions on a single host: a Go API service, a Python worker, a TypeScript frontend, and a Rust binary cache all started together and exercised against each other.

The regulator cannot assert on systemd unit ordering or dependency semantics: there are no systemd units.
It cannot assert on NixOS module behavior: the composition lives outside the NixOS module system.
It cannot exercise kernel features, network namespace isolation, cgroup constraints, or any property that depends on the host kernel beyond what the user's developer-loop kernel happens to provide.
It cannot exercise secrets activation through sops-nix or clan-vars, because activation happens during NixOS boot.
It cannot exercise the boot sequence at all, because there is no boot.
It cannot exercise multi-machine coordination beyond simulating multiple machines as multiple processes on one host, which collapses the network topology to loopback.

The concrete consequence for ironstar's SigNoz/ClickHouse subsystem illustrates the boundary.
The dev-platform composition starts ClickHouse, the SigNoz collector, and the SigNoz query service together and lets a developer point load at the collector and observe traces and metrics arrive.
This is a faithful sample of the application-layer flow.
It is not a sample of how the same subsystem behaves under NixOS deployment: systemd unit ordering between ClickHouse Keeper and the collector, resource limits applied via systemd slices, secrets activation for the collector's downstream credentials, and ClickHouse Keeper raft topology across multiple machines are all outside the process-compose envelope.
A regression in any of those properties passes process-compose and fails in production.

## When adequate

Process-compose is adequate when the artifact under test is genuinely host-process-shaped.

Developer-loop service stacks are the central case: the composition exists to let a developer iterate on application code with the surrounding services running locally.
The eval-gate pattern is sufficient for asserting that the developer loop stays well-formed across changes to service definitions.
The executed-test pattern is sufficient for asserting that a recent change has not broken the loop's ability to start cleanly and answer basic health probes.

Quick local checks of application-layer composition fit the same envelope: do my services come up, do they wait for each other in the right order, do they answer at their declared ports.
A CI pipeline that runs an eval-gate process-compose check on every PR catches configuration drift cheaply and quickly; a more elaborate executed-test version runs in the same envelope at higher confidence.

Polyglot integration checks during early-stage development are a second fit.
A project that is still settling on its deployed shape — Kubernetes-shaped, NixOS-shaped, container-shaped, none of the above — benefits from a regulator that does not pre-commit to an init system or kernel envelope.
Process-compose holds the application-composition envelope steady while the team makes the deployment-shape decision, and the regulator graduates to nspawn or full QEMU once the deployment shape is decided.

Smoke tests in a deployed system can also live in process-compose when the smoke is intentionally narrower than the deployment.
A smoke that asks "given a recent build artifact, does this collection of services start and answer health probes" is well-served by process-compose, even when the production deployment is NixOS-shaped, because the smoke deliberately ignores the systemd and kernel layers.
The risk here is that the smoke gives false confidence about the deployed shape; the cure is to keep a heavier regulator running alongside.

## When inadequate

The escalation triggers are concrete.

The artifact's deployment target is a systemd service on NixOS.
Promote to an nspawn container test (`clan.test.useContainers = true`, which is clan's default).
The service-on-NixOS envelope covers systemd unit ordering and dependencies, NixOS module behavior, and secrets activation under clan-vars or sops-nix.
process-compose cannot cover this envelope because it operates outside the NixOS module system.

The artifact requires multi-machine coordination, kernel features, secrets activation tied to NixOS boot, or boot-sequence behavior.
Promote to a full QEMU NixOS test (`pkgs.testers.runNixOSTest` or clan's `useContainers = false`).
The NixOS-module-plus-kernel-plus-multi-machine envelope is the only one that covers VLANs, kernel modules, namespace isolation beyond what nspawn provides, and the boot sequence.

The artifact requires assertion on observability data flow end-to-end through a collector and a backend.
The deployed system will be NixOS-shaped, so the regulator's runtime envelope should also be NixOS-shaped; nspawn is typically the right choice, and full QEMU is appropriate when the data flow crosses machines or depends on kernel-level capture.
See `preferences-observability-engineering` for the observability-contract regulator pattern that lives in this regulator kind.

## Regulator-kind comparison

| Property | Pure derivation | Process-compose | Nspawn container test | Full QEMU NixOS test |
|---|---|---|---|---|
| Envelope | Function/CLI/transformation | Application-composition | Service-on-NixOS | NixOS + kernel + multi-machine |
| OS portability | Darwin + Linux | Darwin + Linux | Linux only | Linux only, with KVM |
| Hermeticity | Native | Hard | Native (nspawn) | Native (QEMU sandbox) |
| Cost | Seconds | Seconds to tens of seconds | Tens of seconds | Tens of seconds to minutes |
| Sandbox features | None | None | None beyond nix default | `kvm`, `nixos-test` |
| Assertion ergonomics | Direct on output | Application-layer probes | systemd + driver API | Full driver API across machines |

The table is descriptive rather than prescriptive: a project's actual regulator selection follows the escalation rules in the preceding sections, not the column with the lowest cost.

## Cross-references

`references/nixos-vm-tests.md` covers the nspawn and full-QEMU regulators at the depth of their architecture, driver API, and debugging workflow.
`preferences-compositional-continuous-verification` is the theoretical anchor for the operating-envelope-plus-regulator framing that this document instantiates for the application-composition envelope.
`process-compose-init` covers the scaffold recipe for introducing a process-compose composition and its eval-gate check into a flake.
`preferences-observability-engineering` covers the observability-contract regulator pattern that typically lands in nspawn or full QEMU rather than in process-compose.
