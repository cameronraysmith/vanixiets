# Structural check for omnigraph's startup wiring on magnetite.
#
# Two pieces keep a fresh or broken storage root from stalling a switch. The
# create-once bootstrap initializes a never-applied root before the server
# starts, so the server does not boot with zero graphs or exit on a missing
# cluster state; it is useful only if systemd orders it ahead of both the
# server and the apply unit. The readiness probe fails the server's start job
# within seconds when the server has exited or serves fewer graphs than
# declared; it is useful only if the server's ExecStartPost is that probe
# rather than the earlier /healthz poll that waited out its whole budget.
# Both properties are invisible until a deploy goes wrong, so the check reads
# them off magnetite's evaluated units. The behaviour of each program is
# covered by omnigraph-readiness-rehearsal and omnigraph-bootstrap-rehearsal.
{
  self,
  lib,
  ...
}:
{
  perSystem =
    { pkgs, system, ... }:
    let
      mkCheck = self.lib.mkStructuralCheck pkgs;

      units = self.nixosConfigurations.magnetite.config.systemd.services;
      server = units.omnigraph-server;
      bootstrap = units.omnigraph-cluster-bootstrap or null;

      # The store directory name and binary name of an executable path,
      # without its hash or string context: the oracle is which program runs,
      # and depending on the derivation itself would make this check build it.
      programIdentity =
        path:
        let
          m = builtins.match "${builtins.storeDir}/[0-9a-z]{32}-([^/]+)/bin/([^/ ]+)" (
            builtins.unsafeDiscardStringContext path
          );
        in
        if m == null then
          null
        else
          {
            package = builtins.elemAt m 0;
            bin = builtins.elemAt m 1;
          };

      bootstrapUnit = "omnigraph-cluster-bootstrap.service";
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-wiring = mkCheck {
          name = "omnigraph-wiring";
          actual = {
            bootstrapUnitExists = bootstrap != null;
            bootstrapBefore = lib.naturalSort (bootstrap.before or [ ]);
            bootstrapWantedBy = bootstrap.wantedBy or [ ];
            bootstrapType = bootstrap.serviceConfig.Type or null;
            bootstrapRemainAfterExit = bootstrap.serviceConfig.RemainAfterExit or null;
            bootstrapProgram = programIdentity (bootstrap.serviceConfig.ExecStart or "");

            # Wants, not Requires: a refused bootstrap must stay visible as a
            # failed unit rather than also cancel the server start job.
            serverWantsBootstrap = builtins.elem bootstrapUnit server.wants;
            serverAfterBootstrap = builtins.elem bootstrapUnit server.after;
            serverRequiresBootstrap = builtins.elem bootstrapUnit (server.requires or [ ]);

            serverProbe = programIdentity server.serviceConfig.ExecStartPost;
          };
          expected = {
            bootstrapUnitExists = true;
            bootstrapBefore = [
              "omnigraph-cluster-apply.service"
              "omnigraph-server.service"
            ];
            bootstrapWantedBy = [ "multi-user.target" ];
            bootstrapType = "oneshot";
            bootstrapRemainAfterExit = true;
            bootstrapProgram = {
              package = "omnigraph-cluster-bootstrap";
              bin = "omnigraph-cluster-bootstrap";
            };
            serverWantsBootstrap = true;
            serverAfterBootstrap = true;
            serverRequiresBootstrap = false;
            serverProbe = {
              package = "omnigraph-server-wait-ready";
              bin = "omnigraph-server-wait-ready";
            };
          };
        };
      };
    };
}
