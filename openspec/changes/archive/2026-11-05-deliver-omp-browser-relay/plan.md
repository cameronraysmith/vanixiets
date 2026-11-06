<!--
Procedural note: the interactive `superpowers:writing-plans` session was not run; this plan
was written by the delegated session that authored the change, following that skill's
structure (header, global constraints, file map, interfaces, per-task steps), from
`tasks.md`, `design.md` and the specs in this change directory.
-->

# Deliver the omp browser relay extension implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On darwin hosts, deliver omp's relay extension, built from the deployed omp, into a fixed real folder `~/.omp/browser-relay/extension` that Helium loads once per profile and omp's relay keeps current.

**Architecture:** A `pkgs/by-name` package runs upstream's own installer inside the sandbox and checks its version stamp. A Home Manager option set under `programs.omp.browserRelay.extension`, darwin-default, copies that package into the folder on each activation. Nothing touches the browser; the per-profile load and Bitwarden stay manual and are documented in a new README beside the module.

**Tech Stack:** nix flakes with flake-parts and import-tree; `pkgs/by-name` auto-discovery; Home Manager activation (`lib.hm.dag.entryAfter [ "writeBoundary" ]`); omp 18.16.0 from `inputs.llm-agents`; Helium 0.20.3.1.

**Spec:** `design.md`, `specs/browser-relay-delivery/spec.md`, `specs/browser-relay-delivery-interface/spec.md`, `specs/world-assumptions/spec.md` in this change directory.

## Global Constraints

- omp comes only from `inputs.llm-agents.packages.${system}.omp`, through `programs.omp.package`; no fetched zip, no manifest `key`, no second hash.
- Delivered folder: `~/.omp/browser-relay/extension`, a real directory; activation refuses if the path is a symbolic link; files `u+w`; files the package lacks are removed.
- `enable` defaults to `pkgs.stdenv.hostPlatform.isDarwin`.
- `programs.omp.settings` gains no `browser.relay`.
- No Helium policy: no configuration profile; none of `ExtensionInstallForcelist`, `ExtensionInstallBlocklist`, `ExtensionInstallAllowlist`, `ExtensionSettings`, `DeveloperToolsAvailability`, `DisableScreenshots` under `net.imput.helium`.
- Vendored-consumer grounding: the installer is invoked exactly as `omp browser-relay install --dir "$out"` with `HOME=$TMPDIR`, the argument list the sandbox spike ran; the relay's own updater resolves the folder as `path.join(getBrowserRelayDir(), "extension")` (`packages/coding-agent/src/tools/browser/relay/extension-files.ts:31`) with `getBrowserRelayDir()` = `dirs.rootSubdir("browser-relay", "data")` (`packages/utils/src/dirs.ts:811-812`).
- Capture long commands: `<cmd> 2>&1 | tee logs/<name>-$(date +%Y%m%d-%H%M%S).log`.
- Activate nothing before group 5; group 5 is human-gated.

## File map

| Path | Tasks | Responsibility |
|---|---|---|
| `pkgs/by-name/omp-browser-relay-extension/package.nix` | 1.1, 1.2 | Run omp's installer into `$out`; fail on a version-stamp mismatch |
| `modules/checks/package-tests.nix` (or the existing package-check wiring) | 1.1 | Declare `checks.<system>.package-omp-browser-relay-extension` |
| `modules/home/ai/omp/default.nix` | 2.1 | `programs.omp.browserRelay.extension` options and the `ompBrowserRelayExtension` activation step |
| `modules/home/ai/omp/README.md` | 3.1 | Manual per-profile load, opt-in, hazards, options |

## Interfaces

- `pkgs.omp-browser-relay-extension` with argument `ompPackage` (default the llm-agents omp); `name = "omp-browser-relay-extension-${ompPackage.version}"`; output files `LICENSE background.js manifest.json options.html options.js`.
- `config.programs.omp.browserRelay.extension.enable` (bool), `.package` (package), `.directory` (string, absolute).
- `home.activation.ompBrowserRelayExtension` (DAG entry after `writeBoundary`).

## Task 1: Extension package (tasks 1.1, 1.2)

- [ ] **Step 1: Write the package with its stamp check**

```nix
{ runCommand, ompPackage }:
runCommand "omp-browser-relay-extension-${ompPackage.version}"
  {
    nativeBuildInputs = [ ompPackage ];
    expected = ompPackage.version;
  }
  ''
    export HOME=$TMPDIR
    omp browser-relay install --dir "$out"
    stamped=$(head -n1 "$out/background.js")
    want="const OMP_INSTALL_VERSION = \"$expected\";"
    if [ "$stamped" != "$want" ]; then
      echo "omp-browser-relay-extension: expected $want, installer stamped: $stamped" >&2
      exit 1
    fi
  ''
```

