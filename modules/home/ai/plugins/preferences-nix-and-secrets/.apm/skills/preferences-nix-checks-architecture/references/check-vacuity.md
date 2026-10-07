# Check vacuity: patterns and replacements

This reference supports "Operationalizing integrity" in the parent skill.
A vacuous check is one that would pass under a plausible incorrect implementation of its target, or one whose failure mode is already observed more cheaply elsewhere.
An audit of about 80 checks in this repository found about 60 in one of the patterns below.
Each subsection gives the smell a reviewer can recognize, the instance found here, and the replacement.
The patterns are not exclusive; a single check often exhibits two.

## Self-comparison

The smell is a check whose expected value and actual value are read from the same source.
The common form sets an option to a literal in a module and then asserts that the evaluated option equals the same literal, or reads a value back from the option that set it and compares it with itself.
The module system already guarantees that an option holds the value it was set to, so the check can fail only if the module system is broken.

The audit found structural checks in this repository that read a value back from the option that set it and compared it with the literal used to set it.
None of them could fail under an edit to the code they appeared to protect, because editing the literal moved both sides together.

The replacement is to ask what property the literal was meant to secure.
If it is a relation between independently defined values, such as a machine's inventory entry and its configuration, assert the relation as a module `assertions` entry or a nix-unit relational invariant, as in "Relational invariants via nix-unit" in the parent skill.
If there is no such relation, there is nothing to check and the check is deleted.

## Expected value computed by the code under test

The smell is an expected value produced by calling the same function, module, or library path that produces the actual value.
The check then verifies that the code agrees with itself, which it always does.
A milder form computes the expected value with a re-implementation that shares the same helper, so a bug in the helper appears on both sides.

The audit found checks whose expected values were computed by the code under test, so a defect in that code would have produced a matching defect in the expectation and the check would still have passed.

The replacement states expected values independently: as literals for a small number of cases chosen to distinguish correct from plausible incorrect behaviour, or as a property that does not depend on the implementation, such as a round trip or an invariant over all inputs.
`preferences-algebraic-laws` covers the property form.

## Testing upstream software or the Nix language

The smell is a check that would fail only if nixpkgs, home-manager, nix-darwin, clan-core, or Nix itself were broken.
Asserting that `lib.mkMerge` merges, that a nixpkgs package has a given `meta` attribute, that `builtins.toJSON` emits JSON, or that an upstream module produces the systemd unit it documents are all of this kind.

The audit found checks asserting facts about upstream packages and about Nix evaluation semantics, which our code neither implements nor can fix.
Upstream maintains its own test suites, and an upstream regression that matters to us surfaces when our own configuration or behaviour checks fail on the new lock.

The replacement is deletion.
Where an upstream behaviour is a genuine dependency of ours, the check that covers it is the check of our own behaviour that relies on it, which fails for the right reason and names our artifact.
A check that guards a deliberate divergence from upstream is not of this kind: `modules/checks/zerotierone-controller.nix` asserts that clan's controller package still differs from `pkgs.zerotierone`, because the check is obsolete the moment it does not.

## The unreachable assertion

The smell is a scanner or assertion whose target material can never reach the thing being scanned.
It looks like protection and cannot fail, because the input it guards against has no path into the configuration.

The audit found a disclosure audit that scanned generated configuration for a value that was never fed into any configuration in the first place.
No edit to the configuration code could make that value appear, so the check had no failure mode under any plausible change.

The replacement starts by tracing the data flow.
If there is a real path by which sensitive material could enter the output, the scanner targets that path and is tested by feeding it a known-bad input to confirm it fails.
If there is no path, the check is deleted; a guard against an impossible event is not defence in depth, it is noise that dilutes the signal of the checks that can fail.

## The permissive scanner

The smell is a scanner that classifies its input, handles the classes it understands, and lets everything else through.
The failure mode is silent: the scanner reports success on exactly the inputs it was never designed to examine.

`secrets-encryption-integrity` in `modules/checks/validation.nix` validated sops metadata on JSON files and passed any file that was not JSON.
A plaintext YAML secret was therefore a passing input to the check whose purpose was to reject plaintext secrets.
The corrected check selects every regular file under `secrets/` and every `secret` file under `vars/`, parses each according to the sops extension rule (`*.yaml` and `*.yml` as YAML, everything else as JSON), and reports any file it cannot parse as "not parseable in its sops format", which is a failure.
It also fails when it selects no files at all, because an empty selection is indistinguishable from a broken selector.

The rule is that a scanner must fail closed: anything it does not understand is a failure, not a pass.
A new file format, an unparseable file, an empty input set, or a tool error must all produce a non-zero exit.
Confirm the property by feeding the scanner one input of each class it claims to reject, including a class it does not parse.

## Mechanism mismatch

The smell is a heavy mechanism used to test something a lighter one observes equally well: a VM, container, or many subprocesses to test pure logic, or a build-time derivation to test a configuration value.
The cost is paid on every run and buys no failure mode that the lighter mechanism lacks.

The audit found a credential test that spawned about 80 sequential subprocesses and took 3 minutes 55 seconds, exercising functions whose logic was pure.
An in-process unit test of the same pure functions covers the same cases in seconds.

The replacement is to move the check down the placement ladder in "Operationalizing integrity": configuration facts to module `assertions` or existing fleet obligations, pure logic to in-process unit tests, and only executed behaviour to build-time derivations.
The escalation rules in "Choosing among integration regulators" in the parent skill are the same principle applied within the integration category.

## Duplicate coverage across systems

The smell is a check exposed on every system whose derivation does not depend on the system.
Each additional system re-evaluates and, if uncached, re-builds an identical computation and adds no evidence.

The audit found checks whose derivations were identical on every system yet were exposed on all of them, so the same evidence was evaluated once per system.
System-independent structural checks now carry `lib.optionalAttrs (system == "x86_64-linux")`, as in `modules/checks/validation.nix` and `modules/checks/structure/flake-shape.nix`.

The replacement is to gate the check to one system, after confirming that its inputs do not differ by system.
The opposite error is not a fix: a check whose derivation genuinely differs per platform, such as a package, a dev shell, or a platform-gated module branch, stays on every system it can fail on.
"System gating" in the parent skill states both directions.

## The single test

Every pattern above is an instance of one question, the severity criterion from `preferences-validation-assurance` applied to the check itself.
Would this check fail under a plausible incorrect implementation of its target that nothing else in the suite catches?

If the answer is yes, the check stays, on the cheapest rung that preserves that failure.
If the answer is no, the check is deleted.
It is not re-pinned to a new expected value, re-scoped to a narrower assertion that is still unfalsifiable, or kept as documentation; each of those preserves the cost and the false signal of coverage while adding no failure mode.
