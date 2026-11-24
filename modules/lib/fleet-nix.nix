# fleetNix: the Nix the fleet runs, for a package set. One value for the
# system's nix.package (system/nix-package.nix), the default devShell's `nix`
# and every tool that pins a Nix of its own, so they cannot drift apart.
#
# withFleetNix: a program that runs `nix` from PATH, with fleetNix first on
# its PATH, for programs whose result a host or a cluster consumes (nh's build
# before activation, nixidy's rendered manifests): they evaluate with the
# fleet's Nix whatever `nix` the caller has first.
#
# nixDirenv: nix-direnv calling fleetNix by absolute path. It takes `nix` from
# PATH before its fallback, and where that is iets' classic mode every one of
# its calls (all carry --no-warn-dirty) falls back with a notice: about 95
# lines per dev shell rebuild in this repository.
{ config, lib, ... }:
{
  flake.lib.fleetNix = pkgs: pkgs.nixVersions.nix_2_35;

  flake.lib.withFleetNix =
    pkgs: name: package:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ (config.flake.lib.fleetNix pkgs) ];
      text = ''exec ${lib.getExe' package name} "$@"'';
    };

  flake.lib.nixDirenv =
    pkgs:
    (pkgs.nix-direnv.override { nix = config.flake.lib.fleetNix pkgs; }).overrideAttrs (old: {
      # overrideAttrs reaches resholve's outer step, which copies its src, the
      # installed unresholved tree, and resholves the copy.
      src = pkgs.applyPatches {
        name = "nix-direnv-unresholved-fleet-nix";
        inherit (old) src;
        postPatch = ''
          substituteInPlace share/nix-direnv/direnvrc --replace-fail \
            'if command -v nix >/dev/null 2>&1; then' 'if false; then'
        '';
      };
    });
}