The `ompPackage` default is supplied where `pkgs/by-name` is wired to the llm-agents input; follow how sibling packages there receive flake inputs.

- [ ] **Step 2: Build and inspect**

Run: `nix build .#packages.aarch64-darwin.omp-browser-relay-extension --print-out-paths`, then `ls` the output, `head -1 background.js`, `jq -r .version_name manifest.json`.
Expected: five files; both versions equal the deployed omp's.

- [ ] **Step 3: Determinism and upstream identity**

Run: `nix build .#packages.aarch64-darwin.omp-browser-relay-extension --rebuild`; download the matching release asset `omp-browser-relay-extension.zip`, unzip to a temporary directory, `diff -r` against the output.
Expected: rebuild succeeds; no difference.

- [ ] **Step 4: Mutant**

Run: build `.override { ompPackage = omp.overrideAttrs { version = "0.0.0"; }; }`.
Expected: FAIL naming `0.0.0` and the stamped version.

- [ ] **Step 5: Declare the check and commit** `checks.<system>.package-omp-browser-relay-extension`.

## Task 2: Home Manager delivery (tasks 2.1–2.3)

- [ ] **Step 1: Options**

```nix
browserRelay.extension = {
  enable = lib.mkOption {
    type = lib.types.bool;
    default = pkgs.stdenv.hostPlatform.isDarwin;
    description = "Copy omp's browser relay extension into `directory` on activation, for Helium to load unpacked.";
  };
  package = lib.mkOption {
    type = lib.types.package;
    default = pkgs.omp-browser-relay-extension.override { ompPackage = cfg.package; };
  };
  directory = lib.mkOption {
    type = lib.types.str;
    default = "${config.home.homeDirectory}/.omp/browser-relay/extension";
  };
};
```

- [ ] **Step 2: Activation step**

```nix
home.activation.ompBrowserRelayExtension = lib.mkIf relay.enable (
  lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dir=${lib.escapeShellArg relay.directory}
    src=${relay.package}
    if [ -L "$dir" ]; then
      errorEcho "ompBrowserRelayExtension: $dir is a symbolic link; it must be a real directory (Helium records the resolved path). Remove the link and re-run activation."
      exit 1
    fi
    run mkdir -p "$dir"
    # copy only changed files so an unchanged release leaves the folder untouched
    for f in "$src"/*; do
      name=$(basename "$f")
      if ! cmp -s "$f" "$dir/$name"; then
        run install -m 0644 "$f" "$dir/$name"
      fi
    done
    for f in "$dir"/*; do
      [ -e "$src/$(basename "$f")" ] || run rm -rf "$f"
    done
  ''
);
```

- [ ] **Step 3: Evaluate** the 2.1 verify commands for `crs58@aarch64-darwin` and `crs58@x86_64-linux`.
- [ ] **Step 4: Confirm** 2.2 (`browser.relay` is `null`) and 2.3 (no Helium policy keys). No source change if both hold; otherwise stop and report.
- [ ] **Step 5: Commit.**

## Task 3: README (task 3.1)

- [ ] **Step 1:** Write `modules/home/ai/omp/README.md` with the items listed in task 3.1.
- [ ] **Step 2:** Compare its option names and default path with the 2.1 evaluation output.
- [ ] **Step 3: Commit.**

## Task 4: Builds (task 4.1)

- [ ] **Step 1:** `nix build .#checks.aarch64-darwin.package-omp-browser-relay-extension .#checks.aarch64-darwin.darwin-stibnite .#checks.aarch64-darwin.home-manager-crs58 --no-link 2>&1 | tee logs/relay-checks-$(date +%Y%m%d-%H%M%S).log`.
- Expected: all succeed.

## Task 5: Activation and use on stibnite (tasks 5.1–5.4, human-gated)

- [ ] **Step 1:** Operator authorizes and runs the stibnite activation; record the start time.
- [ ] **Step 2:** Run the 5.1 inspection commands as `crs58`; read the alert evaluator's journal on magnetite and the notification topic from the recorded start; record each post with its cause in `verify.md`.
- [ ] **Step 3:** Person loads the folder in each Helium profile; record extension ID, version name and badge per profile.
- [ ] **Step 4:** From an omp session, run an Eval `browser` call with `app.relay: true` and one without; record which opened a Helium tab.
- [ ] **Step 5:** Leave 5.4 open with the recorded extension ID, to be checked at the first omp bump.

## Task 6: Integration verification (tasks 6.1, 6.2)

- [ ] **Step 1:** Assemble 5.1–5.3 evidence into `verify.md`.
- [ ] **Step 2:** For each `x86_64-linux` home user in `modules/checks/home.nix`, evaluate `programs.omp.browserRelay.extension.enable` and the activation names; record.
