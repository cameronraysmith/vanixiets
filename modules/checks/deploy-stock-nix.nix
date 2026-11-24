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
# nix-direnv call would fall back from the wrapper with a notice.
# Mutants, seen failing: pkgs.nh in place of flake.lib.withFleetNix in
# modules/darwin/app.nix; `{{nix_cmd}}` in k3d-up; nixDirenv without its patch.
# One system: the apps and the devShell are the same expression on every system.
{ config, ... }:
let
  flakeLib = config.flake.lib;
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
    in
    {
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
          ' nix-direnv ${flakeLib.nixDirenv pkgs}/share/nix-direnv/direnvrc)
          if [ -z "$nix" ] || [ "$nix" = "$classic" ]; then
            echo "nix-direnv: runs ''${nix:-no nix}"
            failed=1
          else
            echo "nix-direnv: runs $nix"
          fi
          if [ "$failed" -ne 0 ]; then exit 1; fi
          touch $out
        '';
      };
    };
}
