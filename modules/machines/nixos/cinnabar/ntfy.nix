{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" = {
    services.ntfy-sh = {
      enable = true;
      settings = {
        listen-http = "[::1]:2586";
        base-url = "https://ntfy.zt";
      };
    };
  };
}
