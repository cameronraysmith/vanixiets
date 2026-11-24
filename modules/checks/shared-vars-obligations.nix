# checks.x86_64-linux.shared-vars-obligations: the judge of
# flake.lib.sharedVarsObligations (modules/lib/shared-vars-recipients.nix)
# accepts a host that is a recipient of every shared secret it deploys,
# ignores public shared files, undeployed shared files and per-machine
# generators, and finds exactly one problem in each mutant: a deployed shared
# secret the host is not a recipient of, and the same with the file's
# `secret` left at its default.
#
# Per-host facts are module assertions on every NixOS and darwin host
# (modules/lib/shared-vars-recipients.nix), which the nixos-<host> and
# darwin-<host> checks build. No host is evaluated here; the fixtures are
# literals, so the check runs on x86_64-linux only.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      o = self.lib.sharedVarsObligations;
      recipientOf =
        allowed: gen: file:
        builtins.elem "${gen}/${file}" allowed;
      shared = files: {
        share = true;
        inherit files;
      };
      cases = {
        accepted = {
          generators.ntfy-alerter = shared { token.secret = true; };
          allowed = [ "ntfy-alerter/token" ];
          problems = 0;
        };
        publicIgnored = {
          generators.otel-ca = shared { "ca.crt".secret = false; };
          allowed = [ ];
          problems = 0;
        };
        undeployedIgnored = {
          generators.otel-ca = shared {
            "ca.key" = {
              secret = true;
              deploy = false;
            };
          };
          allowed = [ ];
          problems = 0;
        };
        perMachineIgnored = {
          generators.otel-cert.files."key.pem".secret = true;
          allowed = [ ];
          problems = 0;
        };
        notRecipient = {
          generators.ntfy-alerter = shared { token.secret = true; };
          allowed = [ ];
          problems = 1;
        };
        notRecipientDefaultSecret = {
          generators.ntfy-alerter = shared { token = { }; };
          allowed = [ ];
          problems = 1;
        };
      };
      wrong = lib.filterAttrs (
        _: case:
        lib.length (
          o.missing {
            inherit (case) generators;
            isRecipient = recipientOf case.allowed;
          }
        ) != case.problems
      ) cases;
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        shared-vars-obligations = {
          class = "medium";
          measured = false;
        };
      };
      checks.shared-vars-obligations =
        assert lib.assertMsg (
          wrong == { }
        ) "shared-vars-obligations: the judge misjudges ${toString (lib.attrNames wrong)}";
        pkgs.runCommand "shared-vars-obligations" { } "touch $out";
    };
}
