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
            gnugrep
          ];
          text = ''
            usage() {
              cat <<'HELP'
            List publications under a nix-releases channel from s3://nix-releases.

            Usage: nix-channel-pubs [-c CHANNEL] [-n N] [-s SUBSTRING]

            Options:
              -c CHANNEL    Channel name as it appears at https://channels.nixos.org/
                            (default: nixos-unstable-small). The S3 prefix is derived
                            with the same rule the upstream mirror script uses
                            (NixOS/nixos-channel-scripts, mirror-nixos-branch.pl):
                            the special case 'nixpkgs-unstable' resolves to
                            s3://nix-releases/nixpkgs/; otherwise CHANNEL is split
                            on its first '-' into <a>-<b> and resolves to
                            s3://nix-releases/<a>/<b>/.
              -n N          Most recent publications to show (default 10; 0 = all)
              -s SUBSTRING  Optional substring filter on the publication dirname
                            (e.g. '26.05pre' or a partial rev)
              -h            Show this help and exit

            Output: one row per publication with timestamp, size, and the
            nixexprs.tar.xz key. Prepend https://releases.nixos.org/ to construct
            a flake input URL for the corresponding rev.

            Examples:
              nix-channel-pubs
              nix-channel-pubs -c nixos-unstable -n 30
              nix-channel-pubs -c nixos-25.11
              nix-channel-pubs -c nixpkgs-25.11-darwin -n 5
              nix-channel-pubs -c nixpkgs-unstable
              nix-channel-pubs -c nixos-unstable-small -s 989
            HELP
            }

            channel=nixos-unstable-small
            n=10
            substring=

            while getopts ":c:n:s:h" opt; do
              case "$opt" in
                c) channel="$OPTARG" ;;
                n) n="$OPTARG" ;;
                s) substring="$OPTARG" ;;
                h) usage; exit 0 ;;
                \?) echo "unknown option: -$OPTARG" >&2; usage >&2; exit 2 ;;
                :)  echo "option -$OPTARG requires an argument" >&2; exit 2 ;;
              esac
            done

            if [[ "$channel" != *-* ]]; then
              echo "invalid channel '$channel': expected '<scope>-<name>' (e.g. nixos-unstable, nixpkgs-25.11-darwin)" >&2
              exit 2
            fi

            if [[ "$channel" == "nixpkgs-unstable" ]]; then
              prefix=nixpkgs
            else
              prefix="''${channel%%-*}/''${channel#*-}"
            fi

            export AWS_REGION=eu-west-1
            glob="s3://nix-releases/$prefix/*/nixexprs.tar.xz"

            if [[ -n "$substring" ]]; then
              filter=(grep -F -- "$substring")
            else
              filter=(cat)
            fi

            if [[ "$n" = "0" ]]; then
              s5cmd ls -H "$glob" | "''${filter[@]}"
            else
              s5cmd ls -H "$glob" | "''${filter[@]}" | tail -n "$n"
            fi
          '';
          meta.description = "list nix channel publications from s3://nix-releases";
        })
      ];
    };
}
