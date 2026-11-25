# checks.x86_64-linux.deploy-stock-nix: what a host, a cluster or a gate
# consumes is evaluated by the fleet's stock Nix even where `nix` is iets'
# classic mode (lib/nix-classic.nix). Two lists, one place:
# - `programs`: each entry point and the program in it that runs `nix` from
#   PATH (nh before activation, nixidy rendering manifests). The check builds
#   the PATH the entry point gives the program (an app's exported prefix, the
#   devShell's inputs in order) with the classic wrapper after it, resolves the
#   program, then `nix` as that program sees it, and fails on the wrapper.
# - `recipes`: justfile recipes whose own nix calls produce such a result;
#   each must call `{{nix_stock}}` and no `{{nix_cmd}}` or bare `nix`.
# Also nix-direnv (flake.lib.nixDirenv, every home's): its preflight, sourced
# with the classic wrapper first on PATH, must pick another `nix`; every
# nix-direnv call would fall back from the wrapper with a notice. And .envrc's
# `nix_direnv_version` guard must accept that build: a version above it fails
# the guard, and upstream's direnvrc, downloaded in its place, restores the
# PATH lookup; a missing guard fails too. Compared in the build, with sort -V,
# so a failure is this check's message rather than an evaluation error.
# And a home's direnvrc, sourced after that nix-direnv as direnv does, must
# leave the layout's watched flake-profile .rc alone on a cached load, or each
# shell's load makes every other shell in the project reload; once
# nix-direnv's use_flake stops refreshing gcroots, the direnvrc's override is
# dead and the check says to delete it.
# Mutants, seen failing: pkgs.nh in place of flake.lib.withFleetNix in
# modules/darwin/app.nix; `{{nix_cmd}}` in k3d-up; nixDirenv without its patch;
# .envrc requiring a newer nix-direnv; .envrc without its version guard; the
# home direnvrc without its `_nix_refresh_gcroots`.
# One system: the apps and the devShell are the same expression on every system.
{ config, ... }:
let
  flakeLib = config.flake.lib;
  homeDirenvrc =
    config.flake.homeConfigurations."crs58@x86_64-linux".config.xdg.configFile."direnv/direnvrc".source;
in
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      system,
      ...
    }:
    let
      classic = flakeLib.nixClassic pkgs;
      nixDirenv = flakeLib.nixDirenv pkgs;
      app = name: program: {
        inherit program;
        path = "$(prefix ${config.apps.${name}.program})";
      };
      programs = {
        darwin = app "darwin" "nh";
        os = app "os" "nh";
        home = app "home" "nh";
        devShell = {
          program = "nh";
          path = lib.makeBinPath config.devShells.default.nativeBuildInputs;
        };
        nixidy-build = app "nixidy-build" "nixidy";
        nixidy-bootstrap = app "nixidy-bootstrap" "nixidy";
        # nixidy-sync runs its own nixidy-build over packages.nixidy, the next entry.
        nixidy = {
          program = "nixidy";
          path = "${config.packages.nixidy}/bin";
        };
      };
      recipes = [
        "agents-skills-index"
        "k3d-up"
        "k3d-down"
      ];
      justfile = builtins.path {
        path = ../../justfile;
        name = "justfile";
      };
      envrc = builtins.path {
        path = ../../.envrc;
        name = "envrc";
      };
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        deploy-stock-nix = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        deploy-stock-nix = pkgs.runCommand "deploy-stock-nix" { } ''
          prefix() { sed -n 's/^export PATH="\(.*\):\$PATH"$/\1/p' "$1"; }
          classic=${classic}/bin/nix
          failed=0
          ${lib.concatStrings (
            lib.mapAttrsToList (name: e: ''
              path="${e.path}:${classic}/bin"
              p=$(PATH=$path command -v ${e.program}) || p=/dev/null
              nix=$(PATH="$(prefix "$p"):$path" command -v nix)
              if [ "$nix" = "$classic" ]; then
                echo "${name}: ${e.program} ($p) runs the classic wrapper"
                failed=1
              else
                echo "${name}: ${e.program} ($p) runs $nix"
              fi
            '') programs
          )}
          for r in ${lib.escapeShellArgs recipes}; do
            body=$(awk -v r="$r" '$0 ~ "^" r "( |:)" {on = 1; next} on && /^[^ \t]/ {exit} on' ${justfile})
            if [ -z "$body" ] || ! grep -q '{{nix_stock}}' <<<"$body" \
              || grep -qE '\{\{nix_cmd\}\}|(^|[^_{[:alnum:]-])nix (build|eval|run|develop|shell|hash|path-info)' <<<"$body"; then
              echo "just $r: does not evaluate with {{nix_stock}} alone"
              failed=1
            else
              echo "just $r: {{nix_stock}}"
            fi
          done
          nix=$(PATH="${classic}/bin:$PATH" bash -c '
            log_error() { echo "$*" >&2; }
            log_status() { :; }
            has() { command -v "$1" >/dev/null; }
            watch_file() { :; }
            PATH_add() { :; }
            direnv_layout_dir() { echo "$TMPDIR/direnv-layout"; }
            direnv=true NIX_DIRENV_SKIP_VERSION_CHECK=1
            source "$1"
            _nix_direnv_preflight >&2 && echo "$_nix_direnv_nix"
          ' nix-direnv ${nixDirenv}/share/nix-direnv/direnvrc)
          if [ -z "$nix" ] || [ "$nix" = "$classic" ]; then
            echo "nix-direnv: runs ''${nix:-no nix}"
            failed=1
          else
            echo "nix-direnv: runs $nix"
          fi
          packaged=${nixDirenv.version}
          required=$(sed -n '/nix_direnv_version "/{s/.*nix_direnv_version "\([^"]*\)".*/\1/p;q}' ${envrc})
          if [ -z "$required" ]; then
            echo ".envrc: no nix_direnv_version guard; packaged nix-direnv is $packaged"
            failed=1
          elif [ "$(printf '%s\n' "$packaged" "$required" | sort -V | tail -n 1)" != "$packaged" ]; then
            echo ".envrc: requires nix-direnv $required, packaged is $packaged"
            failed=1
          else
            echo ".envrc: requires nix-direnv $required, packaged is $packaged"
          fi
          rcTime=$(cd "$TMPDIR" && XDG_CACHE_HOME=$TMPDIR/cache bash -c '
            log_error() { echo "$*" >&2; }
            log_status() { :; }
            has() { command -v "$1" >/dev/null; }
            watch_file() { :; }
            PATH_add() { :; }
            direnv=true NIX_DIRENV_SKIP_VERSION_CHECK=1
            source "$1"
            source "$2"
            layout=$(direnv_layout_dir)
            mkdir -p "$layout"
            touch -d @0 "$layout/flake-profile-x.rc"
            _nix_refresh_gcroots
            stat -c %Y "$layout/flake-profile-x.rc"
          ' nix-direnv ${nixDirenv}/share/nix-direnv/direnvrc ${homeDirenvrc})
          if [ "$rcTime" != 0 ]; then
            echo "direnvrc: a cached load touches the watched flake-profile .rc"
            failed=1
          else
            echo "direnvrc: a cached load leaves the watched flake-profile .rc alone"
          fi
          if ! grep -qx '[[:space:]]*_nix_refresh_gcroots' ${nixDirenv}/share/nix-direnv/direnvrc; then
            echo "nix-direnv: use_flake no longer refreshes gcroots; delete _nix_refresh_gcroots from modules/home/terminal/direnv.nix"
            failed=1
          fi
          if [ "$failed" -ne 0 ]; then exit 1; fi
          touch $out
        '';
      };
    };
}
