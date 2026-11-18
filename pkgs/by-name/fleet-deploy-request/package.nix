# fleet-deploy-request: the forced command of the deployer account on
# cinnabar (openspec change delegate-fleet-deploys, design D1-D12). The
# NixOS module modules/nixos/fleet-deployer.nix wraps it with clan on PATH
# and FLEET_DEPLOY_CONFIG, rendered from flake.lib.fleetDeployer.requestConfig.
# checks.x86_64-linux.fleet-deploy-request runs its parser over fixtures.
{
  lib,
  writers,
  makeWrapper,
  symlinkJoin,
  git,
  openssh,
  nix,
  coreutils,
}:
let
  unwrapped = writers.writePython3Bin "fleet-deploy-request" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./fleet_deploy_request.py);
in
symlinkJoin {
  name = "fleet-deploy-request";
  paths = [ unwrapped ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/fleet-deploy-request \
      --prefix PATH : ${
        lib.makeBinPath [
          git
          openssh
          nix
          coreutils
        ]
      }
  '';
  meta = {
    description = "Forced command of the fleet deployer: deploy a merged commit to one allowed host";
    license = lib.licenses.mit;
    mainProgram = "fleet-deploy-request";
  };
}
