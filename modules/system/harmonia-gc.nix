# Garbage collection via harmonia-gc, replacing the nixpkgs/nix-darwin gc module on every host.
# The nixpkgs/nix-darwin automatic gc must stay disabled: the upstream module warns when it and harmonia-gc both run.
{ inputs, ... }:
let
  gcSettings = {
    enable = true;
    automatic = true;
    deleteOlderThan = "10d";
    keepRecent = "1d";
  };
in
{
  flake.modules.darwin.base = {
    imports = [ inputs.harmonia.darwinModules.harmonia ];

    # launchd runs a missed calendar interval on the next wake, so a sleeping laptop still collects once per day.
    services.harmonia-dev.gc = gcSettings // {
      startCalendarInterval = [
        {
          Hour = 3;
          Minute = 15;
        }
      ];
    };
  };

  flake.modules.nixos.base = {
    imports = [ inputs.harmonia.nixosModules.harmonia ];

    # Jitter keeps fleet hosts from collecting in lockstep.
    services.harmonia-dev.gc = gcSettings // {
      dates = "*-*-* 04:00:00 America/New_York";
      randomizedDelaySec = "5min";
    };
  };
}
