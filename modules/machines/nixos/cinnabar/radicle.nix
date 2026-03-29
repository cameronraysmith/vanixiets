{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { config, pkgs, ... }:
    {
      # Clan vars key generator for radicle node identity
      clan.core.vars.generators.radicle = {
        files.ssh-private-key = {
          owner = "radicle";
          neededFor = "services";
        };
        files.ssh-public-key = {
          secret = false;
        };
        runtimeInputs = [ pkgs.openssh ];
        script = ''
          ssh-keygen -t ed25519 -N "" -f $out/ssh-private-key \
            -C "radicle@${config.networking.hostName}"
          ssh-keygen -y -f $out/ssh-private-key > $out/ssh-public-key
          rm -f $out/ssh-private-key.pub
        '';
      };

      # Radicle seed node
      services.radicle = {
        enable = true;
        privateKey = config.clan.core.vars.generators.radicle.files.ssh-private-key.path;
        publicKey = config.clan.core.vars.generators.radicle.files.ssh-public-key.path;

        node = {
          listenAddress = "[::]";
          listenPort = 8776;
        };

        settings = {
          node = {
            alias = "cinnabar";
            externalAddresses = [ "radicle.zt:8776" ];
            seedingPolicy.default = "block";
          };
          preferredSeeds = [
            "z6MkrLMMsiPWUcNPHcRajuMi9mDfYckSoJyPwwnknocNYPm7@seed.radicle.xyz:8776"
            "z6Mkmqogy2qEM2ummccUthFEaaHvyYmYBYh3dbe9W4ebScxo@iris.radicle.xyz:8776"
          ];
          web.pinned.repositories = [ ];
        };

        httpd = {
          enable = true;
          listenAddress = "[::1]";
          listenPort = 8080;
        };
      };
    };
}
