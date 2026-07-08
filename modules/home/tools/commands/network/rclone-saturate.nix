{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "rclone-saturate";
          runtimeInputs = [ pkgs.rclone ];
          text = ''
            if [ "$#" -lt 2 ]; then
              echo "usage: rclone-saturate SRC DST [extra rclone flags...]" >&2
              echo "  fat-pipe, rate-safe cross-cloud streaming defaults; trailing flags override." >&2
              exit 2
            fi
            src="$1"
            dst="$2"
            shift 2
            progress=()
            [ -t 1 ] && progress=(--progress)
            exec rclone copy "$src" "$dst" \
              --transfers 32 --checkers 32 \
              --s3-upload-concurrency 8 --s3-chunk-size 64M \
              --multi-thread-cutoff 128M --multi-thread-streams 8 \
              --order-by size,mixed \
              --max-connections 128 \
              "''${progress[@]}" \
              "$@"
          '';
        })
      ];
    };
}
