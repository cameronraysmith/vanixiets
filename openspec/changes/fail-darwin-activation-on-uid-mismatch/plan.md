# Fail darwin activation on a uid mismatch: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a darwin host's activation stops, before it changes anything, when an attached account exists with a uid other than its recorded uid; a medium check proves the comparison fails on a mutant. Covers tasks.md groups 1-4.

**Architecture:** the darwin branch of `modules/system/home-manager-integration.nix` renders one `id -u` comparison per attachment into a read-only internal option `home-manager-integration.uidPreflight` and appends it to `system.activationScripts.preActivation.text`; `modules/checks/darwin-uid-preflight.nix` runs each darwin host's rendered text under a stub `id`. Nothing vendored is patched.

**Tech Stack:** nix-darwin activation scripts; flake-parts perSystem checks; bash.

**Spec:** `openspec/changes/fail-darwin-activation-on-uid-mismatch/`: `design.md` (D1-D6), `specs/darwin-account-uid-agreement`, `specs/darwin-account-uid-agreement-interface`, `specs/world-assumptions` (A370-A374), `tasks.md`.

## Global Constraints

- Implementation starts only after the operator approves the derivation change to the four darwin toplevels and the deploy it needs.
- One commit. This is a shared jj development join: never `jj new`, `describe` or `commit` on another session's chain; the integrating agent routes the edits.
- `just drv-diff <parent> <commit> openspec/changes/fail-darwin-activation-on-uid-mismatch/drv-delta.txt` (about 16 minutes) is the oracle; the implementer returns the command and does not run it.
- `checks.<system>` names read only static data: the check's name is a literal; host configurations are read only in its value.
- Mutants run in a throwaway tree (`jj workspace add` under `/tmp`), never in `@`.

## Grounding: the vendored interfaces

Read at the locked revisions in task 1.2 and cited in a sources log:
- nix-darwin `modules/system/activation-scripts.nix:84-140`: `#!/usr/bin/env -i ${stdenv.shell}`, `set -e`, `set -o pipefail`, `PATH` is the activation path (which includes `/usr/bin`), then `preActivation`, `checks`, `createRun`, `extraActivation`, `groups`, `users`, …
- nix-darwin `modules/users/default.nix:285-288`: the comparison nix-darwin warns on is `u=$(id -u ${name} 2> /dev/null) || true; if [[ -n "$u" && "$u" -ne "${uid}" ]]`. The new comparison uses the same lookup and argument list (`id -u <name>`).
- nix-darwin `pkgs/nix-tools/darwin-rebuild.sh:218-233` and `modules/system/checks.nix:317-324`: `switch` sets the profile then activates; `check` runs `activate` with `checkActivation=1`, which exits 0 after `checks`.
- nix-darwin `modules/services/activate-system/default.nix:61-70`: the boot daemon runs `checks`, `etc`, `keyboard`, not `preActivation`.
- `modules/system/deploy-record.nix:207-211`: deploy-record's `preActivation` read is `mkBefore`; the comparison at default priority follows it.

## Task 1: Baselines

- [ ] **Step 1:** Record the parent's commit id (`jj log -r <parent> --no-graph -T commit_id`).
- [ ] **Step 2:** For each of stibnite, blackphos, argentum, rosegold: `nix eval --raw .#darwinConfigurations.<h>.config.system.build.toplevel.drvPath`; record in `logs/fdaum-1-baseline-<ts>.log`.
- [ ] **Step 3:** Read the grounding lines above at the locked revisions (store paths from `nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.nix-darwin.outPath'` and the same for `clan-core`); write `logs/fdaum-1-sources-<ts>.md`.
- [ ] **Step 4:** `nix eval --json .#darwinConfigurations.<h>.config.users.knownUsers` for each host; confirm the attachments are members.

## Task 2: The comparison

**Files:** modify `modules/system/home-manager-integration.nix` (darwin branch, the `lib.optionalAttrs (class == "darwin")` block; option beside `home-manager-integration.attachments`).

- [ ] **Step 1:** Declare the option (both classes declare it; only darwin sets it):

```nix
options.home-manager-integration.uidPreflight = lib.mkOption {
  type = lib.types.lines;
  internal = true;
  readOnly = true;
  default = "";
  description = "The activation-time comparison of each attached account's uid with its record (darwin).";
};
```

  If `readOnly` with a darwin-only definition conflicts with the default, drop the `default` and define it in both branches (NixOS: `""`).

- [ ] **Step 2:** In the darwin block, render and wire it:

```nix
home-manager-integration.uidPreflight = ''
  uidMismatches=()
  ${lib.concatMapStringsSep "\n" (
    account:
    let
      uid = toString attachments.${account}.uid;
    in
    ''
      u=$(id -u ${lib.escapeShellArg account} 2>/dev/null) || u=
      if [[ -n "$u" && "$u" != ${uid} ]]; then
        uidMismatches+=(${lib.escapeShellArg "${hostName}: account ${account} has uid "}"$u"${lib.escapeShellArg ", recorded ${uid} at flake.fleet.hosts.${hostName}.users.${account}.uid"})
      fi
    ''
  ) accounts}
  if (( ''${#uidMismatches[@]} )); then
    printf >&2 '\e[1;31merror: an attached account has a uid other than its record, aborting activation\e[0m\n'
    printf >&2 '  %s\n' "''${uidMismatches[@]}"
    printf >&2 'Correct the record in modules/lib/host-users.nix, or the account, and deploy again.\n'
    exit 1
  fi
'';
system.activationScripts.preActivation.text = config.home-manager-integration.uidPreflight;
```

  String comparison (`!=`) is deliberate: a non-numeric `id` output is a mismatch (D3 fail closed), where `-ne` would error.

