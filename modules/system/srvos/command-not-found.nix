{
  flake.modules.nixos.base-command-not-found =
    { lib, ... }:
    {
      # TODO: remove this entire modules/system/srvos/ directory once either srvos
      # or nixpkgs lands a fix for the priority-1000 mkDefault collision on
      # programs.command-not-found.enable. nixpkgs commit 205b28d2ec70 (2026-04-21,
      # "nixos/programs/command-not-found: fix eval") changed the config-level
      # default from mkOptionDefault to mkDefault, colliding with srvos's
      # nixos/server/default.nix line 39 (also lib.mkDefault false). mkForce false
      # (priority 50) overrides both, preserving the srvos intent on every NixOS
      # host, each of which imports this part through the NixOS base.
      programs.command-not-found.enable = lib.mkForce false;
    };
}
