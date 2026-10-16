# Per-host declaration of the shared ghq reference tree: whether this host shares
# one, which accounts read it, and the writer account that alone may change it.
# The NixOS and darwin adapters (modules/{nixos,darwin}/shared-reference-tree.nix)
# consume these options.
{ lib, ... }:
let
  options =
    isDarwin:
    { ... }:
    {
      options.services.shared-reference-tree = {
        enable = lib.mkEnableOption "one ghq reference tree shared by this host's participating accounts";
        participants = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Accounts that read the shared tree through the writer's group; none of them can write it.";
        };
        writer = lib.mkOption {
          type = lib.types.str;
          default = if isDarwin then "_ghq" else "ghq";
          description = "System account, and same-named group, that alone owns and writes the shared tree.";
        };
        root = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/ghq";
          description = "Shared ghq root.";
        };
        allowedProtocols = lib.mkOption {
          type = lib.types.listOf (lib.types.strMatching "[a-z][a-z0-9+.-]*");
          default = [ "https" ];
          description = "Git protocols the writer may fetch over; every other protocol is refused.";
        };
      };
    };
in
{
  flake.modules.nixos.shared-reference-tree-options = options false;
  flake.modules.darwin.shared-reference-tree-options = options true;
}
