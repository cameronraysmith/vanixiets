# Keeps secret files placed in a home by hand private to their owner.
#
# The sops age key (~/.config/sops/age/keys.txt) and ssh private keys are
# copied in by hand, so nothing else decides their mode: a key written with the
# default umask is readable by every other local account. Each activation
# tightens those paths (modules/home/core/secret-file-modes.sh) and logs every
# change; it never creates a path, and leaves symlinks, public keys,
# known_hosts, config and authorized_keys alone. Imported by core for people's
# homes and by omnigent-worker for agent accounts, which hold their own
# credentials.
{ config, ... }:
let
  program =
    pkgs:
    pkgs.writeShellApplication {
      name = "secret-file-modes";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.findutils
      ];
      text = builtins.readFile ./secret-file-modes.sh;
    };
in
{
  flake.lib.secretFileModesProgram = program;

  flake.modules.homeManager.secret-file-modes =
    { lib, pkgs, ... }:
    {
      # "$HOME" rather than the declared home directory: home-manager's
      # activation sanity check requires them to be equal, and the worker
      # module rejects activation text naming a /home or /Users path.
      home.activation.secretFileModes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe (program pkgs)} "$HOME"
      '';
    };

  flake.modules.homeManager.core.imports = [ config.flake.modules.homeManager.secret-file-modes ];
}
