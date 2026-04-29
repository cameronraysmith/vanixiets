{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "ngc";
          runtimeInputs = with pkgs; [ nix ];
          text = ''
            case "''${1:-}" in
              -h|--help)
                cat <<'HELP'
            Nix garbage collection for system and user

            Usage: ngc

            Performs garbage collection on Nix store:
              1. System-wide GC (removes profiles older than 7 days)
              2. User GC (removes profiles older than 7 days)
              3. Optimizes Nix store (hardlinks identical files)

            Note: Requires sudo for system-wide collection

            Example:
              ngc    # Run full garbage collection
            HELP
                exit 0
                ;;
            esac

            set -x
            sudo nix-collect-garbage --delete-older-than 7d
            nix-collect-garbage --delete-older-than 7d
            nix store optimise
          '';
          meta.description = "Nix garbage collection for system and user";
        })
      ];
    };
}
