# checks.x86_64-linux.host-list-keys: each host list written by hand beside
# the registry names exactly the registry's hosts of its kind: the cloud
# table the hosts tagged `cloud`, the observability table the hosts that run
# Nix, the ssh logins every host. Each name maps to whether it is in both, so
# the diff names a missing or extra host; the `_phantom*` entries pin that
# mapping on its three cases.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      mkCheck = self.lib.mkStructuralCheck pkgs;
      inherit (self.lib) hosts;

      inBoth =
        listed: registered:
        lib.genAttrs (lib.unique (listed ++ registered)) (
          name: lib.elem name listed && lib.elem name registered
        );
      allTrue = lib.mapAttrs (_: _: true);
      compare =
        listed: registered:
        let
          actual = inBoth listed registered;
        in
        {
          inherit actual;
          expected = allTrue actual;
        };
      hostsWhere = pred: lib.attrNames (lib.filterAttrs (_: pred) hosts);

      lists = {
        cloudMachines = compare (lib.concatMap lib.attrNames (lib.attrValues self.lib.cloudMachines)) (
          hostsWhere (host: host.class != "android" && lib.elem "cloud" host.tags)
        );
        observabilityHosts = compare (lib.attrNames self.lib.observabilityHosts) (
          hostsWhere (host: host.class != "android")
        );
        sshLogins = compare (lib.attrNames self.lib.sshLogins) (lib.attrNames hosts);
      };
      phantoms = {
        _phantomUnlisted = {
          actual = (inBoth [ ] [ "phantom" ]).phantom;
          expected = false;
        };
        _phantomUnregistered = {
          actual = (inBoth [ "phantom" ] [ ]).phantom;
          expected = false;
        };
        _phantomBoth = {
          actual = (inBoth [ "phantom" ] [ "phantom" ]).phantom;
          expected = true;
        };
      };
      cases = lists // phantoms;
    in
    {
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        host-list-keys = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        host-list-keys = mkCheck {
          name = "host-list-keys";
          actual = lib.mapAttrs (_: c: c.actual) cases;
          expected = lib.mapAttrs (_: c: c.expected) cases;
        };
      };
    };
}
