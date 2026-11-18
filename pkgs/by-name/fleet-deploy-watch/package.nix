# fleet-deploy-watch: the rollback watcher the fleet deployer starts on a
# target before it deploys (openspec change delegate-fleet-deploys, design
# D10). modules/system/fleet-deploy-target.nix installs it on every deploy
# target at /run/current-system/sw/bin/fleet-deploy-watch.
{
  lib,
  writeShellApplication,
  coreutils,
  gawk,
  nix,
}:
writeShellApplication {
  name = "fleet-deploy-watch";
  runtimeInputs = [
    coreutils
    gawk
    nix
  ];
  # The script handles every error path itself (see its header).
  bashOptions = [ "nounset" ];
  text = builtins.readFile ./fleet-deploy-watch.sh;
  meta = {
    description = "Return a host to its previous system unless the fleet deployer confirms it";
    license = lib.licenses.mit;
    mainProgram = "fleet-deploy-watch";
  };
}
