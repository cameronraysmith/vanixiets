# pin-contract (openspec change automate-package-version-bumps, design D9):
# the package pin type of lib/pins.nix against valid and malformed fixtures
# (lib/pins.test.nix), and the `passthru.pin` of every package with a
# pin.json, which is evaluated here, so a malformed package pin fails the
# check's evaluation. The realizer hashes a sourceBuild artifact and a
# fixedOutputHash companion through `nix-update --custom-dep`, which reads
# `<package>.<attribute>`, so each must name an attribute carrying an
# `outputHash`; whether it does is recorded here and asserted in the cases.
{ config, lib, ... }:
{
  perSystem =
    {
      self',
      pkgs,
      system,
      ...
    }:
    let
      byName = ../../pkgs/by-name;
      pinned = lib.filter (name: builtins.pathExists (byName + "/${name}/pin.json")) (
        lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir byName))
      );
      packagePins = lib.genAttrs pinned (name: self'.packages.${name}.passthru.pin);
      resolves = package: attr: self'.packages.${package}.${attr} or { } ? outputHash;
      fixedOutputs = lib.concatLists (
        lib.mapAttrsToList (
          name: pin:
          map (artifact: {
            at = "${name}.${artifact}";
            resolves = resolves name artifact;
          }) (lib.attrNames (lib.filterAttrs (_: entry: entry ? sourceBuild) pin.artifacts))
          ++ map (
            c:
            let
              inherit (c.kind.fixedOutputHash) package fodAttr;
            in
            {
              at = "${package}.${fodAttr}";
              resolves = resolves package fodAttr;
            }
          ) (lib.filter (c: c.kind ? fixedOutputHash) pin.companions)
        ) packagePins
      );
      packageData = pkgs.writeText "package-pins.json" (
        builtins.toJSON { inherit packagePins fixedOutputs; }
      );
      check = config.flake.lib.mkEvalCheck pkgs {
        name = "pin-contract";
        testFile = pkgs.writeText "pin-contract.tests.nix" ''
          let
            lib = import ${pkgs.path}/lib;
          in
          import ${../../lib/pins.test.nix} {
            inherit lib;
            pins = import ${../../lib/pins.nix} { inherit lib; };
            inherit (lib.importJSON ${packageData}) packagePins fixedOutputs;
          }
        '';
      };
    in
    {
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # unmeasured: no nixbot run yet (design D9)
        pin-contract = {
          class = "small";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") { pin-contract = check; };
    };
}
