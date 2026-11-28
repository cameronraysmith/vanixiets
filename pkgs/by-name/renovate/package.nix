# Renovate for the service in modules/nixos/renovate.nix: nixpkgs' expression
# at the release pin.json names, withheld from the fleet overlay and packaged
# for x86_64-linux, magnetite's system, only. The service's Renovate holds a
# repository token and runs commands on magnetite, so it follows upstream
# releases through its pin and a fix never waits for a nixpkgs update.
#
# update: nix run .#realize-pin -- renovate <version>
# source: https://github.com/renovatebot/renovate
{
  lib,
  stdenv,
  path,
  callPackage,
  fetchFromGitHub,
}:
let
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "renovate"; })
    pin
    pinPlan
    ;
  planned = (pinPlan pin.version).artifacts;
  # Called by path: `renovate` in this scope is this package.
  nixpkgsRenovate = callPackage (path + "/pkgs/by-name/re/renovate/package.nix") { };
in
if stdenv.hostPlatform.system != "x86_64-linux" then
  null
else
  nixpkgsRenovate.overrideAttrs (old: {
    inherit (pin) version;

    src = fetchFromGitHub (
      planned.src.sourceBuild.fetchFromGitHub // { inherit (pin.artifacts.src.sourceBuild) hash; }
    );

    # nixpkgs' pnpmDeps takes pname, version and src from the final attributes,
    # so only its fixed-output hash changes here.
    pnpmDeps = old.pnpmDeps.overrideAttrs { outputHash = pin.artifacts.pnpmDeps.sourceBuild.hash; };

    passthru = old.passthru // {
      inherit pin pinPlan;
      # nixosTests.renovate runs the nixpkgs package, not this one.
      tests = { inherit (old.passthru.tests) version; };
    };
  })
