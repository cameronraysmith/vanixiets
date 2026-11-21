{ inputs, lib, ... }:
{
  # ACP children receive omnigent's base allowlist, each agent's env_passthrough
  # and, since omnigent 0.23.0, every name in the host's
  # OMNIGENT_RUNNER_ENV_PASSTHROUGH. Values that belong to one agent are therefore
  # set by that agent's own command, never by the host environment.
  # DOCKER_HOST and CONTAINER_HOST locate a worker's rootless podman socket; without
  # them Docker-API clients fall back to the rootful socket and podman runs locally,
  # where the host unit's NoNewPrivileges prevents it from starting.
  flake.lib.omnigentACP =
    pkgs:
    let
      pi-acp = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi-acp;
      # pi-acp drives atomic, with Atomic's state under ~/.atomic/agent
      # (omnigent-worker-login prepares the same directory). Only this row
      # receives the two selectors, checks.omnigent-acp-spawn-env verifies it.
      atomic-acp = pkgs.writeShellScriptBin "atomic-acp" ''
        export PI_ACP_PI_COMMAND=atomic
        export PI_CODING_AGENT_DIR="$HOME/.atomic/agent"
        exec ${lib.getExe pi-acp} "$@"
      '';
    in
    {
      agents = [
        {
          name = "Atomic";
          command = lib.getExe atomic-acp;
          omnigent_mcp = false;
          inject_system_prompt = false;
          env_passthrough = [
            "DOCKER_HOST"
            "CONTAINER_HOST"
          ];
        }
        # omp v18.1.13 resolves state via PI_CODING_AGENT_DIR (oh-my-pi
        # packages/utils/src/dirs.ts:438-473). Never pass PI_CODING_AGENT_DIR here:
        # it would silently share Atomic state. Container socket locators carry no
        # state and are allowed.
        {
          name = "Oh My Pi";
          command = "omp acp";
          omnigent_mcp = false;
          inject_system_prompt = false;
          env_passthrough = [
            "DOCKER_HOST"
            "CONTAINER_HOST"
          ];
        }
      ];
    };
}
