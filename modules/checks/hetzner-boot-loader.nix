# checks.x86_64-linux.hetzner-boot-loader: the judge of
# flake.lib.hetznerBootLoader (modules/nixos/hetzner-cloud.nix) accepts each
# Hetzner type on the loader it gives and finds one problem in each fixture
# on another loader, or with a type it does not map. The fixtures are
# literals; the machine checks judge the real hosts.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      o = self.lib.hetznerBootLoader;
      boot = grub: systemdBoot: {
        loader = {
          grub.enable = grub;
          systemd-boot.enable = systemdBoot;
        };
      };
      cases = {
        sharedOnGrub = {
          type = "cx43";
          boot = boot true false;
          problems = 0;
        };
        dedicatedOnSystemdBoot = {
          type = "ccx23";
          boot = boot false true;
          problems = 0;
        };
        armOnSystemdBoot = {
          type = "cax21";
          boot = boot false true;
          problems = 0;
        };
        dedicatedOnGrub = {
          type = "ccx23";
          boot = boot true false;
          problems = 1;
        };
        dedicatedForcedToGrub = {
          type = "ccx23";
          boot = boot true true;
          problems = 1;
        };
        sharedOnSystemdBoot = {
          type = "cx43";
          boot = boot false true;
          problems = 1;
        };
        unmappedType = {
          type = "cpx31";
          boot = boot true false;
          problems = 1;
        };
      };
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      testSizes.checks.hetzner-boot-loader = {
        class = "medium";
        measured = false;
      };
      checks.hetzner-boot-loader = self.lib.mkJudgeCheck pkgs {
        name = "hetzner-boot-loader";
        judge =
          case:
          o.problems {
            name = "fixture";
            inherit (case) type boot;
          };
        inherit cases;
      };
    };
}
