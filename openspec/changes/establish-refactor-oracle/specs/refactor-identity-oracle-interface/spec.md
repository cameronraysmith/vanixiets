## ADDED Requirements

### Requirement: `just drv-diff` dumps seven drvPath maps at two commits without building

`just drv-diff <before> <after> [allow] [systems] [vm-systems]` SHALL evaluate at each commit, without building, a map from attribute name to drvPath for the NixOS configuration toplevels, the darwin configuration toplevels, the home configuration activation packages, `checks.<s>` for each `s` in `systems` (default `x86_64-linux aarch64-darwin`) and `vmTests.<s>` for each `s` in `vm-systems` (default `x86_64-linux aarch64-linux`), reading each map's attribute names from that commit.

**Trust boundary**: Equal drvPaths show that the build recipe of each dumped attribute is unchanged; they do not show that a deployed system behaves the same, and on darwin, where builds are not sandboxed by default, the same derivation can build differently (world assumption A310). The command sees only the seven maps on the systems it is given: `flake.lib` values, clan inventory data, terranix output, `packages`, `apps`, `devShells` and other systems' checks are outside it. It sees only committed trees (A311).

#### Scenario: The default maps

- **WHEN** `just drv-diff <before> <after>` runs with the default `systems` and `vm-systems`
- **THEN** each commit's dump holds seven maps: `nixosConfigurations.<h>.config.system.build.toplevel`, `darwinConfigurations.<h>.config.system.build.toplevel`, `homeConfigurations."<name>".activationPackage`, `checks.x86_64-linux`, `checks.aarch64-darwin`, `vmTests.x86_64-linux` and `vmTests.aarch64-linux`

#### Scenario: Comparing a commit with itself

- **WHEN** `just drv-diff <c> <c>` runs with no allow-list
- **THEN** it reports every map identical and exits 0

#### Scenario: Nothing is built

- **WHEN** `just drv-diff` runs
- **THEN** it instantiates derivations and realises no derivation output, apart from the flake source copies the evaluator makes

#### Scenario: A host added at the candidate commit

- **WHEN** a host exists only at the candidate commit
- **THEN** its toplevel appears in that commit's map only, and the report lists it as added

### Requirement: `just drv-diff` reads each side from its commit only

`just drv-diff` SHALL resolve `before` and `after` with `git rev-parse --verify <rev>^{commit}` and evaluate each through the flake reference `git+file://<repo>?rev=<commit>`.

#### Scenario: A dirty working copy

- **WHEN** the working copy has uncommitted or untracked files and both arguments name commits
- **THEN** the dumps reflect only the two commits' trees

#### Scenario: A name that is not a commit

- **WHEN** `before` or `after` does not resolve to a commit
- **THEN** the command exits 2 before evaluating anything

### Requirement: `just drv-diff` holds the evaluator fixed and records the run

`just drv-diff` SHALL evaluate configurations and home configurations one attribute per process with `flake.lib.fleetNix`, and `checks.<s>` and `vmTests.<s>` with `nix-eval-jobs-stock` where it is on PATH and `nix-eval-jobs` otherwise, with import-from-derivation and the evaluation cache disabled.
It SHALL write the dumps, each evaluator's resolved path, `nix --version`, and its report to `logs/drv-diff-<before12>-<after12>-<UTC>/`.

#### Scenario: `nix` names another evaluator

- **WHEN** the `nix` on the caller's PATH is iets' classic mode
- **THEN** the dumps are still produced by `flake.lib.fleetNix`, and the run's header records the resolved path of each evaluator used and `nix`'s `--version` output; for `nix-eval-jobs` it records only the store path, whose name carries the version, because iets rejects `--version`

### Requirement: The allow-list declares expected differences

The optional `allow` argument SHALL name a file of lines `<set>.<attr> <expect>` with an optional `# reason`, where `<set>` is one of `nixos`, `darwin`, `home`, `checks.<s>`, `vmTests.<s>` and `<expect>` is one of `changed`, `added`, `removed`, `may-change`; blank lines and lines starting with `#` are ignored.
An entry SHALL name one exact attribute; no pattern matches several.

#### Scenario: A malformed entry

- **WHEN** the allow-list has a line whose `<expect>` is not one of the four words, or whose `<set>` is not one of the five forms
- **THEN** the command exits 2 and names the line

#### Scenario: An entry for an attribute absent at both commits

- **WHEN** the allow-list names `darwin.nosuchhost changed` and neither commit has that host
- **THEN** the command exits 2 and names the entry

### Requirement: Checks built from the whole repository are allowed once, for every run

`just drv-diff` SHALL read a committed base allow-list kept beside the `drv-diff` app, in the allow-list format and holding only `may-change` entries, and SHALL apply it on every run together with the `allow` argument.
The base allow-list SHALL name every dumped check whose derivation takes the whole flake source as an input, and nothing else.

#### Scenario: The secret-scan check changes on every commit

- **WHEN** a refactor's candidate commit differs from its base commit and its `drv-delta.txt` does not name `checks.x86_64-linux.gitleaks`
- **THEN** that check's changed drvPath is reported as allowed by the base allow-list and does not by itself cause exit 1

