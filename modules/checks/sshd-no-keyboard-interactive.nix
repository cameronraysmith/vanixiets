# Structural check that sshd on every NixOS machine of the clan inventory
# refuses keyboard-interactive authentication, so PAM cannot offer password
# login to an account that has a password; key and certificate login remain.
# The setting comes from the clan sshd server role's extraModules
# (modules/clan/inventory/services/sshd.nix).
#
# Per machine it compares, with false and absent expected:
# - settings.KbdInteractiveAuthentication, the effective value after merging;
# - settings.ChallengeResponseAuthentication, its deprecated alias, which
#   renders first and so would win;
# - whether extraConfig names either option, as a Match block could re-enable
#   keyboard-interactive login for some connections.
#
# The mutant is cinnabar extended with a mkForce true override; its entry must
# differ from the expectation. Machine names come from inventory metadata, and
# the check is defined for x86_64-linux alone.
{ self, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      hosts = lib.attrNames (
        lib.filterAttrs (
          _: machine: (machine.machineClass or "nixos") == "nixos"
        ) self.clan.inventory.machines
      );
      observe =
        config:
        let
          inherit (config.services.openssh) settings extraConfig;
          names = lib.toLower extraConfig;
        in
        {
          KbdInteractiveAuthentication = settings.KbdInteractiveAuthentication;
          ChallengeResponseAuthentication = settings.ChallengeResponseAuthentication or null;
          extraConfigNamesIt =
            lib.hasInfix "kbdinteractiveauthentication" names
            || lib.hasInfix "challengeresponseauthentication" names;
        };
      expected = {
        KbdInteractiveAuthentication = false;
        ChallengeResponseAuthentication = null;
        extraConfigNamesIt = false;
      };
      render =
        observations:
        lib.concatStrings (lib.mapAttrsToList (name: o: "${name} ${builtins.toJSON o}\n") observations);
      mutantHost = "cinnabar";
      mutant =
        (self.nixosConfigurations.${mutantHost}.extendModules {
          modules = [ { services.openssh.settings.KbdInteractiveAuthentication = lib.mkForce true; } ];
        }).config;
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        sshd-no-keyboard-interactive = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        sshd-no-keyboard-interactive =
          assert lib.assertMsg (builtins.elem mutantHost hosts)
            "sshd-no-keyboard-interactive: mutant host ${mutantHost} is not a NixOS inventory machine";
          pkgs.runCommand "sshd-no-keyboard-interactive"
            {
              expected = render (lib.genAttrs hosts (_: expected));
              actual = render (lib.genAttrs hosts (name: observe self.nixosConfigurations.${name}.config));
              mutantExpected = render { ${mutantHost} = expected; };
              mutantActual = render { ${mutantHost} = observe mutant; };
              passAsFile = [
                "expected"
                "actual"
                "mutantExpected"
                "mutantActual"
              ];
              meta.description = "sshd refuses keyboard-interactive authentication on every NixOS machine";
            }
            ''
              if ! diff -u "$expectedPath" "$actualPath"; then
                echo "FAIL: sshd allows keyboard-interactive authentication on a NixOS machine"
                exit 1
              fi
              if diff -u "$mutantExpectedPath" "$mutantActualPath" > /dev/null; then
                echo "FAIL: mutant ${mutantHost}-kbd-interactive-true was accepted"
                exit 1
              fi
              echo "mutant ${mutantHost}-kbd-interactive-true rejected"
              touch $out
            '';
      };
    };
}
