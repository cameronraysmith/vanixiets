{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "nix-channel-pubs";
          runtimeInputs = with pkgs; [
            s5cmd
            coreutils
          ];
          text = ''
            usage() {
              cat <<'HELP'
            List channel publications from the public s3://nix-releases bucket.

            Usage: nix-channel-pubs [-n N] [-t TREE] [-c CHANNEL] [-s SERIES]

            Options:
              -n N        Most recent publications to show (default 10; 0 = all)
              -t TREE     Top-level tree: nixos | nixpkgs (default nixos)
              -c CHANNEL  Channel under tree=nixos: unstable-small | unstable |
                          25.11 | 25.11-small | 25.05 (default unstable-small).
                          Ignored when tree=nixpkgs (which is flat, not channeled).
              -s SERIES   NixOS release series prefix (default 26.05)
              -h          Show this help and exit

            Output: one row per publication with timestamp, size, and the
            nixexprs.tar.xz key. Prepend https://releases.nixos.org/ to construct
            a flake input URL for the corresponding rev.

            Examples:
              nix-channel-pubs                              # 10 most recent of nixos/unstable-small/26.05
              nix-channel-pubs -n 30                        # 30 most recent (same tree/channel/series)
              nix-channel-pubs -n 0                         # all (no tail)
              nix-channel-pubs -s 26.11                     # different release series
              nix-channel-pubs -t nixpkgs                   # nixpkgs tree (flat, no channel)
              nix-channel-pubs -t nixos -c unstable         # nixos/unstable channel
              nix-channel-pubs -t nixos -c 25.11 -s 25.11   # 25.11 stable channel
            HELP
            }

            n=10
            tree=nixos
            channel=unstable-small
            series=26.05

            while getopts ":n:t:c:s:h" opt; do
              case "$opt" in
                n) n="$OPTARG" ;;
                t) tree="$OPTARG" ;;
                c) channel="$OPTARG" ;;
                s) series="$OPTARG" ;;
                h) usage; exit 0 ;;
                \?) echo "unknown option: -$OPTARG" >&2; usage >&2; exit 2 ;;
                :)  echo "option -$OPTARG requires an argument" >&2; exit 2 ;;
              esac
            done

            case "$tree" in
              nixos)   prefix="s3://nix-releases/nixos/$channel/$tree-''${series}pre*" ;;
              nixpkgs) prefix="s3://nix-releases/nixpkgs/$tree-''${series}pre*" ;;
              *) echo "tree must be 'nixos' or 'nixpkgs', got: $tree" >&2; exit 2 ;;
            esac

            export AWS_REGION=eu-west-1
            cmd=(s5cmd ls -H "$prefix/nixexprs.tar.xz")
            if [ "$n" = "0" ]; then
              "''${cmd[@]}"
            else
              "''${cmd[@]}" | tail -n "$n"
            fi
          '';
          meta.description = "list nix channel publications from s3://nix-releases";
        })
      ];
    };
}
