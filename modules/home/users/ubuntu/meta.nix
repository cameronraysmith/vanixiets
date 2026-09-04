{ config, ... }:
{
  flake.users.ubuntu = {
    meta = {
      username = "ubuntu";
      fullname = "Cameron Smith";
      email = "cameron.ray.smith@gmail.com";
      githubUser = "cameronraysmith";
      # `hm-sops-bridge` is a NixOS module and this profile never runs under
      # NixOS: the sandbox receives its age key from the `devin-bootstrap` app
      # instead, so there is no bridge deployment to name.
      sopsAgeKeyId = null;
      sshKeys = [ ];
    };

    # The account exists only inside a hosted x86_64-linux sandbox, so the
    # darwin entry would be a configuration nobody can activate.
    systems = [ "x86_64-linux" ];

    aggregates = with config.flake.modules.homeManager; [
      base-sops
      core
      development
      herdr
      shell
      terminal
    ];
  };
}