- [ ] **Step 3:** `nix eval --raw .#darwinConfigurations.blackphos.config.home-manager-integration.uidPreflight` and read it: crs58 502, raquel 506, option paths present.
- [ ] **Step 4:** `nix eval --raw .#darwinConfigurations.stibnite.config.system.activationScripts.script.text` (or the `activate` text option nix-darwin exposes) and `grep -n` for the deploy-record read, `uidMismatches=()` and the macOS version check; confirm that order.
- [ ] **Step 5:** One NixOS host's toplevel drvPath equals its baseline (`cinnabar`).

## Task 3: The mutant check

**Files:** create `modules/checks/darwin-uid-preflight.nix`.

- [ ] **Step 1:** Write the check:

```nix
# checks.x86_64-linux.darwin-uid-preflight: each darwin host's activation-time
# uid comparison (home-manager-integration.uidPreflight) passes when every
# attached account has its recorded uid or is absent, and fails naming the
# account when one has another uid. A stub `id` stands in for macOS's lookup.
# One system: the derivation is a bash script and does not differ by system.
{ config, lib, ... }:
let
  inherit (config) flake;
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        darwin-uid-preflight = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        darwin-uid-preflight =
          let
            hosts = lib.attrNames (lib.filterAttrs (_: h: h.class == "darwin") flake.fleet.hosts);
            caseOf =
              host:
              let
                cfg = flake.darwinConfigurations.${host}.config;
                uids = lib.mapAttrs (_: a: a.uid) cfg.home-manager-integration.attachments;
                mutant = lib.head (lib.attrNames uids);
                table = u: lib.concatStrings (lib.mapAttrsToList (n: v: "${n} ${toString v}\n") u);
              in
              ''
                run ${host} ${pkgs.writeText "${host}-script" cfg.home-manager-integration.uidPreflight} \
                  ${pkgs.writeText "${host}-match" (table uids)} \
                  ${pkgs.writeText "${host}-mutant" (table (uids // { ${mutant} = uids.${mutant} + 1; }))} \
                  ${lib.escapeShellArg mutant}
              '';
          in
          pkgs.runCommand "darwin-uid-preflight-check" { } ''
            mkdir stub
            cat > stub/id <<'EOF'
            #!${pkgs.runtimeShell}
            [ "$1" = -u ] || exit 2
            while read -r n u; do [ "$n" = "$2" ] && { echo "$u"; exit 0; }; done < "$UID_TABLE"
            exit 1
            EOF
            chmod +x stub/id
            export PATH="$PWD/stub:$PATH"
            run() {
              host=$1 script=$2 match=$3 mutant=$4 account=$5
              UID_TABLE=$match ${pkgs.bash}/bin/bash -e "$script" || { echo "$host: match case failed"; exit 1; }
              UID_TABLE=/dev/null ${pkgs.bash}/bin/bash -e "$script" || { echo "$host: absent case failed"; exit 1; }
              if UID_TABLE=$mutant ${pkgs.bash}/bin/bash -e "$script" 2>err; then echo "$host: mutant uid passed"; exit 1; fi
              grep -q "account $account has uid" err || { echo "$host: mutant not named"; cat err; exit 1; }
            }
            ${lib.concatMapStrings caseOf hosts}
            touch $out
          '';
      };
    };
}
```

- [ ] **Step 2:** `nix build .#checks.x86_64-linux.darwin-uid-preflight` succeeds.
- [ ] **Step 3:** In a throwaway tree, apply each mutant in turn to the darwin block of the integration aspect and build only the case it must fail: (a) `uidPreflight = ""` (mutant-uid case must fail); (b) the `if` condition replaced by `false` (mutant-uid case must fail); (c) `[[ "$u" != ${uid} ]]` without the `-n "$u"` guard (absent case must fail). Log each outcome to `logs/fdaum-3-mutants-<ts>.log`.
- [ ] **Step 4:** Write `drv-delta.txt` in the change directory, in the format of `nix run .#drv-diff -- --help`, with the reason on each line:

```
darwinConfigurations.stibnite.config.system.build.toplevel  changed  # preActivation gains the uid comparison (D2)
darwinConfigurations.blackphos.config.system.build.toplevel  changed
darwinConfigurations.argentum.config.system.build.toplevel  changed
darwinConfigurations.rosegold.config.system.build.toplevel  changed
checks.x86_64-linux.darwin-uid-preflight  added  # D5
checks.x86_64-linux.fleet-alert  changed  # renders every testSizes.checks entry
```

  Re-read which checks embed `modules/system/home-manager-integration.nix` by store path at the parent and add each that is not covered by `modules/apps/drv-diff-base-allow.txt`; aarch64-darwin `checks` that build the darwin toplevels are added by exact path.

## Task 4: Integration verification (operator)

- [ ] **Step 1:** Return `just drv-diff <parent> <commit> openspec/changes/fail-darwin-activation-on-uid-mismatch/drv-delta.txt` to the operator.
- [ ] **Step 2:** The operator runs `just darwin-test <host>` on each Mac; expects `ok`.
- [ ] **Step 3:** The operator deploys each Mac; the output has no `unexpected uid` warning; alerts since the deploy started are read and recorded.
- [ ] **Step 4:** `id -u <account>` and `dscl . -read /Users/<account> UniqueID` agree for each attachment (A374).

## Review Focus

- The comparison sits after deploy-record's `mkBefore` read and before nix-darwin's checks; a later `mkBefore` elsewhere would not move it ahead of anything that changes the system, since all of preActivation precedes `checks`.
- A darwin fixture in a runtime test that sets `home-manager-integration.attachments` also renders the comparison; confirm the omnigent-worker fixtures still build.
- A failed switch leaves the system profile one generation ahead (A371); the runbook line in the error message and design Migration Plan covers it.
