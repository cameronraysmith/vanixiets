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
        rootForms = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          internal = true;
          readOnly = true;
          description = "Every path git may resolve the root to, canonical form first; each adapter defines it.";
        };
        writerId = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          description = "Darwin only: the operator-approved UID, also used as GID, of the writer account; NixOS allocates its own.";
        };
        allowedProtocols = lib.mkOption {
          type = lib.types.listOf (lib.types.strMatching "[a-z][a-z0-9+.-]*");
          default = [ "https" ];
          description = "Git protocols the writer may fetch over; every other protocol is refused.";
        };
      };
    };
  # A safe.directory entry trusts the shared tree's repositories, written by
  # another account, whenever it is `*` or a `<dir>/*` whose `<dir>` encloses the
  # root. `roots` lists every path form git may resolve the root to, canonical
  # form first; a participant must carry exactly the canonical root wildcard.
  safeDirectoriesConform =
    {
      roots,
      participant,
    }:
    entries:
    let
      encloses =
        entry:
        entry == "*"
        ||
          lib.hasSuffix "/*" entry
          && lib.any (
            root:
            let
              dir = lib.removeSuffix "*" entry;
            in
            dir != "${root}/" && lib.hasPrefix dir "${root}/"
          ) roots;
    in
    if participant then entries == [ "${lib.head roots}/*" ] else !(lib.any encloses entries);
in
{
  flake.modules.nixos.shared-reference-tree-options = options false;
  flake.modules.darwin.shared-reference-tree-options = options true;
  flake.lib.sharedReferenceTreeSafeDirectoriesConform = safeDirectoriesConform;
}
