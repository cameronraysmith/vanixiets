# Garbage collection via harmonia-gc, replacing the nixpkgs/nix-darwin gc module on every host.
# The nixpkgs/nix-darwin automatic gc must stay disabled: the upstream module warns when it and harmonia-gc both run.
#
# harmonia-gc, like Nix's own auto-GC, waits for /nix/var/nix/gc.lock with no
# time limit (acquire_gc_lock in harmonia-store-gc/src/gc.rs), and a run that
# waits keeps its unit or job busy, so the next scheduled run does not start
# either. Every run is therefore bounded (bound-fleet-garbage-collection D1):
# NixOS by the oneshot unit's TimeoutStartSec, darwin, where launchd has no
# run time limit, by running upstream's argv under coreutils' `timeout`.
# darwin also keeps the run's output and errors in one log (D2).
#
# flake.lib.harmoniaGcObligations.failures, asserted by
# modules/checks/machines.nix on every nixos-<host> and darwin-<host> check,
# judges each host's evaluated unit or job, so a later override that drops the
# bound or the log fails before deploy;
# checks.x86_64-linux.harmonia-gc-obligations runs the judge over fixtures.
{
  config,
  inputs,
  lib,
  ...
}:
let
  bound = "2h";
  logPath = "/var/log/harmonia-gc.log";

  gcSettings = {
    enable = true;
    automatic = true;
    keepRecent = "1d";
  };

  # One message per way `service` fails the bound or, on darwin, the log.
  # `service` is the unit's serviceConfig on NixOS, the job's on darwin;
  # `argv` is services.harmonia-dev.gc.argv, which the darwin wrapper must
  # end with exactly.
  problems =
    {
      platform,
      service,
      argv ? null,
    }:
    if platform == "nixos" then
      lib.optional ((service.TimeoutStartSec or null) != bound)
        "harmonia-gc's TimeoutStartSec is ${
          builtins.toJSON (service.TimeoutStartSec or null)
        }, not \"${bound}\""
    else
      let
        args = service.ProgramArguments or [ ];
        wrapper = lib.take 2 args;
        wrapped =
          builtins.length wrapper == 2
          && lib.hasSuffix "/bin/timeout" (builtins.head wrapper)
          && builtins.elemAt wrapper 1 == bound;
      in
      (
        if !wrapped then
          [ "harmonia-gc's ProgramArguments do not start with timeout ${bound}" ]
        else
          lib.optional (lib.drop 2 args != argv) "harmonia-gc's timeout wraps a list other than its argv"
      )
      ++
        lib.concatMap
          (
            key:
            lib.optional ((service.${key} or null) != logPath)
              "harmonia-gc's ${key} is ${builtins.toJSON (service.${key} or null)}, not ${logPath}"
          )
          [
            "StandardOutPath"
            "StandardErrorPath"
          ];

  harmoniaGcObligations = {
    inherit bound logPath problems;
    failures =
      name: hostConfig:
      if config.flake.lib.hosts.${name}.class == "darwin" then
        problems {
          platform = "darwin";
          service = hostConfig.launchd.daemons.harmonia-gc.serviceConfig;
          inherit (hostConfig.services.harmonia-dev.gc) argv;
        }
      else
        problems {
          platform = "nixos";
          service = hostConfig.systemd.services.harmonia-gc.serviceConfig;
        };
  };
in
{
  flake.lib = {
    inherit harmoniaGcObligations;
  };

  fleetObligations.harmoniaGcObligations.failures = harmoniaGcObligations.failures;

  flake.modules.darwin.base =
    { config, pkgs, ... }:
    {
      imports = [ inputs.harmonia.darwinModules.harmonia ];

      # launchd runs a missed calendar interval on the next wake, so a sleeping laptop still collects once per day.
      # Laptops keep 7 days of generations, servers 10 (D4), magnetite 3.
      services.harmonia-dev.gc = gcSettings // {
        deleteOlderThan = "7d";
        startCalendarInterval = [
          {
            Hour = 3;
            Minute = 15;
          }
        ];
      };

      launchd.daemons.harmonia-gc.serviceConfig = {
        ProgramArguments = lib.mkForce (
          [
            "${pkgs.coreutils}/bin/timeout"
            bound
          ]
          ++ config.services.harmonia-dev.gc.argv
        );
        StandardOutPath = logPath;
        StandardErrorPath = logPath;
      };
    };

  flake.modules.nixos.base-harmonia-gc = {
    imports = [ inputs.harmonia.nixosModules.harmonia ];

    # Jitter keeps fleet hosts from collecting in lockstep. A host may set
    # its own schedule and retention; magnetite does.
    services.harmonia-dev.gc = gcSettings // {
      deleteOlderThan = lib.mkDefault "10d";
      dates = lib.mkDefault "*-*-* 04:00:00 America/New_York";
      randomizedDelaySec = "5min";
    };

    # The unit is Type=oneshot, so the start timeout bounds the whole run.
    # Batch CPU and idle I/O scheduling, as srvos gives nix-gc.service, so a
    # collection yields to builds and services.
    systemd.services.harmonia-gc.serviceConfig = {
      TimeoutStartSec = bound;
      CPUSchedulingPolicy = "batch";
      IOSchedulingClass = "idle";
      IOSchedulingPriority = 7;
    };
  };
}
