# fleet-deploy-watch: the rollback watcher the fleet deployer starts on a
# target before it deploys (openspec change delegate-fleet-deploys, design
# D10). modules/system/fleet-deploy-target.nix installs it on every deploy
# target at /run/current-system/sw/bin/fleet-deploy-watch and, on darwin,
# declares the launchd job `--arm` bootstraps into the system domain.
# launchctl is macOS's own /bin/launchctl.
{
  lib,
  writeShellApplication,
  coreutils,
  nix,
}:
writeShellApplication {
  name = "fleet-deploy-watch";
  runtimeInputs = [
    coreutils
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
