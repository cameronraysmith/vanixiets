{ ... }:
{
  flake.modules.darwin.zt-dns = {
    environment.etc."resolver/zt" = {
      enable = true;
      text = ''
        nameserver fddb:4344:343b:14b9:399:93db:4344:343b
      '';
    };
  };
}
