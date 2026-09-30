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
          # Public seeds from modules/home/development/radicle.nix, minus
          # cinnabar itself. iris and rosa use heartwood's bootstrap hostnames
          # (radicle.network; the radicle.xyz names still resolve to the same
          # nodes), and seed.radicle.dev is the address the seed.radicle.xyz
          # node advertises for itself.
          preferredSeeds = [
            "z6MksmpU5b1dS7oaqF2bHXhQi1DWy2hB7Mh9CuN7y1DN6QSz@seed.radicle.dev:8776"
            "z6MkrLMMsiPWUcNPHcRajuMi9mDfYckSoJyPwwnknocNYPm7@iris.radicle.network:8776"
            "z6Mkmqogy2qEM2ummccUthFEaaHvyYmYBYh3dbe9W4ebScxo@rosa.radicle.network:8776"
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
