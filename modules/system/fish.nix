# System-level fish shell enablement
# Makes fish available as a shell option; user config in modules/home/shell/fish.nix
{ ... }:
{
  flake.modules = {
    # NixOS system module
    nixos.fish =
      { pkgs, lib, ... }:
      {
        programs.fish.enable = true;

        # Disable auto-generated completions to prevent staleness
        # Pattern from mic92-clan-dotfiles
        environment.etc."fish/generated_completions".source = lib.mkForce (
          pkgs.runCommand "fish-no-completions" { } "mkdir $out"
        );
      };

    # Darwin system module
    darwin.fish =
      { ... }:
      {
        programs.fish.enable = true;
      };
  };
}
