# Evaluation cost: measurement and refactoring oracle

This reference is the procedure behind "Evaluation cost as a design constraint" in the parent skill.
It is written so that an agent with no prior context can measure what an attribute costs to evaluate, find where the cost comes from, decide whether a candidate change is an improvement, and prove that a refactor did not change any output.
The figures quoted are measurements from this repository, not targets.

## Cost of one attribute

Evaluate the attribute's `drvPath` with the evaluator's statistics enabled:

```bash
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/x.json \
  nix eval --raw '.#.checks.x86_64-linux.<name>.drvPath'
jaq '{bytes: .gc.totalBytes, cpu: .cpuTime}' /tmp/x.json
```

`drvPath` is the right target because it forces the whole derivation expression, including every input's derivation, without building anything.
`gc.totalBytes` is the total allocation during the evaluation and `cpuTime` is the evaluator's CPU time in seconds; together they are the cost an evaluator worker pays for this attribute from a cold start.
The `.#.` prefix makes the attribute path absolute.
Without the leading dot, `nix eval '.#checks...'` first probes default prefixes such as `packages.<system>.` and `legacyPackages.<system>.`, and those probes can force unrelated outputs and contaminate the measurement.

A cold single-attribute figure includes the flake load and everything strict on the path to the attribute.
In this repository a trivial structural check measured about 934 MiB and 3 s before the key-set fix in `modules/checks/zerotierone-controller.nix`, and 89 MiB and 0.27 s after it, with no change to the check itself.
That gap is the signature of cost that does not belong to the attribute being measured.

## Cost of the key set alone

Measure the names of the enclosing attribute set with the same statistics:

```bash
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/keys.json \
  nix eval --json '.#.checks.x86_64-linux' --apply builtins.attrNames
```

This forces every expression that the attribute names depend on and nothing that only the values depend on.
If the key-set figure is close to the single-attribute figure, the cost is in the key set, which every attribute and every worker pays; the fix is to make the offending module's names depend only on static data, as described in "Key-set strictness".
If the key-set figure is small and the single-attribute figure is large, the cost is in that attribute's value, which only that attribute pays, and the question becomes whether the value is worth it.
The difference between the two measurements localizes strictness without reading any code.

To find which module contributes to the key set, bisect: temporarily remove check modules from the import tree in a scratch checkout and re-measure, or evaluate `builtins.attrNames` of each module's contribution where it is reachable on its own.

## Attributing cost within an evaluation

When the key-set or value cost is known to be large but its source is not, use the evaluation profiler (available in Nix 2.30 and later):

```bash
nix eval --raw '.#.checks.x86_64-linux.<name>.drvPath' \
  --option eval-profiler flamegraph \
  --option eval-profile-file /tmp/eval.folded
```

The output is in collapsed-stack format, one line per call stack with a sample count.
Render it with `inferno-flamegraph` or `flamegraph.pl`, or read it directly by summing counts per frame prefix to get inclusive cost.
Read the widest frames below the flake root first: a `nixosSystem` or `evalModules` frame, a nixpkgs `import`, or a module file path under `modules/checks/` that should not be on the path to the measured attribute is the usual finding.
A nixpkgs instantiation appears as a wide frame rooted in `pkgs/top-level`; more such frames than there are systems indicates a configuration that re-imports nixpkgs instead of receiving `nixpkgs.pkgs`.

## Fleet-wide cost

nix-eval-jobs reports per-attribute statistics in its JSON output, including `stats.allocBytes` and `stats.wallMs`.
Summing them over a run gives total evaluation cost; sorting them gives the most expensive attributes.

These per-attribute figures overstate what removing a given check would save.
Each fresh worker, whether at start-up or after a restart triggered by `--max-memory-size`, evaluates the flake and every strict prefix before its first attribute, and that shared cost is charged to whichever attribute the worker happens to evaluate first.
An attribute that appears expensive may simply have been first in a fresh worker.
Before deleting or restructuring a check because of its nix-eval-jobs figure, confirm with the single-attribute and key-set measurements above, and count worker restarts in the run, since the shared prefix is paid once per restart.

## A/B/A/B benchmark discipline

A candidate change to evaluation is accepted on measurement, and the measurement is interleaved.
Run baseline, candidate, baseline, candidate, at minimum, on the same host with the same nix-eval-jobs flags.
A single baseline/candidate pair is confounded by store and evaluation cache state, by page cache, and by whatever else the host is doing; interleaving makes those effects show up as variance within each arm rather than as a difference between arms.

For each run record wall time, total allocation (summed `stats.allocBytes` or the process-level figure), the number of worker restarts, and whether anything else was running on the host.
Report every run, not the best one.
A result is credible when the two candidate runs agree with each other, the two baseline runs agree with each other, and the arms separate.

The discipline exists because allocation and wall time do not move together.
An earlier candidate in this repository reduced total allocation by 7% and reproducibly took 7 to 9% longer, and only the interleaved benchmark caught it; a single pair, or a decision based on allocation alone, would have merged a regression.

## drvPath-identity oracle

A refactor whose purpose is to make evaluation cheaper must not change what is built.
The acceptance criterion is byte-identical derivation paths before and after.

Record the check derivations for every system the flake declares.
Ask the flake rather than hardcoding a list, because the set is a property of the `systems` input and changes when a platform is added or retired.

```bash
for sys in $(nix eval --json '.#.checks' --apply builtins.attrNames | jaq -r '.[]'); do
  nix eval --json ".#.checks.$sys" \
    --apply 'c: builtins.mapAttrs (_: v: v.drvPath) c' > "/tmp/checks-$sys.$label.json"
done
```

Record the configuration toplevels as well, since a change to how nixpkgs is instantiated or passed in affects machines and homes directly rather than through a check:

```bash
nix eval --json '.#.nixosConfigurations' \
  --apply 'cs: builtins.mapAttrs (_: c: c.config.system.build.toplevel.drvPath) cs' > "/tmp/nixos.$label.json"
nix eval --json '.#.darwinConfigurations' \
  --apply 'cs: builtins.mapAttrs (_: c: c.config.system.build.toplevel.drvPath) cs' > "/tmp/darwin.$label.json"
nix eval --json '.#.homeConfigurations' \
  --apply 'cs: builtins.mapAttrs (_: c: c.activationPackage.drvPath) cs' > "/tmp/home.$label.json"
```

Adjust the system list and output names to what the flake actually exposes; the point is that every output a user deploys is covered.
Run the set with `label=before` on the base revision and `label=after` on the candidate, then `diff` each pair.

Identical output is the pass condition.
Any difference must be intended and named in the change description: an attribute deliberately removed because it duplicated another system's identical derivation, or a check moved to one system by gating.
An unexplained difference in a toplevel means the refactor changed a deployed system and is not a pure evaluation refactor, whatever its intent.
