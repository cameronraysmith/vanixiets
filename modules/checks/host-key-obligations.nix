# checks.x86_64-linux.host-key-obligations: the judge of
# flake.lib.hostKeyObligations (modules/lib/host-keys.nix) finds no failure
# for a host whose generated openssh public key equals its hostKeys entry,
# for a host absent from hostKeys and for a host with no openssh generator,
# and exactly one failure for a value one character off and for the value
# with its trailing " \n" trimmed, which is part of the pinned bytes.
#
# The per-host fact is a module assertion on every NixOS host
# (modules/lib/host-keys.nix), which the nixos-<host> checks build. No host is
# evaluated here; the fixtures are literal host configurations, so the check
# runs on x86_64-linux only.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      o = self.lib.hostKeyObligations;
      pinned = self.lib.hostKeys.cinnabar;
      # The pinned key with its first key-material character changed.
      oneOff =
        let
          i = lib.stringLength "ssh-ed25519 ";
          c = lib.substring i 1 pinned;
        in
        lib.substring 0 i pinned
        + (if c == "A" then "B" else "A")
        + lib.substring (i + 1) (lib.stringLength pinned) pinned;
      withKey = value: {
        clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub" = { inherit value; };
      };
      cases = {
        accepted = {
          name = "cinnabar";
          hostConfig = withKey pinned;
          problems = 0;
        };
        oneCharacterOff = {
          name = "cinnabar";
          hostConfig = withKey oneOff;
          problems = 1;
        };
        trimmed = {
          name = "cinnabar";
          hostConfig = withKey (lib.trim pinned);
          problems = 1;
        };
        absentFromHostKeys = {
          name = "not-a-fleet-host";
          hostConfig = withKey oneOff;
          problems = 0;
        };
        noOpensshGenerator = {
          name = "cinnabar";
          hostConfig.clan.core.vars.generators = { };
          problems = 0;
        };
      };
      wrong = lib.filterAttrs (
        _: case: lib.length (o.failures case.name case.hostConfig) != case.problems
      ) cases;
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      testSizes.checks = {
        # nixbot: 0 runs, too few to class (declare-test-size-classes design D4)
        host-key-obligations = {
          class = "medium";
          measured = false;
        };
      };
      checks.host-key-obligations =
        assert lib.assertMsg (
          wrong == { }
        ) "host-key-obligations: the judge misjudges ${toString (lib.attrNames wrong)}";
        pkgs.runCommand "host-key-obligations" { } "touch $out";
    };
}
