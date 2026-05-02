{ config, ... }:
{
  flake.users.tara = {
    meta = {
      username = "tara";
      fullname = "Tara Chari";
      email = "17519396+tarachari3@users.noreply.github.com";
      githubUser = "tarachari3";
      sopsAgeKeyId = "tara";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHwVoxa3ZO+DA+Tun3vthf2oiY2itTqSA5t9lm5Ac8vg"
      ];
    };
    aggregates = with config.flake.modules.homeManager; [
      base-sops
      core
      development
      packages
      shell
      terminal
      tools
      agents-md
    ];
  };
}
