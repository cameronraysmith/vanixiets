# Mosh (mobile shell) server for every fleet machine.
# mosh-server is spawned through an ordinary SSH login, so it reuses the
# existing key and certificate trust; only the UDP return path is new.
{ config, lib, ... }:
let
  inherit (config.flake.lib) meshInterfaces;
in
{
  flake.modules = {
    nixos.base-mosh =
      { config, ... }:
      {
        programs.mosh = {
          enable = true;
          # The upstream module's openFirewall opens 60000-61000 on every
          # interface. Scope the range to the mesh instead.
          openFirewall = false;
        };

        # mosh-server binds the first free port in [PORT_RANGE_LOW,
        # PORT_RANGE_HIGH] = [60001, 60999] (src/network/network.h), one port
        # per live session.
        networking.firewall.interfaces = lib.genAttrs (meshInterfaces config) (_: {
          allowedUDPPortRanges = [
            {
              from = 60001;
              to = 60999;
            }
          ];
        });
      };

    darwin.base =
      { pkgs, ... }:
      {
        # macOS has no declarative packet filter here: pf loads only Apple's
        # own anchors and none of them block inbound UDP, and the application
        # firewall is off. Shipping the binary is the whole change.
        environment.systemPackages = [ pkgs.mosh ];
      };
  };
}
