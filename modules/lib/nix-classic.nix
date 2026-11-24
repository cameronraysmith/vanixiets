# nixClassic: the fleet's Nix (flake.lib.fleetNix) whose `nix` is iets'
# classic mode (numtide/iets lib.mkClassic) where the user has opted in, with
# `nix-stock` beside it for the real one. Every other executable is the fleet
# Nix's own. The default devShell carries it on every host and home-manager's
# nixClassic.enable installs it, but `nix` evaluates with iets only when the
# marker file ${XDG_CONFIG_HOME:-~/.config}/nix-classic/enabled exists (that
# option writes it) and the caller is not root (sudo keeps the user's PATH and
# HOME on darwin). Otherwise it execs the fleet's Nix with the same argv and
# environment: dash, unlike bash, exports nothing of its own.
#
# Classic mode falls back to the real nix, before evaluating anything, when a
# client setting it lacks differs from Nix's default (iets src/config.rs
# UNIMPLEMENTED), and the fleet's nix.conf sets plugin-files (the grpc store
# dispatcher), so unwrapped it would never evaluate. `nix` therefore appends a
# marked `plugin-files =` line to NIX_CONFIG for iets and points
# IETS_NIX_BIN_DIR at `restore`, which deletes that line again before it execs
# the real nix. A fallback (iets execs IETS_NIX_BIN_DIR/nix with its own
# environment, src/cli/classic/mod.rs) and `nix-stock` thus run the real nix
# with the configuration it would have had. What iets itself spawns, such as
# the shell of a native `nix develop`, keeps the line; a nix client there
# loses only the plugin, which as a daemon client it does not load anyway
# (builds dispatch through the daemon's nix.conf).
#
# The tracing cache is off unless IETS_CACHE is set: a hit is only as right as
# iets' record of what the evaluation read, and an omission there would answer
# with a stale result silently.
{
  config,
  inputs,
  lib,
  ...
}:
{
  flake.lib.nixClassic =
    pkgs:
    let
      nix = config.flake.lib.fleetNix pkgs;
      classic =
        inputs.iets.lib.mkClassic pkgs inputs.iets.packages.${pkgs.stdenv.hostPlatform.system}.default
          nix;
      mark = "plugin-files = # nix-classic: for iets only";
      restore = pkgs.writeShellApplication {
        name = "nix";
        text = ''
          config=""
          while IFS= read -r line; do
            [ "$line" = ${lib.escapeShellArg mark} ] || config+=''${config:+$'\n'}$line
          done <<<"''${NIX_CONFIG-}"
          if [ -n "$config" ]; then export NIX_CONFIG=$config; else unset NIX_CONFIG; fi
          exec ${lib.getExe' nix "nix"} "$@"
        '';
      };
    in
    pkgs.runCommand "nix-classic-${nix.version}"
      {
        passthru = {
          inherit classic restore nix;
        };
        meta.mainProgram = "nix";
      }
      ''
        mkdir -p $out/bin
        for f in ${nix}/bin/*; do
          ln -s $f $out/bin/
        done
        rm $out/bin/nix
        cat >$out/bin/nix <<'EOF'
        #!${lib.getExe pkgs.dash}
        if [ -e "''${XDG_CONFIG_HOME:-$HOME/.config}/nix-classic/enabled" ] && [ "$(${lib.getExe' pkgs.coreutils "id"} -u)" != 0 ]; then
          export IETS_NIX_BIN_DIR=${restore}/bin
          export IETS_CACHE="''${IETS_CACHE:-0}"
          export NIX_CONFIG="''${NIX_CONFIG:+$NIX_CONFIG
        }"${lib.escapeShellArg mark}
          exec ${classic}/bin/nix "$@"
        fi
        exec ${lib.getExe' nix "nix"} "$@"
        EOF
        chmod +x $out/bin/nix
        ln -s ${lib.getExe restore} $out/bin/nix-stock
      '';
}