#### Scenario: A change's own allow-list repeats a base entry

- **WHEN** a change's `drv-delta.txt` names an attribute that the base allow-list already names
- **THEN** the command exits 2 and names the duplicate entry, so the whole-source checks are declared in one place only

### Requirement: `just drv-diff` exits by the allow-list

`just drv-diff` SHALL exit 1 when any attribute's drvPath differs, appears or disappears without a matching entry, or when a `changed`, `added` or `removed` entry did not occur; it SHALL exit 0 otherwise; it SHALL exit 2 on a malformed allow-list, an entry naming an attribute absent at both commits, or a dump it could not produce.

#### Scenario: An undeclared difference

- **WHEN** one darwin host's toplevel drvPath differs and the allow-list has no entry for it
- **THEN** the report names `darwin.<host>` with both drvPaths and the command exits 1

#### Scenario: A declared difference

- **WHEN** the allow-list has `darwin.stibnite changed  # activation order` and only that toplevel differs
- **THEN** the command exits 0 and the report lists the difference as declared

#### Scenario: A declared difference that did not happen

- **WHEN** the allow-list has `vmTests.x86_64-linux.fleet-ingress changed` and that drvPath is identical at both commits
- **THEN** the command exits 1 and names the entry as not occurring

#### Scenario: A possible difference

- **WHEN** the allow-list has `darwin.stibnite may-change` and that drvPath is identical at both commits
- **THEN** the command exits 0 and reports the entry as not occurring

#### Scenario: Mutant revision

- **WHEN** the candidate commit changes one value in one host's configuration and nothing else, and no allow-list is given
- **THEN** the report names that host's toplevel and the checks that build it, besides the base allow-list's whole-source checks, and nothing else

### Requirement: A recorded run can be re-judged without evaluating

`drv-diff --reuse <dir>` SHALL judge the dumps recorded in an earlier run's evidence directory against the current allow-lists, with a run's report format and exit codes, without evaluating anything.
It SHALL write a new report file and SHALL NOT write the run's own header or report.

#### Scenario: An allow-list edited after the run

- **WHEN** an entry has moved from a change's `drv-delta.txt` to the base allow-list since the run, and `just drv-diff-rejudge <dir> <drv-delta.txt>` is run on that run's directory
- **THEN** the new report lists that attribute as allowed by the base list, the command exits as the edited lists decide, no evaluation runs, and the run's original `report` is unchanged

#### Scenario: A directory missing a dump

- **WHEN** `<dir>/header` names `checks.aarch64-darwin` among its systems and `<dir>/checks.aarch64-darwin.after.jsonl` does not exist, or `<dir>/header` is missing
- **THEN** the command exits 2 and names what is missing

### Requirement: An attribute failing to evaluate differs only when it fails at one commit

`just drv-diff` SHALL list an attribute that failed to evaluate at both commits without that failure by itself causing exit 1, and SHALL report one that failed at exactly one commit as a difference.

#### Scenario: Failing at both commits

- **WHEN** `vmTests.aarch64-linux.<t>` reports an evaluation error at both commits
- **THEN** the report lists it as failing at both, and the exit status is decided by the other attributes

#### Scenario: Failing at the candidate commit only

- **WHEN** a check evaluates at the base commit and reports an error at the candidate commit, and no allow-list entry names it
- **THEN** the report names it as a difference and the command exits 1

### Requirement: `just eval-cost` measures interleaved runs

`just eval-cost <attr> <before> <after> [runs] [mode]` SHALL evaluate `<attr>` at each commit once untimed, then `runs` rounds (default 2) of `before` then `after`, each a fresh `flake.lib.fleetNix` process with `NIX_SHOW_STATS=1`, a per-run `NIX_SHOW_STATS_PATH` and the evaluation cache disabled.
It SHALL evaluate `.#.<attr>.drvPath` when `mode` is `drv` (default) and `.#.<attr>` with `--apply builtins.attrNames` when `mode` is `keys`.

#### Scenario: Interleaving

- **WHEN** `just eval-cost darwinConfigurations.stibnite.config.system.build.toplevel A B 2` runs
- **THEN** the timed runs occur in the order A, B, A, B, each in a new process, and four rows are printed

#### Scenario: Key-set mode

- **WHEN** `mode` is `keys` and `attr` is `checks.x86_64-linux`
- **THEN** each run evaluates the attribute names only and records the same five figures

### Requirement: `just eval-cost` records every run with its conditions

For each timed run `just eval-cost` SHALL record wall time, `cpuTime`, `gc.totalBytes`, `nrThunks` and `envs.number`, and in the header the evaluator's resolved path and version, the host, its memory, and whether another `nix` or `nix-eval-jobs` process was running, write them to `logs/eval-cost-<label>-<UTC>.{log,jsonl}`, and print every run.

**Trust boundary**: The figures hold only for the recorded evaluator, host and conditions (A312, A313); the command does not stop other work on the host and only reports whether evaluations were running.

#### Scenario: Another evaluation is running

- **WHEN** a `nix-eval-jobs` process is running on the host when `just eval-cost` starts
- **THEN** the header records it, and every run's five figures are still written to both files
